import type { SafeIntegrationHeaderMetadata } from "../_shared/nse/nse_types.ts";
import type {
  OrderFundingApi,
  OrderFundingSource,
} from "../_shared/nse/nse_order_funding.ts";

export type ClaimedOrderFundingEvent = {
  event_outbox_id: string | null;
  integration_operation_id: string | null;
  correlation_id: string | null;
  attempt: number;
  claim_state: "newly_claimed" | "safe_retry_claimed" | "no_event";
  claim_token: string | null;
};
export type OrderFundingGatewayResult =
  | {
    kind: "response";
    status: number;
    contentType: string | null;
    safeHeaderMetadata: SafeIntegrationHeaderMetadata;
    rawBody: string;
    rawBodyBase64: string;
  }
  | {
    kind: "failure";
    errorCategory: string;
    timeout: boolean;
    networkFailure: boolean;
  };
export interface OrderFundingGateway {
  requestHeaderMetadata(
    serializedRequest: string,
    api: OrderFundingApi,
  ): SafeIntegrationHeaderMetadata;
  submit(
    serializedRequest: string,
    api: OrderFundingApi,
  ): Promise<OrderFundingGatewayResult>;
}
export interface OrderFundingPersistence {
  recoverExpired(
    input: { eventOutboxId: string; maxAttempts: number },
  ): Promise<unknown>;
  claimEvent(
    input: { eventOutboxId: string; maxAttempts: number; leaseSeconds: number },
  ): Promise<ClaimedOrderFundingEvent>;
  loadSource(operationId: string): Promise<OrderFundingSource>;
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
      responseBodyBase64?: string;
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
    },
  ): Promise<unknown>;
}
