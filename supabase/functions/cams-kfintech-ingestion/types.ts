export type Registrar = "CAMS" | "KFINTECH";
export type StatementFileType = "CAS_PDF" | "DBF";

export type FailureCode =
  | "authorization_required"
  | "not_authorized"
  | "mailbox_connection_not_found"
  | "oauth_credentials_unavailable"
  | "mailbox_poll_failed"
  | "sender_not_allowed"
  | "attachment_too_large"
  | "attachment_hash_mismatch"
  | "duplicate_attachment"
  | "unsupported_media_type"
  | "magic_byte_mismatch"
  | "malware_detected"
  | "malware_scan_unavailable"
  | "encrypted_storage_write_failed"
  | "encrypted_storage_read_failed"
  | "unsupported_registrar"
  | "unsupported_statement_format"
  | "statement_decryption_failed"
  | "parse_failed"
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

export type RegistrarConfig = {
  registrar: Registrar;
  allowedSenderAddresses: string[];
  maxAttachmentBytes: number;
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
  filename: string;
  declaredMime: string;
  receivedAt: string;
  expectedSha256Hex?: string;
  stream: ReadableStream<Uint8Array>;
};

export type MailMessage = {
  senderAddress: string;
  messageId: string;
  receivedAt: string;
  attachments: EmailAttachment[];
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
  correlationId: string;
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
  correlationId: string;
  registrar: Registrar;
  failureCode: FailureCode;
  sha256Hex?: string;
  storage?: StoredObject;
  detectedMime?: string;
  fileType?: StatementFileType;
  sizeBytes?: number;
};
