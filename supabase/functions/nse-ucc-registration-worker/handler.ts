import {
  buildNseUccRequest,
  NseUccValidationError,
  parseNseUccResponse,
} from "../_shared/nse/nse_ucc.ts";
import { UccSourcePersistenceError } from "./types.ts";
import type { ClaimedUccEvent, UccGateway, UccPersistence } from "./types.ts";

export type UccWorkerDependencies = {
  internalToken: string;
  persistence: UccPersistence;
  gateway: UccGateway;
  maxAttempts?: number;
  leaseSeconds?: number;
  now?: () => Date;
  uuid?: () => string;
  log?: (entry: Record<string, unknown>) => void;
};
function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
function bearerToken(request: Request): string | null {
  const header = request.headers.get("authorization");
  if (header == null || !header.startsWith("Bearer ")) return null;
  return header.substring("Bearer ".length).trim() || null;
}
function validationCode(error: NseUccValidationError): string {
  return error.issues[0]?.code ?? "ucc_contract_validation_failed";
}
function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}
function log(
  dependencies: UccWorkerDependencies,
  event: ClaimedUccEvent,
  outcome: string,
  errorCode: string | null = null,
): void {
  dependencies.log?.({
    event_outbox_id: event.event_outbox_id,
    integration_operation_id: event.integration_operation_id,
    correlation_id: event.correlation_id,
    attempt: event.attempt,
    outcome,
    error_code: errorCode,
  });
}
async function persistIdempotently(
  action: () => Promise<unknown>,
): Promise<void> {
  try {
    await action();
  } catch {
    await action();
  }
}

