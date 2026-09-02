import type { SafeIntegrationHeaderMetadata } from "../_shared/nse/nse_types.ts";
import type { NseUccVerificationSource } from "../_shared/nse/nse_ucc_verification.ts";

export type ClaimedVerificationEvent = {
  event_outbox_id: string | null;
  integration_operation_id: string | null;
  correlation_id: string | null;
  attempt: number;
  claim_state: "newly_claimed" | "safe_retry_claimed" | "no_event";
  claim_token: string | null;
};
export type VerificationGatewayResult =
  | {
    kind: "response";
    status: number;
    contentType: string | null;
    safeHeaderMetadata: SafeIntegrationHeaderMetadata;
    rawBody: string;
  }
  | {
    kind: "failure";
    errorCategory: string;
    timeout: boolean;
    networkFailure: boolean;
  };
export interface VerificationGateway {
  requestHeaderMetadata(
    serializedRequest: string,
  ): SafeIntegrationHeaderMetadata;
  submit(serializedRequest: string): Promise<VerificationGatewayResult>;
}
export interface VerificationPersistence {
  recoverExpired(
    input: { eventOutboxId: string; maxAttempts: number },
  ): Promise<unknown>;
  claimEvent(
    input: { eventOutboxId: string; maxAttempts: number; leaseSeconds: number },
  ): Promise<ClaimedVerificationEvent>;
  loadSource(operationId: string): Promise<NseUccVerificationSource>;
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
    },
  ): Promise<unknown>;
  distribute(
    targetOperationId: string,
    verificationOperationId: string,
  ): Promise<unknown>;
}
