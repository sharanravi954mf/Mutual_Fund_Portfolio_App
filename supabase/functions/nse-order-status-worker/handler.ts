import {
  buildNseOrderStatusRequest,
  type NseOrderStatusSource,
  parseNseOrderStatusResponse,
} from "../_shared/nse/nse_order_status.ts";
import { createNseEvidenceCall } from "../_shared/nse/nse_evidence_call.ts";
import type { SafeIntegrationHeaderMetadata } from "../_shared/nse/nse_types.ts";

export type ClaimedOrderStatusEvent = {
  event_outbox_id: string | null;
  integration_operation_id: string | null;
  attempt: number;
  claim_state: string;
  claim_token: string | null;
};
export type OrderStatusResult = {
  kind: "response";
  status: number;
  contentType: string | null;
  safeHeaderMetadata: SafeIntegrationHeaderMetadata;
  rawBody: string;
} | {
  kind: "failure";
  errorCategory: string;
  timeout: boolean;
  networkFailure: boolean;
};
export interface OrderStatusPersistence {
  recoverExpired(
    input: { eventOutboxId: string; maxAttempts: number },
  ): Promise<unknown>;
  claimEvent(
    input: { eventOutboxId: string; maxAttempts: number; leaseSeconds: number },
  ): Promise<ClaimedOrderStatusEvent>;
  loadSource(id: string): Promise<NseOrderStatusSource>;
  start(input: Record<string, unknown>): Promise<unknown>;
  finish(input: Record<string, unknown>): Promise<unknown>;
}
export interface OrderStatusGateway {
  requestHeaderMetadata(body: string): SafeIntegrationHeaderMetadata;
  submit(body: string): Promise<OrderStatusResult>;
}
export type OrderStatusWorkerDependencies = {
  internalToken: string;
  persistence: OrderStatusPersistence;
  gateway: OrderStatusGateway;
  maxAttempts?: number;
  leaseSeconds?: number;
  now?: () => Date;
  uuid?: () => string;
};
const id =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const retryable = new Set([408, 429, 500, 502, 503, 504]);
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
const token = (request: Request) =>
  request.headers.get("authorization")?.replace(/^Bearer\s+/, "").trim();
export function createNseOrderStatusHandler(
  deps: OrderStatusWorkerDependencies,
) {
  const now = deps.now ?? (() => new Date());
  const uuid = deps.uuid ?? (() => crypto.randomUUID());
  const maxAttempts = deps.maxAttempts ?? 3;
  const leaseSeconds = deps.leaseSeconds ?? 120;
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json({ error: { code: "method_not_allowed" } }, 405);
    }
    if (!deps.internalToken || token(request) !== deps.internalToken) {
      return json({ error: { code: "not_authorized" } }, 403);
    }
    let input: unknown;
    try {
      input = await request.json();
    } catch {
      return json({ error: { code: "invalid_json" } }, 400);
    }
    const eventId =
      input != null && typeof input === "object" && !Array.isArray(input)
        ? (input as Record<string, unknown>).event_outbox_id
        : null;
    if (typeof eventId !== "string" || !id.test(eventId)) {
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
    if (!event.integration_operation_id || !event.claim_token) {
      return json({ error: { code: "requested_event_not_found" } }, 404);
    }
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
    const callId = uuid();
    const started = now();
    const call = createNseEvidenceCall(() => deps.gateway.submit(serialized));
    try {
      await call.persist(() =>
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
    const result = await call.submit();
    const completed = now();
    const elapsedMs = Math.max(0, completed.getTime() - started.getTime());
    if (result.kind === "failure") {
      await call.persist(() =>
        deps.persistence.finish({
          eventOutboxId: eventId,
          claimToken: event.claim_token!,
          callId,
          responsePayload: "",
          responseContentType: null,
          responseHeaderMetadata: {},
          httpStatus: null,
          nativeStatusValue: null,
          nativeRemarkCategory: "order_status_transport_failure",
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
            : "order_status_attempts_exhausted",
        },
      }, 202);
    }
    let observation = {
      nativeStatus: null as string | null,
      nativeRemarkCategory: "order_status_http_failure",
      recordCount: 0,
      projectedRecords: [] as Array<Record<string, string | number | null>>,
    };
    if (result.status >= 200 && result.status < 300) {
      try {
        observation = parseNseOrderStatusResponse(result.rawBody);
      } catch {
        observation.nativeRemarkCategory = "order_status_response_invalid";
      }
    }
    const outcome = result.status < 200 || result.status >= 300
      ? "HTTP_FAILURE"
      : observation.nativeStatus === "S"
      ? "SUCCESS"
      : "BUSINESS_FAILURE";
    await call.persist(() =>
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
        normalizedOutcome: outcome,
        errorCategory: outcome === "SUCCESS"
          ? null
          : observation.nativeRemarkCategory,
        timeoutOccurred: false,
        networkFailure: false,
        completedAt: completed.toISOString(),
        elapsedMs,
        maxAttempts,
      })
    );
    const canRetry = outcome === "HTTP_FAILURE" &&
      retryable.has(result.status) && event.attempt < maxAttempts;
    return json(
      {
        data: {
          outcome: canRetry
            ? "safe_read_retry_available"
            : outcome === "SUCCESS"
            ? "order_status_report_received"
            : "order_status_failed",
          record_count: observation.recordCount,
          records: observation.projectedRecords,
        },
      },
      canRetry
        ? 202
        : outcome === "SUCCESS"
        ? 200
        : outcome === "HTTP_FAILURE"
        ? 502
        : 202,
    );
  };
}
