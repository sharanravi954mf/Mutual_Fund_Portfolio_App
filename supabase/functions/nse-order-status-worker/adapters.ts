import { NseClient, NseClientError } from "../_shared/nse/nse_client.ts";
import { NSE_ORDER_STATUS_ENDPOINT } from "../_shared/nse/nse_order_status.ts";
import type { NseConfig } from "../_shared/nse/nse_types.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type {
  ClaimedOrderStatusEvent,
  OrderStatusGateway,
  OrderStatusPersistence,
} from "./handler.ts";
const required = <T>(data: T | null, error: unknown): T => {
  if (error || data == null) {
    throw new Error("order_status_persistence_unavailable");
  }
  return data;
};
export function createOrderStatusPersistence(
  client: SupabaseClient,
): OrderStatusPersistence {
  return {
    recoverExpired: async (input) => {
      const { data, error } = await client.rpc(
        "recover_expired_nse_order_status_events",
        {
          p_event_outbox_id: input.eventOutboxId,
          p_max_attempts: input.maxAttempts,
        },
      );
      return required(data, error);
    },
    claimEvent: async (input) => {
      const { data, error } = await client.rpc("claim_nse_order_status_event", {
        p_event_outbox_id: input.eventOutboxId,
        p_max_attempts: input.maxAttempts,
        p_lease_seconds: input.leaseSeconds,
      });
      const row = Array.isArray(data) ? data[0] : null;
      if (error || row == null || typeof row !== "object") {
        return {
          event_outbox_id: null,
          integration_operation_id: null,
          attempt: 0,
          claim_state: "no_event",
          claim_token: null,
        };
      }
      return row as ClaimedOrderStatusEvent;
    },
    loadSource: async (id) => {
      const { data, error } = await client.rpc("get_nse_order_status_source", {
        p_integration_operation_id: id,
      });
      return required(data, error);
    },
    start: async (input) => {
      const { data, error } = await client.rpc("start_nse_order_status", {
        p_event_outbox_id: input.eventOutboxId,
        p_claim_token: input.claimToken,
        p_call_id: input.callId,
        p_request_payload: input.requestPayload,
        p_request_header_metadata: input.requestHeaderMetadata,
        p_started_at: input.startedAt,
      });
      return required(data, error);
    },
    finish: async (input) => {
      const { data, error } = await client.rpc("finish_nse_order_status", {
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
  };
}
export function createOrderStatusGateway(
  config: NseConfig,
  fetcher: typeof fetch = fetch,
): OrderStatusGateway {
  const client = new NseClient(config, fetcher);
  const options = (bodyText: string) => ({
    method: "POST" as const,
    path: NSE_ORDER_STATUS_ENDPOINT,
    bodyText,
    contentType: "application/json",
    accept: "application/json",
    timeoutMs: 30_000,
    maxResponseBytes: 1024 * 1024,
    acceptHttpErrors: true,
  });
  return {
    requestHeaderMetadata: (body) =>
      client.safeRequestHeaderMetadata(options(body)),
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
