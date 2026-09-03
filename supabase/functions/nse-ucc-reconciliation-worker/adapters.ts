import { NseClient, NseClientError } from "../_shared/nse/nse_client.ts";
import type { NseConfig } from "../_shared/nse/nse_types.ts";
import { NSE_CLIENT_MASTER_ENDPOINT } from "../_shared/nse/nse_ucc_verification.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { VerificationGateway, VerificationPersistence } from "./types.ts";

function required<T>(data: T | null, error: unknown): T {
  if (error || data == null) {
    throw new Error("verification_persistence_unavailable");
  }
  return data;
}
export function createVerificationPersistence(
  client: SupabaseClient,
): VerificationPersistence {
  return {
    async recoverExpired(input) {
      const { data, error } = await client.rpc(
        "recover_expired_nse_ucc_verification_events",
        {
          p_event_outbox_id: input.eventOutboxId,
          p_max_attempts: input.maxAttempts,
        },
      );
      return required(data, error);
    },
    async claimEvent(input) {
      const { data, error } = await client.rpc(
        "claim_nse_ucc_verification_event",
        {
          p_event_outbox_id: input.eventOutboxId,
          p_max_attempts: input.maxAttempts,
          p_lease_seconds: input.leaseSeconds,
        },
      );
      return required(data, error);
    },
    async loadSource(operationId) {
      const { data, error } = await client.rpc(
        "get_nse_ucc_verification_source",
        { p_integration_operation_id: operationId },
      );
      return required(data, error);
    },
    async start(input) {
      const { data, error } = await client.rpc("start_nse_ucc_verification", {
        p_event_outbox_id: input.eventOutboxId,
        p_claim_token: input.claimToken,
        p_call_id: input.callId,
        p_request_payload: input.requestPayload,
        p_request_header_metadata: input.requestHeaderMetadata,
        p_started_at: input.startedAt,
      });
      return required(data, error);
    },
    async finish(input) {
      const { data, error } = await client.rpc("finish_nse_ucc_verification", {
        p_event_outbox_id: input.eventOutboxId,
        p_claim_token: input.claimToken,
        p_call_id: input.callId,
        p_response_payload: input.responsePayload,
        p_response_content_type: input.responseContentType,
        p_response_header_metadata: input.responseHeaderMetadata,
        p_http_status: input.httpStatus,
        p_native_status_value: input.nativeStatusValue,
        p_native_remark_category: input.nativeRemarkCategory,
        p_normalized_outcome: input.normalizedOutcome,
        p_error_category: input.errorCategory,
        p_timeout_occurred: input.timeoutOccurred,
        p_network_failure: input.networkFailure,
        p_completed_at: input.completedAt,
        p_elapsed_ms: input.elapsedMs,
        p_max_attempts: input.maxAttempts,
      });
      return required(data, error);
    },
    async distribute(targetOperationId, verificationOperationId) {
      const { data, error } = await client.rpc(
        "distribute_nse_ucc_verification_result",
        {
          p_target_operation_id: targetOperationId,
          p_verification_operation_id: verificationOperationId,
        },
      );
      return required(data, error);
    },
  };
}
export function createVerificationGateway(
  config: NseConfig,
  fetcher: typeof fetch = fetch,
): VerificationGateway {
  const client = new NseClient(config, fetcher);
  const options = (bodyText: string) => ({
    method: "POST" as const,
    path: NSE_CLIENT_MASTER_ENDPOINT,
    bodyText,
    contentType: "application/json",
    accept: "application/json",
    timeoutMs: 30_000,
    maxResponseBytes: 1024 * 1024,
    acceptHttpErrors: true,
  });
  return {
    requestHeaderMetadata(body) {
      return client.safeRequestHeaderMetadata(options(body));
    },
    async submit(body) {
      try {
        const response = await client.request(options(body));
        return {
          kind: "response" as const,
          status: response.status,
          contentType: response.headers.get("content-type"),
          safeHeaderMetadata: response.safeHeaderMetadata,
          rawBody: new TextDecoder().decode(response.body),
        };
      } catch (error) {
        const code = error instanceof NseClientError
          ? error.code
          : "nse_network_error";
        return {
          kind: "failure" as const,
          errorCategory: code,
          timeout: code === "nse_request_timeout",
          networkFailure: code === "nse_network_error",
        };
      }
    },
  };
}
