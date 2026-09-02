import {
  buildNseClientMasterRequest,
  parseNseClientMasterResponse,
} from "../_shared/nse/nse_ucc_verification.ts";
import type {
  ClaimedVerificationEvent,
  VerificationGateway,
  VerificationPersistence,
} from "./types.ts";

export type VerificationWorkerDependencies = {
  internalToken: string;
  persistence: VerificationPersistence;
  gateway: VerificationGateway;
  maxAttempts?: number;
  leaseSeconds?: number;
  now?: () => Date;
  uuid?: () => string;
};
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
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
async function twice(action: () => Promise<unknown>) {
  try {
    await action();
  } catch {
    await action();
  }
}

export function createNseUccReconciliationHandler(
  deps: VerificationWorkerDependencies,
) {
  const now = deps.now ?? (() => new Date());
  const uuid = deps.uuid ?? (() => crypto.randomUUID());
  const maxAttempts = deps.maxAttempts ?? 3;
  const leaseSeconds = deps.leaseSeconds ?? 120;
  return async (request: Request): Promise<Response> => {
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
      return json({ error: { code: "verification_recovery_failed" } }, 500);
    }
    let event: ClaimedVerificationEvent;
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
      return json({ error: { code: "verification_source_unavailable" } }, 503);
    }
    let serialized: string;
    try {
      serialized = JSON.stringify(buildNseClientMasterRequest(source));
    } catch {
      return json({ error: { code: "verification_source_invalid" } }, 422);
    }
    const callId = uuid();
    const started = now();
    try {
      await twice(() =>
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
    const result = await deps.gateway.submit(serialized);
    const completed = now();
    const elapsedMs = Math.max(0, completed.getTime() - started.getTime());
    if (result.kind === "failure") {
      await twice(() =>
        deps.persistence.finish({
          eventOutboxId: eventId,
          claimToken: event.claim_token!,
          callId,
          responsePayload: "",
          responseContentType: null,
          responseHeaderMetadata: {},
          httpStatus: null,
          nativeStatusValue: null,
          nativeRemarkCategory: "verification_transport_failed",
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
            : "verification_transport_failed",
        },
      }, 202);
    }
    const isHttpSuccess = result.status >= 200 && result.status < 300;
    let observation = {
      nativeStatus: null as string | null,
      nativeRemarkCategory: "client_master_http_failure",
      exactIdentityMatch: false,
      recordCount: 0,
    };
    if (isHttpSuccess) {
      try {
        observation = parseNseClientMasterResponse(
          result.rawBody,
          source.intended_client_code,
          source.pan,
        );
      } catch {
        observation.nativeRemarkCategory = "client_master_response_invalid";
      }
    }
    const normalizedOutcome = !isHttpSuccess
      ? "HTTP_FAILURE" as const
      : observation.exactIdentityMatch
      ? "SUCCESS" as const
      : "BUSINESS_FAILURE" as const;
    await twice(() =>
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
    await deps.persistence.distribute(
      source.target_operation_id,
      source.operation_id,
    );
    const status = normalizedOutcome === "SUCCESS"
      ? 200
      : isHttpSuccess
      ? 202
      : 502;
    return json({
      data: {
        outcome: observation.exactIdentityMatch
          ? "identity_confirmed"
          : "identity_not_confirmed",
        verification_purpose: source.verification_purpose,
        exact_identity_match: observation.exactIdentityMatch,
      },
    }, status);
  };
}
