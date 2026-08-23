import {
  type DetectedFormat,
  type FailureCode,
  IngestionError,
  type Registrar,
} from "./types.ts";

export const DEFAULT_MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024 - 1;

const secretFieldNames = new Set([
  "oauth_access_token",
  "oauth_refresh_token",
  "mailbox_password",
  "cas_decryption_password",
  "allowed_sender_list",
  "malware_result",
  "attachment_hash",
  "registrar_authorization",
  "service_role_key",
]);

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function bearerToken(req: Request): string | null {
  const header = req.headers.get("authorization");
  if (header == null || !header.startsWith("Bearer ")) {
    return null;
  }

  const token = header.substring("Bearer ".length).trim();
  return token.length === 0 ? null : token;
}

async function sha256(bytes: Uint8Array): Promise<Uint8Array> {
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(bytes));
  return new Uint8Array(digest);
}

function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff === 0;
}

export async function verifyInternalInvocation(
  req: Request,
  expectedToken: string,
): Promise<void> {
  const token = bearerToken(req);
  if (token == null) {
    throw new IngestionError("authorization_required");
  }
  if (expectedToken.length === 0) {
    throw new IngestionError("not_authorized");
  }

  const actualDigest = await sha256(new TextEncoder().encode(token));
  const expectedDigest = await sha256(new TextEncoder().encode(expectedToken));
  if (!equalBytes(actualDigest, expectedDigest)) {
    throw new IngestionError("not_authorized");
  }
}

export function assertNoTrustedPlaintextPayload(
  payload: Record<string, unknown>,
): void {
  for (const field of Object.keys(payload)) {
    if (secretFieldNames.has(field)) {
      throw new IngestionError("not_authorized");
    }
  }
}

export async function readBoundedStream(
  stream: ReadableStream<Uint8Array>,
  maxBytes: number,
  options: {
    signal?: AbortSignal;
    abortCode?: FailureCode;
    emptyCode?: FailureCode;
  } = {},
): Promise<Uint8Array> {
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  const abortCode = options.abortCode ?? "mailbox_poll_failed";
  const emptyCode = options.emptyCode ?? "unsupported_statement_format";
  let aborted = options.signal?.aborted ?? false;
  const abort = () => {
    aborted = true;
    void reader.cancel();
  };
  options.signal?.addEventListener("abort", abort, { once: true });

  try {
    while (true) {
      if (aborted) {
        throw new IngestionError(abortCode);
      }
      const { done, value } = await reader.read();
      if (aborted) {
        throw new IngestionError(abortCode);
      }
      if (done) break;
      if (value == null) continue;

      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel();
        throw new IngestionError("attachment_too_large");
      }
      chunks.push(value);
    }
  } finally {
    options.signal?.removeEventListener("abort", abort);
  }

  if (total === 0) {
    throw new IngestionError(emptyCode);
  }

  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await sha256(bytes);
  return Array.from(digest).map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function deterministicUuid(input: string): Promise<string> {
  const digest = await sha256(new TextEncoder().encode(input));
  const bytes = digest.slice(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes).map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join("-");
}

export function normalizeSenderAddress(value: string): string {
  const angleMatch = value.match(/<([^<>@\s]+@[^<>@\s]+)>/);
  const raw = angleMatch?.[1] ?? value;
  const emailMatch = raw.toLowerCase().match(
    /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/,
  );
  return emailMatch?.[0] ?? "";
}

export function validateSender(
  senderAddress: string,
  allowlist: string[],
): void {
  const normalizedSender = normalizeSenderAddress(senderAddress);
  const normalizedAllowlist = allowlist.map(normalizeSenderAddress);
  if (
    normalizedSender === "" || !normalizedAllowlist.includes(normalizedSender)
  ) {
    throw new IngestionError("sender_not_allowed");
  }
}

function looksLikeDbf(bytes: Uint8Array): boolean {
  if (bytes.byteLength < 33) return false;
  const version = bytes[0];
  const validVersion = [0x02, 0x03, 0x30, 0x31, 0x32, 0x83, 0x8b, 0xcb, 0xf5]
    .includes(version);
  if (!validVersion) return false;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const headerLength = view.getUint16(8, true);
  const recordLength = view.getUint16(10, true);
  return headerLength >= 33 && headerLength < bytes.byteLength &&
    recordLength > 1 &&
    bytes[headerLength - 1] === 0x0d;
}

function looksLikePdf(bytes: Uint8Array): boolean {
  if (bytes.byteLength < 8) return false;
  return bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 &&
    bytes[3] === 0x46 && bytes[4] === 0x2d;
}

export function detectAndValidateFormat(
  declaredMime: string,
  bytes: Uint8Array,
): DetectedFormat {
  const normalizedMime = declaredMime.toLowerCase().split(";")[0].trim();
  const isPdf = looksLikePdf(bytes);
  const isDbf = looksLikeDbf(bytes);

  if (isPdf && isDbf) {
    throw new IngestionError("magic_byte_mismatch");
  }

  if (isPdf) {
    if (normalizedMime !== "application/pdf") {
      throw new IngestionError("magic_byte_mismatch");
    }
    return { detectedMime: "application/pdf", fileType: "CAS_PDF" };
  }

  if (isDbf) {
    const allowedDbfMime = [
      "application/x-dbase",
      "application/dbase",
      "application/vnd.dbf",
      "application/octet-stream",
    ];
    if (!allowedDbfMime.includes(normalizedMime)) {
      throw new IngestionError("magic_byte_mismatch");
    }
    return { detectedMime: normalizedMime, fileType: "DBF" };
  }

  throw new IngestionError("unsupported_media_type");
}

export function assertRegistrar(value: unknown): Registrar {
  if (value === "CAMS" || value === "KFINTECH") {
    return value;
  }
  throw new IngestionError("unsupported_registrar");
}

export function errorStatus(code: FailureCode): number {
  switch (code) {
    case "authorization_required":
      return 401;
    case "not_authorized":
      return 403;
    case "oauth_state_replayed":
      return 409;
    case "oauth_exchange_failed":
    case "oauth_revocation_failed":
      return 502;
    case "malware_detected":
    case "sender_not_allowed":
    case "duplicate_attachment":
    case "correlation_conflict":
    case "ingestion_run_in_progress":
    case "ingestion_run_finalized":
    case "attempt_lineage_incomplete":
    case "previous_ingestion_failed":
    case "processing_incomplete":
    case "persistence_conflict":
    case "amc_mapping_conflict":
    case "folio_relationship_conflict":
    case "portfolio_mapping_ambiguous":
      return 409;
    default:
      return 422;
  }
}
