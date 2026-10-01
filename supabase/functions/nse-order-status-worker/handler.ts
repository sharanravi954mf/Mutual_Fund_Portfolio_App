import {
  buildNseOrderStatusRequest,
  parseNseOrderStatusResponse,
} from "../_shared/nse/nse_order_status.ts";
import { createNseEvidenceCall } from "../_shared/nse/nse_evidence_call.ts";
import type {
  ClaimedOrderStatusEvent,
  OrderStatusGateway,
  OrderStatusPersistence,
} from "./types.ts";

export type OrderStatusWorkerDependencies = {
  internalToken: string;
  persistence: OrderStatusPersistence;
  gateway: OrderStatusGateway;
  maxAttempts?: number;
  leaseSeconds?: number;
  now?: () => Date;
  uuid?: () => string;
};
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const retryableReadHttpStatuses = new Set([408, 429, 500, 502, 503, 504]);
function isRetryableReadHttpFailure(status: number) {
  return retryableReadHttpStatuses.has(status);
}
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
function bearer(request: Request) {
  const value = request.headers.get("authorization");
  return value?.startsWith("Bearer ") ? value.slice(7).trim() : null;
}
export function createNseOrderStatusHandler(
  deps: OrderStatusWorkerDependencies,
) {
  const now = deps.now ?? (() => new Date());
  const uuid = deps.uuid ?? (() => crypto.randomUUID());
  const maxAttempts = deps.maxAttempts ?? 3;
  const leaseSeconds = deps.leaseSeconds ?? 120;
  const handle = async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json({ error: { code: "method_not_allowed" } }, 405);
    }
    if (!deps.internalToken || bearer(request) !== deps.internalToken) {
      return json({ error: { code: "not_authorized" } }, 403);
    }
    let input: unknown;
    try {
      input = await request.json();
    } catch {
      return json({ error: { code: "invalid_json" } }, 400);
    }
    if (input == null || typeof input !== "object" || Array.isArray(input)) {
      return json({ error: { code: "invalid_request_body" } }, 400);
    }
    const eventId = (input as Record<string, unknown>).event_outbox_id;
    if (typeof eventId !== "string" || !uuidPattern.test(eventId)) {
      return json({ error: { code: "event_outbox_id_required" } }, 400);
    }
    try {
      await deps.persistence.recoverExpired({
        eventOutboxId: eventId,
        maxAttempts,
      });
    } catch {
      return json({ error: { code: "order_status_recovery_failed" } }, 500);
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
    let source;
    try {
      source = await deps.persistence.loadSource(
        event.integration_operation_id,
      );
    } catch {
      return json({ error: { code: "order_status_source_unavailable" } }, 503);
    }
    let serialized: string;
    try {
      serialized = JSON.stringify(buildNseOrderStatusRequest(source));
    } catch {
      return json({ error: { code: "order_status_source_invalid" } }, 422);
    }
    const callId = uuid();
    const started = now();
    const evidenceCall = createNseEvidenceCall(() =>
      deps.gateway.submit(serialized)
    );
    try {
      await evidenceCall.persist(() =>
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
    const result = await evidenceCall.submit();
    const completed = now();
    const elapsedMs = Math.max(0, completed.getTime() - started.getTime());
    if (result.kind === "failure") {
      await evidenceCall.persist(() =>
        deps.persistence.finish({
          eventOutboxId: eventId,
          claimToken: event.claim_token!,
          callId,
          responsePayload: "",
          responseContentType: null,
          responseHeaderMetadata: {},
          httpStatus: null,
          nativeStatusValue: null,
          nativeRemarkCategory: "order_status_transport_failed",
          normalizedOutcome: "TRANSPORT_FAILURE",
          errorCategory: result.errorCategory,
          timeoutOccurred: result.timeout,
          networkFailure: result.networkFailure,
          completedAt: completed.toISOString(),
          elapsedMs,
          maxAttempts,
        })
      );
      return json({
        data: {
          outcome: event.attempt < maxAttempts
            ? "safe_read_retry_available"
            : "order_status_transport_failed",
        },
      }, 202);
    }
    const isHttpSuccess = result.status >= 200 && result.status < 300;
    let observation = {
      nativeStatus: null as "S" | "F" | null,
      nativeRemarkCategory: "order_status_http_failure",
      success: false,
      recordCount: 0,
      validCount: 0,
      invalidCount: 0,
      otherCount: 0,
    };
    if (isHttpSuccess) {
      observation = parseNseOrderStatusResponse(result.rawBody, source.request);
    }
    const normalizedOutcome = !isHttpSuccess
      ? "HTTP_FAILURE" as const
      : observation.success
      ? "SUCCESS" as const
      : "BUSINESS_FAILURE" as const;
    const retryableHttpFailure = normalizedOutcome === "HTTP_FAILURE" &&
      isRetryableReadHttpFailure(result.status);
    await evidenceCall.persist(() =>
      deps.persistence.finish({
        eventOutboxId: eventId,
        claimToken: event.claim_token!,
        callId,
        responsePayload: result.rawBody,
        responseContentType: result.contentType,
        responseHeaderMetadata: result.safeHeaderMetadata,
        httpStatus: result.status,
        nativeStatusValue: observation.nativeStatus,
        nativeRemarkCategory: observation.nativeRemarkCategory,
        normalizedOutcome,
        errorCategory: normalizedOutcome === "SUCCESS"
          ? null
          : observation.nativeRemarkCategory,
        timeoutOccurred: false,
        networkFailure: false,
        completedAt: completed.toISOString(),
        elapsedMs,
        maxAttempts,
      })
    );
    if (retryableHttpFailure) {
      const retryAvailable = event.attempt < maxAttempts;
      return json({
        data: {
          outcome: retryAvailable
            ? "safe_read_retry_available"
            : "order_status_http_attempts_exhausted",
        },
      }, retryAvailable ? 202 : 502);
    }
    const status = normalizedOutcome === "SUCCESS"
      ? 200
      : isHttpSuccess
      ? 202
      : 502;
    return json({
      data: {
        outcome: observation.nativeRemarkCategory,
        record_count: observation.recordCount,
      },
    }, status);
  };
  return async (request: Request): Promise<Response> => {
    try {
      return await handle(request);
    } catch {
      return json({ error: { code: "order_status_worker_failed" } }, 500);
    }
  };
}
