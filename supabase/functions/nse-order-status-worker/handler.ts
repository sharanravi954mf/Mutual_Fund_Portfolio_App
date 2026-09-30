import {
  buildNseOrderStatusRequest,
  parseNseOrderStatusResponse,
} from "../_shared/nse/nse_order_status.ts";
import { createNseEvidenceCall } from "../_shared/nse/nse_evidence_call.ts";
import type {
  ClaimedOrderStatusEvent,
  OrderStatusGateway,
  OrderStatusPersistence,
} from "./adapters.ts";

export type OrderStatusWorkerDependencies = {
  internalToken: string;
  persistence: OrderStatusPersistence;
  gateway: OrderStatusGateway;
  maxAttempts?: number;
  leaseSeconds?: number;
  now?: () => Date;
  uuid?: () => string;
};
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const retryable = new Set([408, 429, 500, 502, 503, 504]);
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
const bearer = (request: Request) =>
  request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/)?.[1].trim() ??
    null;

export function createNseOrderStatusHandler(
  deps: OrderStatusWorkerDependencies,
) {
  const now = deps.now ?? (() => new Date());
  const nextId = deps.uuid ?? (() => crypto.randomUUID());
  const maxAttempts = deps.maxAttempts ?? 3;
  const leaseSeconds = deps.leaseSeconds ?? 120;
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json({ error: { code: "method_not_allowed" } }, 405);
    }
    if (!deps.internalToken || bearer(request) !== deps.internalToken) {
      return json({ error: { code: "not_authorized" } }, 403);
    }
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return json({ error: { code: "invalid_json" } }, 400);
    }
    const eventId = body && typeof body === "object" && !Array.isArray(body)
      ? (body as Record<string, unknown>).event_outbox_id
      : null;
    if (typeof eventId !== "string" || !uuid.test(eventId)) {
      return json({ error: { code: "event_outbox_id_required" } }, 400);
    }
    try {
      await deps.persistence.recoverExpired({
        eventOutboxId: eventId,
        maxAttempts,
      });
    } catch {
      return json({ error: { code: "recovery_failed" } }, 500);
    }
    let event: ClaimedOrderStatusEvent;
    try {
      event = await deps.persistence.claimEvent({
        eventOutboxId: eventId,
        maxAttempts,
        leaseSeconds,
      });
    } catch {
      return json({ error: { code: "claim_failed" } }, 500);
    }
    if (
      event.claim_state === "no_event" || !event.integration_operation_id ||
      !event.claim_token
    ) return json({ error: { code: "requested_event_not_found" } }, 404);
    let serialized: string;
    try {
      serialized = JSON.stringify(
        buildNseOrderStatusRequest(
          await deps.persistence.loadSource(event.integration_operation_id),
        ),
      );
    } catch {
      return json({ error: { code: "order_status_source_invalid" } }, 422);
    }
    const callId = nextId();
    const started = now();
    const evidence = createNseEvidenceCall(() =>
      deps.gateway.submit(serialized)
    );
    try {
      await evidence.persist(() =>
        deps.persistence.start({
          eventOutboxId: eventId,
          claimToken: event.claim_token!,
          callId,
          requestPayload: serialized,
          requestHeaderMetadata: deps.gateway.requestHeaderMetadata(serialized),
          startedAt: started.toISOString(),
        })
      );
    } catch {
      return json({ error: { code: "request_evidence_failed" } }, 500);
    }
    const result = await evidence.submit();
    const completed = now();
    const elapsedMs = Math.max(0, completed.getTime() - started.getTime());
    const finish = (
      input: Omit<
        Parameters<OrderStatusPersistence["finish"]>[0],
        | "eventOutboxId"
        | "claimToken"
        | "callId"
        | "completedAt"
        | "elapsedMs"
        | "maxAttempts"
      >,
    ) =>
      evidence.persist(() =>
        deps.persistence.finish({
          ...input,
          eventOutboxId: eventId,
          claimToken: event.claim_token!,
          callId,
          completedAt: completed.toISOString(),
          elapsedMs,
          maxAttempts,
        })
      );
    if (result.kind === "failure") {
      await finish({
        responsePayload: "",
        responseContentType: null,
        responseHeaderMetadata: {},
        httpStatus: null,
        nativeStatusValue: null,
        nativeRemarkCategory: "transport_failure",
        normalizedOutcome: "TRANSPORT_FAILURE",
        errorCategory: result.errorCategory,
        timeoutOccurred: result.timeout,
        networkFailure: result.networkFailure,
        recordCount: 0,
        invalidCount: 0,
      });
      return json({
        data: {
          outcome: event.attempt < maxAttempts
            ? "safe_read_retry_available"
            : "read_attempts_exhausted",
        },
      }, 202);
    }
    const observation = result.status >= 200 && result.status < 300
      ? parseNseOrderStatusResponse(result.rawBody)
      : {
        responseStatus: null,
        recordCount: 0,
        invalidCount: 0,
        remarkCategory: "http_failure",
      };
    const outcome = result.status < 200 || result.status >= 300
      ? "HTTP_FAILURE" as const
      : observation.responseStatus === "S"
      ? "SUCCESS" as const
      : "BUSINESS_FAILURE" as const;
    await finish({
      responsePayload: result.rawBody,
      responseContentType: result.contentType,
      responseHeaderMetadata: result.safeHeaderMetadata,
      httpStatus: result.status,
      nativeStatusValue: observation.responseStatus,
      nativeRemarkCategory: observation.remarkCategory,
      normalizedOutcome: outcome,
      errorCategory: outcome === "SUCCESS" ? null : observation.remarkCategory,
      timeoutOccurred: false,
      networkFailure: false,
      recordCount: observation.recordCount,
      invalidCount: observation.invalidCount,
    });
    if (outcome === "HTTP_FAILURE" && retryable.has(result.status)) {
      return json({
        data: {
          outcome: event.attempt < maxAttempts
            ? "safe_read_retry_available"
            : "read_attempts_exhausted",
        },
      }, event.attempt < maxAttempts ? 202 : 502);
    }
    return json(
      {
        data: {
          outcome: outcome === "SUCCESS"
            ? "report_success"
            : "report_business_failure",
          record_count: observation.recordCount,
          invalid_count: observation.invalidCount,
        },
      },
      outcome === "SUCCESS" ? 200 : outcome === "BUSINESS_FAILURE" ? 202 : 502,
    );
  };
}
