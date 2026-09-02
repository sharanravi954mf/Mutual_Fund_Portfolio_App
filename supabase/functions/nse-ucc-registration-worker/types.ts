import type { NseUccSource } from "../_shared/nse/nse_ucc.ts";
import type {
  SafeIntegrationHeaderMetadata,
} from "../_shared/nse/nse_types.ts";

export class UccSourcePersistenceError extends Error {
  constructor() {
    super("ucc_source_persistence_unavailable");
    this.name = "UccSourcePersistenceError";
  }
}

export type ClaimedUccEvent = {
  event_outbox_id: string | null;
  integration_operation_id: string | null;
  payload: Record<string, unknown> | null;
  correlation_id: string | null;
  attempt: number;
  claim_state:
    | "newly_claimed"
    | "safe_retry_claimed"
    | "pre_request_recovery_claimed"
    | "no_event";
  claim_token: string | null;
  claim_expires_at: string | null;
};

export type GatewayResponse = {
  kind: "response";
  status: number;
  contentType: string | null;
  safeHeaderMetadata: SafeIntegrationHeaderMetadata;
  rawBody: string;
};
export type GatewayFailure = {
  kind: "failure";
  delivery: "NOT_SENT" | "MAYBE_SENT";
  errorCategory: string;
  timeout: boolean;
  networkFailure: boolean;
};
export type UccGateway = {
  requestHeaderMetadata(
    serializedRequest: string,
  ): SafeIntegrationHeaderMetadata;
  submit(serializedRequest: string): Promise<GatewayResponse | GatewayFailure>;
};

export type SubmissionEvidenceResult = {
  state?: string;
  retry_allowed?: boolean;
};

export type UccPersistence = {
  recoverExpired(input: { maxAttempts: number }): Promise<void>;
  claimEvent(input: {
    eventOutboxId: string;
    maxAttempts: number;
    leaseSeconds: number;
  }): Promise<ClaimedUccEvent>;
  loadSource(integrationOperationId: string): Promise<NseUccSource>;
  startSubmission(input: {
    eventOutboxId: string;
    claimToken: string;
    callId: string;
    requestPayload: string;
    requestContentType: string;
    requestHeaderMetadata: SafeIntegrationHeaderMetadata;
    startedAt: string;
  }): Promise<SubmissionEvidenceResult>;
  finishSubmission(input: {
    eventOutboxId: string;
    claimToken: string;
    callId: string;
    responsePayload: string;
    responseContentType: string | null;
    responseHeaderMetadata: SafeIntegrationHeaderMetadata;
    httpStatus: number | null;
    completedAt: string;
    elapsedMs: number;
    nativeStatusValue: string | null;
    nativeRemarkCategory: string | null;
    normalizedOutcome:
      | "SUCCESS"
      | "BUSINESS_FAILURE"
      | "HTTP_FAILURE"
      | "PRE_TRANSMISSION_FAILURE"
      | "AMBIGUOUS";
    errorCategory: string | null;
    timeoutOccurred: boolean;
    networkFailure: boolean;
    externalAccountId: string | null;
    registrationReference: string | null;
    maxAttempts: number;
  }): Promise<SubmissionEvidenceResult>;
  failPreparation(input: {
    eventOutboxId: string;
    claimToken: string;
    errorCode: string;
  }): Promise<void>;
};
