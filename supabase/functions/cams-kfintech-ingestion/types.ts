export type Registrar = "CAMS" | "KFINTECH";
export type StatementFileType = "CAS_PDF" | "DBF";

export type FailureCode =
  | "authorization_required"
  | "not_authorized"
  | "mailbox_connection_not_found"
  | "oauth_credentials_unavailable"
  | "mailbox_poll_failed"
  | "attachment_limit_exceeded"
  | "sender_not_allowed"
  | "attachment_too_large"
  | "attachment_hash_mismatch"
  | "duplicate_attachment"
  | "correlation_conflict"
  | "previous_ingestion_failed"
  | "processing_incomplete"
  | "investor_mapping_unresolved"
  | "investor_mapping_ambiguous"
  | "investor_workspace_relationship_required"
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
};

export type DownloadedAttachment = EmailAttachment & {
  stream: ReadableStream<Uint8Array>;
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
