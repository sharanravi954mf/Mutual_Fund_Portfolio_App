import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import { NseClient, NseClientError } from "../_shared/nse/nse_client.ts";
import type { NseUccSource } from "../_shared/nse/nse_ucc.ts";
import { NSE_UCC_ENDPOINT } from "../_shared/nse/nse_ucc.ts";
import { UccSourcePersistenceError } from "./types.ts";
import type { ClaimedUccEvent, UccGateway, UccPersistence } from "./types.ts";

function rpcFailure(error: { message?: string } | null): never {
  throw new Error(error?.message ?? "integration_persistence_failed");
}

export function createUccPersistence(client: SupabaseClient): UccPersistence {
  return {
    async recoverExpired(input) {
      const { error } = await client.rpc("recover_expired_nse_ucc_events", {
        p_max_attempts: input.maxAttempts,
      });
      if (error != null) rpcFailure(error);
    },
    async claimEvent(input) {
      const { data, error } = await client.rpc(
        "claim_nse_ucc_registration_event",
        {
          p_event_outbox_id: input.eventOutboxId,
          p_max_attempts: input.maxAttempts,
          p_lease_seconds: input.leaseSeconds,
        },
      );
      if (error != null) rpcFailure(error);
      const rows = data as ClaimedUccEvent[] | null;
      return rows?.[0] ??
        {
          event_outbox_id: null,
          integration_operation_id: null,
          payload: null,
          correlation_id: null,
          attempt: 0,
          claim_state: "no_event",
          claim_token: null,
          claim_expires_at: null,
        };
    },
    async loadSource(integrationOperationId) {
      const { data, error } = await client.rpc(
        "get_nse_ucc_registration_source",
        {
          p_integration_operation_id: integrationOperationId,
        },
      );
      if (error != null || data == null || typeof data !== "object") {
        throw new UccSourcePersistenceError();
      }
      return data as NseUccSource;
    },
    async startSubmission(input) {
      const { data, error } = await client.rpc("start_nse_ucc_submission", {
        p_event_outbox_id: input.eventOutboxId,
        p_claim_token: input.claimToken,
        p_call_id: input.callId,
        p_request_payload: input.requestPayload,
        p_request_content_type: input.requestContentType,
        p_request_header_metadata: input.requestHeaderMetadata,
        p_started_at: input.startedAt,
      });
      if (error != null) rpcFailure(error);
      return data ?? {};
    },
    async finishSubmission(input) {
      const { data, error } = await client.rpc("finish_nse_ucc_submission", {
        p_event_outbox_id: input.eventOutboxId,
        p_claim_token: input.claimToken,
        p_call_id: input.callId,
        p_response_payload: input.responsePayload,
        p_response_content_type: input.responseContentType,
        p_response_header_metadata: input.responseHeaderMetadata,
        p_http_status: input.httpStatus,
        p_completed_at: input.completedAt,
        p_elapsed_ms: input.elapsedMs,
        p_native_status_value: input.nativeStatusValue,
        p_native_remark_category: input.nativeRemarkCategory,
        p_normalized_outcome: input.normalizedOutcome,
        p_error_category: input.errorCategory,
        p_timeout_occurred: input.timeoutOccurred,
        p_network_failure: input.networkFailure,
        p_external_account_id: input.externalAccountId,
        p_registration_reference: input.registrationReference,
        p_max_attempts: input.maxAttempts,
      });
      if (error != null) rpcFailure(error);
      return data ?? {};
    },
    async failPreparation(input) {
      const { error } = await client.rpc("record_nse_ucc_validation_failure", {
        p_event_outbox_id: input.eventOutboxId,
        p_claim_token: input.claimToken,
        p_error_code: input.errorCode,
      });
      if (error != null) rpcFailure(error);
    },
  };
}

export function createNseUccGateway(client: NseClient): UccGateway {
  const requestOptions = (serializedRequest: string) => ({
    method: "POST",
    path: NSE_UCC_ENDPOINT,
    bodyText: serializedRequest,
    contentType: "application/json",
    accept: "application/json",
    timeoutMs: 30_000,
    maxResponseBytes: 1024 * 1024,
    acceptHttpErrors: true,
  } as const);
  return {
    requestHeaderMetadata(serializedRequest) {
      return client.safeRequestHeaderMetadata(
        requestOptions(serializedRequest),
      );
    },
    async submit(serializedRequest) {
      try {
        const response = await client.request(
          requestOptions(serializedRequest),
        );
        return {
          kind: "response",
          status: response.status,
          contentType: response.headers.get("content-type"),
          safeHeaderMetadata: response.safeHeaderMetadata,
          rawBody: new TextDecoder().decode(response.body),
        };
      } catch (error) {
        if (error instanceof NseClientError) {
          const notSent = error.code === "nse_request_invalid";
          return {
            kind: "failure",
            delivery: notSent ? "NOT_SENT" : "MAYBE_SENT",
            errorCategory: error.code,
            timeout: error.code === "nse_request_timeout",
            networkFailure: error.code === "nse_network_error",
          };
        }
        return {
          kind: "failure",
          delivery: "MAYBE_SENT",
          errorCategory: "nse_transport_unexpected_error",
          timeout: false,
          networkFailure: true,
        };
      }
    },
  };
}
