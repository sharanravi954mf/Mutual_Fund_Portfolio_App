import { NseClient, NseClientError } from "../_shared/nse/nse_client.ts";
import type { NseConfig } from "../_shared/nse/nse_types.ts";
import { NSE_ORDER_STATUS_ENDPOINT } from "../_shared/nse/nse_order_status.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import type {
  ClaimedOrderStatusEvent,
  OrderStatusGateway,
  OrderStatusPersistence,
} from "./types.ts";

function required<T>(data: T | null, error: unknown): T {
  if (error || data == null) {
    throw new Error("order_status_persistence_unavailable");
  }
  return data;
}

function noOrderStatusEvent(): ClaimedOrderStatusEvent {
  return {
    event_outbox_id: null,
    integration_operation_id: null,
    correlation_id: null,
    attempt: 0,
    claim_state: "no_event",
    claim_token: null,
  };
}

function unwrapClaimedOrderStatusEvent(
  data: unknown,
): ClaimedOrderStatusEvent {
  if (data == null || (Array.isArray(data) && data.length === 0)) {
    return noOrderStatusEvent();
  }
  if (!Array.isArray(data)) {
    throw new Error("order_status_claim_response_invalid");
  }
  const row = data[0];
  if (row == null || typeof row !== "object" || Array.isArray(row)) {
    throw new Error("order_status_claim_response_invalid");
  }
  const claim = row as Partial<ClaimedOrderStatusEvent>;
  if (claim.claim_state === "no_event") return noOrderStatusEvent();
  if (
    (claim.claim_state !== "newly_claimed" &&
      claim.claim_state !== "safe_retry_claimed") ||
    typeof claim.event_outbox_id !== "string" ||
    typeof claim.integration_operation_id !== "string" ||
    typeof claim.correlation_id !== "string" ||
    typeof claim.claim_token !== "string" ||
    typeof claim.attempt !== "number"
  ) {
    throw new Error("order_status_claim_response_invalid");
  }
  return {
    event_outbox_id: claim.event_outbox_id,
    integration_operation_id: claim.integration_operation_id,
    correlation_id: claim.correlation_id,
    attempt: claim.attempt,
    claim_state: claim.claim_state,
    claim_token: claim.claim_token,
  };
}

export function createOrderStatusPersistence(
  client: SupabaseClient,
): OrderStatusPersistence {
  return {
    async recoverExpired(input) {
      const { data, error } = await client.rpc(
        "recover_expired_nse_order_status_events",
        {
          p_event_outbox_id: input.eventOutboxId,
          p_max_attempts: input.maxAttempts,
        },
      );
      return required(data, error);
    },
    async claimEvent(input) {
      const { data, error } = await client.rpc(
        "claim_nse_order_status_event",
        {
          p_event_outbox_id: input.eventOutboxId,
          p_max_attempts: input.maxAttempts,
          p_lease_seconds: input.leaseSeconds,
        },
      );
      if (error != null) {
        throw new Error("order_status_persistence_unavailable");
      }
      return unwrapClaimedOrderStatusEvent(data);
    },
    async loadSource(operationId) {
      const { data, error } = await client.rpc(
        "get_nse_order_status_source",
        { p_integration_operation_id: operationId },
      );
      return required(data, error);
    },
    async start(input) {
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
    async finish(input) {
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
  // Keep this read on its exact endpoint even if the vendor returns a redirect.
  const client = new NseClient(
    config,
    (input, init) => fetcher(input, { ...init, redirect: "error" }),
  );
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
