import { NseClient, NseClientError } from "../_shared/nse/nse_client.ts";
import type {
  NseConfig,
  SafeIntegrationHeaderMetadata,
} from "../_shared/nse/nse_types.ts";
import { NSE_ORDER_STATUS_ENDPOINT } from "../_shared/nse/nse_order_status.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type ClaimedOrderStatusEvent = {
  event_outbox_id: string | null;
  integration_operation_id: string | null;
  correlation_id: string | null;
  attempt: number;
  claim_state: "newly_claimed" | "safe_retry_claimed" | "no_event";
  claim_token: string | null;
};
export type GatewayResult = {
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
export type OrderStatusPersistence = {
  recoverExpired(
    input: { eventOutboxId: string; maxAttempts: number },
  ): Promise<unknown>;
  claimEvent(
    input: { eventOutboxId: string; maxAttempts: number; leaseSeconds: number },
  ): Promise<ClaimedOrderStatusEvent>;
  loadSource(operationId: string): Promise<unknown>;
  start(
    input: {
      eventOutboxId: string;
      claimToken: string;
      callId: string;
      requestPayload: string;
      requestHeaderMetadata: SafeIntegrationHeaderMetadata;
      startedAt: string;
    },
  ): Promise<unknown>;
  finish(
    input: {
      eventOutboxId: string;
      claimToken: string;
      callId: string;
      responsePayload: string;
      responseContentType: string | null;
      responseHeaderMetadata: SafeIntegrationHeaderMetadata;
      httpStatus: number | null;
      nativeStatusValue: string | null;
      nativeRemarkCategory: string;
      normalizedOutcome:
        | "SUCCESS"
        | "BUSINESS_FAILURE"
        | "HTTP_FAILURE"
        | "TRANSPORT_FAILURE";
      errorCategory: string | null;
      timeoutOccurred: boolean;
      networkFailure: boolean;
      completedAt: string;
      elapsedMs: number;
      maxAttempts: number;
      recordCount: number;
      invalidCount: number;
    },
  ): Promise<unknown>;
};
export type OrderStatusGateway = {
  requestHeaderMetadata(body: string): SafeIntegrationHeaderMetadata;
  submit(body: string): Promise<GatewayResult>;
};
const noEvent = (): ClaimedOrderStatusEvent => ({
  event_outbox_id: null,
  integration_operation_id: null,
  correlation_id: null,
  attempt: 0,
  claim_state: "no_event",
  claim_token: null,
});
function unwrapClaim(data: unknown): ClaimedOrderStatusEvent {
  if (data == null || Array.isArray(data) && data.length === 0) {
    return noEvent();
  }
  if (
    !Array.isArray(data) || data.length !== 1 || data[0] == null ||
    typeof data[0] !== "object" || Array.isArray(data[0])
  ) throw new Error("order_status_claim_response_invalid");
  const row = data[0] as Partial<ClaimedOrderStatusEvent>;
  if (row.claim_state === "no_event") return noEvent();
  if (
    (row.claim_state !== "newly_claimed" &&
      row.claim_state !== "safe_retry_claimed") ||
    typeof row.event_outbox_id !== "string" ||
    typeof row.integration_operation_id !== "string" ||
    typeof row.correlation_id !== "string" ||
    typeof row.claim_token !== "string" || typeof row.attempt !== "number"
  ) throw new Error("order_status_claim_response_invalid");
  return row as ClaimedOrderStatusEvent;
}
function required<T>(data: T | null, error: unknown): T {
  if (error || data == null) {
    throw new Error("order_status_persistence_unavailable");
  }
  return data;
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
      const { data, error } = await client.rpc("claim_nse_order_status_event", {
        p_event_outbox_id: input.eventOutboxId,
        p_max_attempts: input.maxAttempts,
        p_lease_seconds: input.leaseSeconds,
      });
      if (error) throw new Error("order_status_persistence_unavailable");
      return unwrapClaim(data);
    },
    async loadSource(operationId) {
      const { data, error } = await client.rpc("get_nse_order_status_source", {
        p_integration_operation_id: operationId,
      });
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
        p_record_count: input.recordCount,
        p_invalid_count: input.invalidCount,
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
          kind: "response",
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
          kind: "failure",
          errorCategory: code,
          timeout: code === "nse_request_timeout",
          networkFailure: code === "nse_network_error",
        };
      }
    },
  };
}