export function createNseUccWorkerHandler(
  dependencies: UccWorkerDependencies,
): (request: Request) => Promise<Response> {
  const now = dependencies.now ?? (() => new Date());
  const uuid = dependencies.uuid ?? (() => crypto.randomUUID());
  const maxAttempts = dependencies.maxAttempts ?? 2;
  const leaseSeconds = dependencies.leaseSeconds ?? 120;
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return new Response("ok");
    if (request.method !== "POST") {
      return jsonResponse({ error: { code: "method_not_allowed" } }, 405);
    }
    if (
      dependencies.internalToken.trim().length === 0 ||
      bearerToken(request) !== dependencies.internalToken
    ) {
      return jsonResponse({ error: { code: "not_authorized" } }, 403);
    }
    let invocation: unknown;
    try {
      invocation = await request.json();
    } catch {
      return jsonResponse({ error: { code: "invalid_json" } }, 400);
    }
    if (
      invocation == null || typeof invocation !== "object" ||
      Array.isArray(invocation)
    ) {
      return jsonResponse({ error: { code: "invalid_request_body" } }, 400);
    }
    const requestedEventId =
      (invocation as Record<string, unknown>).event_outbox_id;
    if (requestedEventId == null) {
      return jsonResponse({ error: { code: "event_outbox_id_required" } }, 400);
    }
    if (!isUuid(requestedEventId)) {
      return jsonResponse({ error: { code: "event_outbox_id_invalid" } }, 400);
    }
    try {
      await dependencies.persistence.recoverExpired({ maxAttempts });
    } catch {
      return jsonResponse({ error: { code: "recovery_failed" } }, 500);
    }
    let event: ClaimedUccEvent;
    try {
      event = await dependencies.persistence.claimEvent({
        eventOutboxId: requestedEventId,
        maxAttempts,
        leaseSeconds,
      });
    } catch {
      return jsonResponse({ error: { code: "claim_failed" } }, 500);
    }
    if (
      event.claim_state === "no_event" || event.event_outbox_id == null ||
      event.integration_operation_id == null || event.claim_token == null
    ) {
      return jsonResponse(
        { error: { code: "requested_event_not_found" } },
        404,
      );
    }

    let source;
    try {
      source = await dependencies.persistence.loadSource(
        event.integration_operation_id,
      );
    } catch (error) {
      const code = error instanceof UccSourcePersistenceError
        ? error.message
        : "ucc_source_persistence_unavailable";
      log(dependencies, event, "source_load_deferred_for_recovery", code);
      return jsonResponse({
        error: { code },
        data: { outcome: "pre_request_recovery_pending" },
      }, 503);
    }

    let uccRequest;
    let requestPayload: string;
    try {
      uccRequest = buildNseUccRequest(source);
      requestPayload = JSON.stringify(uccRequest);
    } catch (error) {
      if (!(error instanceof NseUccValidationError)) {
        log(
          dependencies,
          event,
          "source_mapping_deferred_for_recovery",
          "ucc_source_shape_invalid",
        );
        return jsonResponse({
          error: { code: "ucc_source_shape_invalid" },
          data: { outcome: "pre_request_recovery_pending" },
        }, 503);
      }
      const code = validationCode(error);
      try {
        await dependencies.persistence.failPreparation({
          eventOutboxId: event.event_outbox_id,
          claimToken: event.claim_token,
          errorCode: code,
        });
      } catch {
        log(dependencies, event, "preparation_failure_recording_failed", code);
        return jsonResponse({
          error: { code: "preparation_failure_recording_failed" },
        }, 500);
      }
      log(dependencies, event, "validation_failed", code);
      return jsonResponse({
        error: { code },
        data: { outcome: "validation_failed" },
      }, 422);
    }
    const callId = uuid();
    const startedAt = now();
    const requestHeaderMetadata = dependencies.gateway.requestHeaderMetadata(
      requestPayload,
    );
    const startInput = {
      eventOutboxId: event.event_outbox_id,
      claimToken: event.claim_token,
      callId,
      requestPayload,
      requestContentType: "application/json",
      requestHeaderMetadata,
      startedAt: startedAt.toISOString(),
    };
    try {
      await persistIdempotently(() =>
        dependencies.persistence.startSubmission(startInput)
      );
    } catch {
      log(dependencies, event, "request_evidence_failed");
      return jsonResponse({ error: { code: "request_evidence_failed" } }, 500);
    }

    const gatewayResult = await dependencies.gateway.submit(requestPayload);
    const completedAt = now();
    const elapsedMs = Math.max(0, completedAt.getTime() - startedAt.getTime());
    const finish = async (
      input: Omit<
        Parameters<UccPersistence["finishSubmission"]>[0],
        | "eventOutboxId"
        | "claimToken"
        | "callId"
        | "completedAt"
        | "elapsedMs"
        | "maxAttempts"
      >,
    ) => {
      await persistIdempotently(() =>
        dependencies.persistence.finishSubmission({
          eventOutboxId: event.event_outbox_id!,
          claimToken: event.claim_token!,
          callId,
          completedAt: completedAt.toISOString(),
          elapsedMs,
          maxAttempts,
          ...input,
        })
      );
    };
    try {
      if (gatewayResult.kind === "failure") {
        const ambiguous = gatewayResult.delivery === "MAYBE_SENT";
        await finish({
          responsePayload: "",
          responseContentType: null,
          responseHeaderMetadata: {},
          httpStatus: null,
          nativeStatusValue: null,
          nativeRemarkCategory: null,
          normalizedOutcome: ambiguous
            ? "AMBIGUOUS"
            : "PRE_TRANSMISSION_FAILURE",
          errorCategory: gatewayResult.errorCategory,
          timeoutOccurred: gatewayResult.timeout,
          networkFailure: gatewayResult.networkFailure,
          externalAccountId: null,
          registrationReference: null,
        });
        const outcome = ambiguous
          ? "reconciliation_required"
          : event.attempt < maxAttempts
          ? "safe_retry_available"
          : "submission_failed";
        log(dependencies, event, outcome, gatewayResult.errorCategory);
        return jsonResponse({
          error: { code: gatewayResult.errorCategory },
          data: { outcome },
        }, ambiguous ? 202 : 503);
      }
      if (gatewayResult.status < 200 || gatewayResult.status > 299) {
        const definitive = gatewayResult.status === 400 ||
          gatewayResult.status === 403;
        await finish({
          responsePayload: gatewayResult.rawBody,
          responseContentType: gatewayResult.contentType,
          responseHeaderMetadata: gatewayResult.safeHeaderMetadata,
          httpStatus: gatewayResult.status,
          nativeStatusValue: null,
          nativeRemarkCategory: null,
          normalizedOutcome: definitive ? "HTTP_FAILURE" : "AMBIGUOUS",
          errorCategory: definitive
            ? "nse_http_definitive_failure"
            : "nse_http_ambiguous_failure",
          timeoutOccurred: false,
          networkFailure: false,
          externalAccountId: null,
          registrationReference: null,
        });
        const outcome = definitive ? "http_failed" : "reconciliation_required";
        log(
          dependencies,
          event,
          outcome,
          definitive
            ? "nse_http_definitive_failure"
            : "nse_http_ambiguous_failure",
        );
        return jsonResponse({
          error: {
            code: definitive
              ? "nse_http_definitive_failure"
              : "nse_http_ambiguous_failure",
          },
          data: { outcome },
        }, definitive ? 502 : 202);
      }
      let parsed;
      try {
        parsed = parseNseUccResponse(
          gatewayResult.rawBody,
          gatewayResult.status,
        );
      } catch {
        await finish({
          responsePayload: gatewayResult.rawBody,
          responseContentType: gatewayResult.contentType,
          responseHeaderMetadata: gatewayResult.safeHeaderMetadata,
          httpStatus: gatewayResult.status,
          nativeStatusValue: null,
          nativeRemarkCategory: "unparseable_response",
          normalizedOutcome: "AMBIGUOUS",
          errorCategory: "nse_response_contract_invalid",
          timeoutOccurred: false,
          networkFailure: false,
          externalAccountId: null,
          registrationReference: null,
        });
        return jsonResponse({
          error: { code: "nse_response_contract_invalid" },
          data: { outcome: "reconciliation_required" },
        }, 202);
      }
      const submittedClientCode = uccRequest.reg_details[0].client_code;
      const mismatch = parsed.businessSuccess &&
        parsed.clientCode !== submittedClientCode;
      const success = parsed.businessSuccess && parsed.clientCode != null &&
        !mismatch;
      const normalizedOutcome = mismatch
        ? "AMBIGUOUS"
        : success
        ? "SUCCESS"
        : "BUSINESS_FAILURE";
      await finish({
        responsePayload: gatewayResult.rawBody,
        responseContentType: gatewayResult.contentType,
        responseHeaderMetadata: gatewayResult.safeHeaderMetadata,
        httpStatus: gatewayResult.status,
        nativeStatusValue: parsed.nativeStatusValue,
        nativeRemarkCategory: parsed.nativeRemarkCategory,
        normalizedOutcome,
        errorCategory: mismatch
          ? "nse_client_code_mismatch"
          : success
          ? null
          : "nse_ucc_business_failure",
        timeoutOccurred: false,
        networkFailure: false,
        externalAccountId: parsed.clientCode,
        registrationReference: parsed.registrationReference,
      });
      const outcome = mismatch
        ? "reconciliation_required"
        : success
        ? "success"
        : "business_failed";
      log(
        dependencies,
        event,
        outcome,
        mismatch
          ? "nse_client_code_mismatch"
          : success
          ? null
          : "nse_ucc_business_failure",
      );
      return jsonResponse(
        { data: { outcome } },
        mismatch ? 202 : success ? 200 : 422,
      );
    } catch {
      log(dependencies, event, "result_evidence_failed");
      return jsonResponse({
        error: { code: "result_evidence_failed" },
        data: { outcome: "reconciliation_required" },
      }, 500);
    }
  };
}
