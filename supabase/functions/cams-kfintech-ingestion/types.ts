export type Registrar = "CAMS" | "KFINTECH";
export type StatementFileType = "CAS_PDF" | "DBF";

export type FailureCode =
  | "authorization_required"
  | "not_authorized"
  | "mailbox_connection_not_found"
  | "oauth_credentials_unavailable"
  | "oauth_request_invalid"
  | "oauth_state_invalid"
  | "oauth_state_expired"
  | "oauth_state_replayed"
  | "oauth_redirect_uri_mismatch"
  | "oauth_code_required"
  | "oauth_provider_error"
  | "oauth_refresh_token_required"
  | "oauth_exchange_failed"
  | "oauth_revocation_failed"
  | "mailbox_poll_failed"
  | "attachment_limit_exceeded"
  | "sender_not_allowed"
  | "attachment_too_large"
  | "attachment_hash_mismatch"
  | "duplicate_attachment"
  | "correlation_conflict"
  | "ingestion_run_in_progress"
  | "ingestion_run_not_claimed"
  | "ingestion_run_finalized"
  | "attempt_lineage_incomplete"
  | "previous_ingestion_failed"
  | "processing_incomplete"
  | "investor_mapping_unresolved"
  | "investor_mapping_ambiguous"
  | "investor_workspace_relationship_required"
  | "amc_mapping_unresolved"
  | "amc_mapping_conflict"
  | "portfolio_mapping_ambiguous"
  | "folio_relationship_conflict"
  | "configuration_ambiguous"
  | "connector_untrusted_origin"
  | "credential_refresh_failed"
  | "unsupported_media_type"
  | "magic_byte_mismatch"
  | "malware_detected"
  | "malware_scan_unavailable"
  | "encrypted_storage_write_failed"
  | "encrypted_storage_read_failed"
  | "storage_object_conflict"
  | "stored_object_hash_mismatch"
  | "stored_object_size_mismatch"
  | "unsupported_registrar"
  | "unsupported_statement_format"
  | "unsupported_report"
  | "statement_decryption_failed"
  | "parse_failed"
  | "persistence_conflict"
  | "persistence_failed";

export class IngestionError extends Error {
  readonly code: FailureCode;

  constructor(code: FailureCode) {
    super(code);
    this.name = "IngestionError";
    this.code = code;
  }
}

export type MailboxConnection = {
  id: string;
  workspaceId: string;
  registrar: Registrar;
  connectorRef: string;
  mailboxAddress: string;
  allowedSenderAddresses: string[];
  maxAttachmentBytes: number;
};

export type CredentialBundle = {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: string;
};

export type EncryptedCredentialEnvelope = {
  credentialCiphertext: string;
  credentialNonce: string;
  keyVersion: number;
};

export type RegistrarConfig = {
  registrar: Registrar;
  allowedSenderAddresses: string[];
  maxAttachmentBytes: number;
  maxMessagesPerPoll: number;
  maxAttachmentsPerMessage: number;
  maxAttachmentsPerRun: number;
  totalBytesPerRun: number;
  supportedFileTypes: StatementFileType[];
};

export type IngestionRunContext = {
  workspaceId: string;
  mailboxConnectionId: string;
  correlationId: string;
  mailbox: MailboxConnection;
  credentials: CredentialBundle;
  registrarConfig: RegistrarConfig;
};

export type EmailAttachment = {
  attachmentId: string;
  filename: string;
  declaredMime: string;
  receivedAt: string;
  expectedSha256Hex?: string;
};

export type MailMessage = {
  senderAddress: string;
  messageId: string;
  receivedAt: string;
  attachments: EmailAttachment[];
  outcome?: "no_data" | "unsupported_report";
};

export type DownloadedAttachment = EmailAttachment & {
  stream: ReadableStream<Uint8Array>;
  deadlineSignal?: AbortSignal;
  cancelDeadline?: () => void;
};

export type DetectedFormat = {
  detectedMime: string;
  fileType: StatementFileType;
};

export type StoredObject = {
  bucket: string;
  path: string;
};

export type NormalizedTransaction = {
  registrar: Registrar;
  clientPan: string;
  investorName: string;
  folioNumber: string;
  schemeCode: string;
  schemeName: string;
  fundHouse: string;
  category: string;
  transactionType: "BUY" | "SELL" | "SWITCH";
  transactionDirection: "INFLOW" | "OUTFLOW";
  registrarTransactionCode: string;
  units: number;
  nav: number;
  amount: number;
  date: string;
  sourceRowNumber: number;
  registrarTransactionId?: string;
};

export type PersistenceInput = {
  workspaceId: string;
  mailboxConnectionId: string;
  ingestionRunId: string;
  documentCorrelationId: string;
  providerMessageId: string;
  providerAttachmentId: string;
  attachmentAttemptKey: string;
  registrar: Registrar;
  sha256Hex: string;
  storage: StoredObject;
  detectedMime: string;
  fileType: StatementFileType;
  sizeBytes: number;
  receivedAt: string;
  transactions: NormalizedTransaction[];
};

export type PersistenceResult = {
  document_id: string;
  ingestion_log_id: string | null;
  outbox_event_id: string | null;
  transaction_count: number;
  idempotent: boolean;
  failure_code?: FailureCode | null;
};

export type IngestionRunClaimInput = {
  workspaceId: string;
  mailboxConnectionId: string;
  ingestionRunId: string;
  registrar: Registrar;
};

export type IngestionRunFinalStatus =
  | "claimed"
  | "completed"
  | "partially_failed"
  | "failed"
  | "stopped";

export type IngestionRunReplayState =
  | "newly_claimed"
  | "active_in_progress"
  | "terminal_replay";

export type IngestionRunSummary = {
  ingestion_run_id: string;
  status: IngestionRunFinalStatus;
  replay_state?: IngestionRunReplayState;
  attempted_attachment_count: number;
  successful_attachment_count: number;
  failed_attachment_count: number;
  duplicate_attachment_count: number;
  stopped_attachment_count: number;
  observed_attachment_count: number;
  durable_attempt_count: number;
  lineage_gap_count: number;
  stopped_reason: FailureCode | null;
  run_failure_code: FailureCode | null;
};

export type IngestionRunClaimResult = IngestionRunSummary & {
  replay_state: IngestionRunReplayState;
};

export type IngestionRunFinalizeInput = IngestionRunClaimInput & {
  stoppedReason?: FailureCode;
  failureCode?: FailureCode;
  observedAttachmentCount?: number;
};

export type FailureLineageInput = {
  workspaceId: string;
  mailboxConnectionId: string;
  ingestionRunId: string;
  documentCorrelationId: string;
  providerMessageId?: string;
  providerAttachmentId?: string;
  attachmentAttemptKey?: string;
  registrar: Registrar;
  failureCode: FailureCode;
  sha256Hex?: string;
  storage?: StoredObject;
  detectedMime?: string;
  fileType?: StatementFileType;
  sizeBytes?: number;
};
