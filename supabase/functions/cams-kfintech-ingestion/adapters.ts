import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.39.8";
import type { PdfTextExtractor } from "./parser.ts";
import {
  DEFAULT_MAX_ATTACHMENT_BYTES,
  readBoundedStream,
  sha256Hex,
} from "./security.ts";
import {
  type CredentialBundle,
  type DownloadedAttachment,
  type EncryptedCredentialEnvelope,
  type FailureCode,
  type FailureLineageInput,
  IngestionError,
  type IngestionRunClaimInput,
  type IngestionRunClaimResult,
  type IngestionRunContext,
  type IngestionRunFinalizeInput,
  type IngestionRunSummary,
  type MailMessage,
  type PersistenceInput,
  type PersistenceResult,
  type Registrar,
  type StoredObject,
} from "./types.ts";

const knownFailureCodes: Set<string> = new Set([
  "authorization_required",
  "not_authorized",
  "mailbox_connection_not_found",
  "oauth_credentials_unavailable",
  "attachment_hash_mismatch",
  "duplicate_attachment",
  "correlation_conflict",
  "ingestion_run_in_progress",
  "ingestion_run_not_claimed",
  "ingestion_run_finalized",
  "attempt_lineage_incomplete",
  "previous_ingestion_failed",
  "processing_incomplete",
  "investor_mapping_unresolved",
  "investor_mapping_ambiguous",
  "investor_workspace_relationship_required",
  "amc_mapping_unresolved",
  "amc_mapping_conflict",
  "portfolio_mapping_ambiguous",
  "folio_relationship_conflict",
  "storage_object_conflict",
  "stored_object_hash_mismatch",
  "stored_object_size_mismatch",
  "unsupported_registrar",
  "unsupported_statement_format",
  "unsupported_report",
  "parse_failed",
  "persistence_conflict",
  "persistence_failed",
  "oauth_request_invalid",
  "oauth_state_invalid",
  "oauth_state_expired",
  "oauth_state_replayed",
  "oauth_redirect_uri_mismatch",
  "oauth_code_required",
  "oauth_provider_error",
  "oauth_refresh_token_required",
  "oauth_exchange_failed",
  "oauth_revocation_failed",
]);

function errorCodeFromRpc(error: { message?: string } | null): FailureCode {
  const code = error?.message?.match(/([a-z][a-z0-9_]+)$/)?.[1] ??
    "persistence_failed";
  return knownFailureCodes.has(code)
    ? code as FailureCode
    : "persistence_failed";
}

type CredentialEnvelopeRow = {
  credential_ciphertext: string;
  credential_nonce: string;
  key_version: number;
};

type RegistrarConfigRow = {
  registrar: Registrar;
  allowed_sender_addresses: string[];
  max_attachment_bytes: number | null;
  max_messages_per_poll: number | null;
  max_attachments_per_message: number | null;
  max_attachments_per_run: number | null;
  total_bytes_per_run: number | null;
  supported_file_types: ("CAS_PDF" | "DBF")[] | null;
};

function bearerTokenFromHeader(header: string | null): string | null {
  if (header == null || !header.startsWith("Bearer ")) {
    return null;
  }
  const token = header.substring("Bearer ".length).trim();
  return token.length === 0 ? null : token;
}

function b64ToBytes(value: string): Uint8Array {
  try {
    return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
  } catch (_error) {
    throw new IngestionError("oauth_credentials_unavailable");
  }
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function bytesToText(value: ArrayBuffer): string {
  return new TextDecoder().decode(value);
}

function validPositive(
  value: number | null | undefined,
  fallback: number,
): number {
  if (value == null || !Number.isFinite(value) || value <= 0) {
    return fallback;
  }
  return Math.floor(value);
}

function requirePositive(value: number, code: FailureCode): number {
  if (!Number.isFinite(value) || value <= 0) {
    throw new IngestionError(code);
  }
  return Math.floor(value);
}

function timeoutController(timeoutMs: number): {
  signal: AbortSignal;
  cancel: () => void;
} {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  return {
    signal: controller.signal,
    cancel: () => clearTimeout(timeout),
  };
}

async function importAesKey(rawBase64: string): Promise<CryptoKey> {
  const keyBytes = b64ToBytes(rawBase64);
  if (keyBytes.byteLength !== 32) {
    throw new IngestionError("oauth_credentials_unavailable");
  }
  return await crypto.subtle.importKey(
    "raw",
    new Uint8Array(keyBytes),
    "AES-GCM",
    false,
    ["encrypt", "decrypt"],
  );
}

function additionalData(
  workspaceId: string,
  mailboxConnectionId: string,
  keyVersion: number,
): string {
  if (keyVersion !== 1) {
    throw new IngestionError("oauth_credentials_unavailable");
  }
  return `${workspaceId}:${mailboxConnectionId}:${keyVersion}`;
}

async function decryptAesGcm(
  ciphertextBase64: string,
  nonceBase64: string,
  key: CryptoKey,
  aad: string,
): Promise<string> {
  try {
    const nonce = b64ToBytes(nonceBase64);
    if (nonce.byteLength !== 12) {
      throw new IngestionError("oauth_credentials_unavailable");
    }
    const ciphertext = b64ToBytes(ciphertextBase64);
    const plaintext = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: new Uint8Array(nonce),
        additionalData: new TextEncoder().encode(aad),
      },
      key,
      new Uint8Array(ciphertext),
    );
    return bytesToText(plaintext);
  } catch (error) {
    if (error instanceof IngestionError) throw error;
    throw new IngestionError("oauth_credentials_unavailable");
  }
}

async function encryptAesGcm(
  plaintext: string,
  key: CryptoKey,
  aad: string,
): Promise<{ ciphertext: string; nonce: string }> {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    {
      name: "AES-GCM",
      iv: nonce,
      additionalData: new TextEncoder().encode(aad),
    },
    key,
    new TextEncoder().encode(plaintext),
  );
  return {
    ciphertext: bytesToBase64(new Uint8Array(ciphertext)),
    nonce: bytesToBase64(nonce),
  };
}

function recordFromUnknown(
  value: unknown,
  code: FailureCode = "mailbox_poll_failed",
): Record<string, unknown> {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    throw new IngestionError(code);
  }
  return value as Record<string, unknown>;
}

function parseTrustedConnectorUrl(
  connectorUrl: string,
  allowInsecureConnector: boolean,
): URL {
  try {
    const parsed = new URL(connectorUrl);
    const isLocalhost = parsed.hostname === "localhost" ||
      parsed.hostname === "127.0.0.1";
    if (
      parsed.protocol !== "https:" &&
      !(allowInsecureConnector && parsed.protocol === "http:" && isLocalhost)
    ) {
      throw new IngestionError("connector_untrusted_origin");
    }
    return parsed;
  } catch (error) {
    if (error instanceof IngestionError) throw error;
    throw new IngestionError("connector_untrusted_origin");
  }
}

function endpoint(baseUrl: URL, suffix: string): URL {
  const basePath = baseUrl.pathname.endsWith("/")
    ? baseUrl.pathname.slice(0, -1)
    : baseUrl.pathname;
  const next = new URL(baseUrl.toString());
  next.pathname = `${basePath}${suffix}`;
  next.search = "";
  next.hash = "";
  return next;
}

function assertSameOrigin(url: URL, expectedOrigin: string): void {
  if (url.origin !== expectedOrigin) {
    throw new IngestionError("connector_untrusted_origin");
  }
}

async function readJsonResponse(
  response: Response,
  maxBytes: number,
  code: FailureCode,
  signal?: AbortSignal,
): Promise<Record<string, unknown>> {
  if (response.body == null || maxBytes <= 0 || !Number.isFinite(maxBytes)) {
    throw new IngestionError(code);
  }
  let bytes: Uint8Array;
  try {
    bytes = await readBoundedStream(response.body, Math.floor(maxBytes), {
      signal,
      abortCode: code,
      emptyCode: code,
    });
  } catch (_error) {
    throw new IngestionError(code);
  }
  try {
    return recordFromUnknown(JSON.parse(new TextDecoder().decode(bytes)), code);
  } catch (error) {
    if (error instanceof IngestionError) throw error;
    throw new IngestionError(code);
  }
}

function isExpiringSoon(
  expiresAt: string | undefined,
  now = Date.now(),
): boolean {
  if (expiresAt == null || expiresAt.trim() === "") return false;
  const expires = Date.parse(expiresAt);
  if (!Number.isFinite(expires)) return true;
  return expires - now <= 5 * 60 * 1000;
}

export class CredentialEnvelopeCrypto {
  constructor(private readonly keyBase64: string) {}

  async decrypt(
    envelope: EncryptedCredentialEnvelope,
    workspaceId: string,
    mailboxConnectionId: string,
  ): Promise<CredentialBundle> {
    const key = await importAesKey(this.keyBase64);
    const plaintext = await decryptAesGcm(
      envelope.credentialCiphertext,
      envelope.credentialNonce,
      key,
      additionalData(workspaceId, mailboxConnectionId, envelope.keyVersion),
    );
    const parsed = recordFromUnknown(
      JSON.parse(plaintext),
      "oauth_credentials_unavailable",
    );
    if (typeof parsed.accessToken !== "string" || parsed.accessToken === "") {
      throw new IngestionError("oauth_credentials_unavailable");
    }
    return {
      accessToken: parsed.accessToken,
      refreshToken: typeof parsed.refreshToken === "string"
        ? parsed.refreshToken
        : undefined,
      expiresAt: typeof parsed.expiresAt === "string"
        ? parsed.expiresAt
        : undefined,
    };
  }

  async encrypt(
    bundle: CredentialBundle,
    workspaceId: string,
    mailboxConnectionId: string,
    keyVersion = 1,
  ): Promise<EncryptedCredentialEnvelope> {
    if (bundle.accessToken.trim() === "") {
      throw new IngestionError("oauth_credentials_unavailable");
    }
    const key = await importAesKey(this.keyBase64);
    const encrypted = await encryptAesGcm(
      JSON.stringify(bundle),
      key,
      additionalData(workspaceId, mailboxConnectionId, keyVersion),
    );
    return {
      credentialCiphertext: encrypted.ciphertext,
      credentialNonce: encrypted.nonce,
      keyVersion,
    };
  }
}

export type CredentialRefreshClient = {
  refresh(
    context: {
      workspaceId: string;
      mailboxConnectionId: string;
      connectorRef: string;
      registrar: Registrar;
    },
    credentials: CredentialBundle,
  ): Promise<CredentialBundle>;
};

export function supabaseClient(serviceRoleKey: string): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL") || "", serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

function userSupabaseClient(userToken: string): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL") || "",
    Deno.env.get("SUPABASE_ANON_KEY") || "",
    {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${userToken}` } },
    },
  );
}

export class SupabaseWorkspaceAuthorizer {
  constructor(
    private readonly serviceClient: SupabaseClient,
    private readonly userClientFactory: (userToken: string) => SupabaseClient =
      userSupabaseClient,
  ) {}

  async authorize(
    req: Request,
    input: {
      workspaceId: string;
    },
  ): Promise<void> {
    const userToken = bearerTokenFromHeader(
      req.headers.get("x-user-authorization"),
    ) ?? bearerTokenFromHeader(req.headers.get("authorization"));
    if (userToken == null) {
      throw new IngestionError("authorization_required");
    }

    const userResult = await this.serviceClient.auth.getUser(userToken);
    const userId = userResult.data.user?.id;
    if (userResult.error != null || userId == null) {
      throw new IngestionError("not_authorized");
    }

    const userClient = this.userClientFactory(userToken);
    const authorizationResult = await userClient.rpc(
      "authorize_cams_kfintech_workspace",
      { p_workspace_id: input.workspaceId },
    );
    if (
      authorizationResult.error != null || authorizationResult.data !== true
    ) {
      throw new IngestionError("not_authorized");
    }
  }
}

export class SupabaseConfigRepository {
  private readonly crypto: CredentialEnvelopeCrypto;

  constructor(
    private readonly client: SupabaseClient,
    credentialKeyBase64: string,
    private readonly credentialRefresher?: CredentialRefreshClient,
  ) {
    this.crypto = new CredentialEnvelopeCrypto(credentialKeyBase64);
  }

  async loadRunContext(input: {
    workspaceId: string;
    mailboxConnectionId: string;
    correlationId: string;
    registrar: Registrar;
  }): Promise<IngestionRunContext> {
    const { data: mailbox, error: mailboxError } = await this.client
      .from("mailbox_connections")
      .select(
        "id, workspace_id, registrar, mailbox_address, connector_ref, allowed_sender_addresses, status",
      )
      .eq("id", input.mailboxConnectionId)
      .eq("workspace_id", input.workspaceId)
      .eq("registrar", input.registrar)
      .eq("status", "active")
      .maybeSingle();

    if (mailboxError != null || mailbox == null) {
      throw new IngestionError("mailbox_connection_not_found");
    }

    const config = await this.loadRegistrarConfig(
      input.workspaceId,
      input.registrar,
    );
    const credentials = await this.loadCredentials(
      input.workspaceId,
      input.mailboxConnectionId,
      mailbox.connector_ref,
      input.registrar,
    );
    return {
      workspaceId: input.workspaceId,
      mailboxConnectionId: input.mailboxConnectionId,
      correlationId: input.correlationId,
      mailbox: {
        id: mailbox.id,
        workspaceId: mailbox.workspace_id,
        registrar: mailbox.registrar,
        connectorRef: mailbox.connector_ref,
        mailboxAddress: mailbox.mailbox_address,
        allowedSenderAddresses: mailbox.allowed_sender_addresses ?? [],
        maxAttachmentBytes: config.max_attachment_bytes ??
          DEFAULT_MAX_ATTACHMENT_BYTES,
      },
      credentials,
      registrarConfig: {
        registrar: config.registrar,
        allowedSenderAddresses: config.allowed_sender_addresses ?? [],
        maxAttachmentBytes: validPositive(
          config.max_attachment_bytes,
          DEFAULT_MAX_ATTACHMENT_BYTES,
        ),
        maxMessagesPerPoll: validPositive(config.max_messages_per_poll, 25),
        maxAttachmentsPerMessage: validPositive(
          config.max_attachments_per_message,
          5,
        ),
        maxAttachmentsPerRun: validPositive(config.max_attachments_per_run, 25),
        totalBytesPerRun: validPositive(
          config.total_bytes_per_run,
          DEFAULT_MAX_ATTACHMENT_BYTES,
        ),
        supportedFileTypes: config.supported_file_types ?? ["CAS_PDF", "DBF"],
      },
    };
  }

  private async loadRegistrarConfig(
    workspaceId: string,
    registrar: Registrar,
  ): Promise<RegistrarConfigRow> {
    const selectList =
      "registrar, allowed_sender_addresses, max_attachment_bytes, max_messages_per_poll, max_attachments_per_message, max_attachments_per_run, total_bytes_per_run, supported_file_types";
    const workspace = await this.client
      .from("registrar_configs")
      .select(selectList)
      .eq("workspace_id", workspaceId)
      .eq("registrar", registrar)
      .eq("is_active", true)
      .limit(2);

    if (workspace.error != null) {
      throw new IngestionError("unsupported_registrar");
    }
    if ((workspace.data ?? []).length > 1) {
      throw new IngestionError("configuration_ambiguous");
    }
    if ((workspace.data ?? []).length === 1) {
      return workspace.data![0] as RegistrarConfigRow;
    }

    const global = await this.client
      .from("registrar_configs")
      .select(selectList)
      .is("workspace_id", null)
      .eq("registrar", registrar)
      .eq("is_active", true)
      .limit(2);
    if (global.error != null) {
      throw new IngestionError("unsupported_registrar");
    }
    if ((global.data ?? []).length > 1) {
      throw new IngestionError("configuration_ambiguous");
    }
    if ((global.data ?? []).length === 1) {
      return global.data![0] as RegistrarConfigRow;
    }
    throw new IngestionError("unsupported_registrar");
  }

  private async loadCredentials(
    workspaceId: string,
    mailboxConnectionId: string,
    connectorRef: string,
    registrar: Registrar,
  ): Promise<CredentialBundle> {
    const { data, error } = await this.client.rpc(
      "load_mailbox_oauth_credential_envelope",
      {
        p_workspace_id: workspaceId,
        p_mailbox_connection_id: mailboxConnectionId,
      },
    );

    if (error != null || data == null) {
      throw new IngestionError("oauth_credentials_unavailable");
    }

    const row = (Array.isArray(data) ? data[0] : data) as CredentialEnvelopeRow;
    let credentials = await this.crypto.decrypt(
      {
        credentialCiphertext: row.credential_ciphertext,
        credentialNonce: row.credential_nonce,
        keyVersion: row.key_version,
      },
      workspaceId,
      mailboxConnectionId,
    );

    if (isExpiringSoon(credentials.expiresAt)) {
      if (this.credentialRefresher == null) {
        throw new IngestionError("credential_refresh_failed");
      }
      credentials = await this.credentialRefresher.refresh({
        workspaceId,
        mailboxConnectionId,
        connectorRef,
        registrar,
      }, credentials);
      const refreshed = await this.crypto.encrypt(
        credentials,
        workspaceId,
        mailboxConnectionId,
        row.key_version,
      );
      const replace = await this.client.rpc(
        "replace_mailbox_oauth_credential_envelope",
        {
          p_workspace_id: workspaceId,
          p_mailbox_connection_id: mailboxConnectionId,
          p_credential_ciphertext: refreshed.credentialCiphertext,
          p_credential_nonce: refreshed.credentialNonce,
          p_key_version: refreshed.keyVersion,
          p_expires_at: credentials.expiresAt ?? null,
        },
      );
      if (replace.error != null) {
        throw new IngestionError("credential_refresh_failed");
      }
    }

    return credentials;
  }

  async loadForRevocation(
    workspaceId: string,
    mailboxConnectionId: string,
  ): Promise<{ bundle: CredentialBundle; credentialNonce: string }> {
    const { data, error } = await this.client.rpc(
      "load_mailbox_oauth_credential_envelope",
      {
        p_workspace_id: workspaceId,
        p_mailbox_connection_id: mailboxConnectionId,
      },
    );
    if (error != null || data == null) {
      throw new IngestionError("oauth_credentials_unavailable");
    }
    const row = (Array.isArray(data) ? data[0] : data) as CredentialEnvelopeRow;
    const bundle = await this.crypto.decrypt(
      {
        credentialCiphertext: row.credential_ciphertext,
        credentialNonce: row.credential_nonce,
        keyVersion: row.key_version,
      },
      workspaceId,
      mailboxConnectionId,
    );
    return { bundle, credentialNonce: row.credential_nonce };
  }
}

type OAuthStateRow = {
  authorization_id: string;
  workspace_id: string;
  mailbox_connection_id: string;
  flow_kind: "first_time" | "reauthorization";
};

export class SupabaseOAuthStateRepository {
  constructor(private readonly serviceClient: SupabaseClient) {}

  async begin(input: {
    userToken: string;
    workspaceId: string;
    mailboxConnectionId: string;
    stateHash: string;
    redirectUri: string;
    expiresAt: string;
  }): Promise<{ flowKind: "first_time" | "reauthorization" }> {
    const client = userSupabaseClient(input.userToken);
    const { data, error } = await client.rpc("begin_mailbox_oauth_authorization", {
      p_workspace_id: input.workspaceId,
      p_mailbox_connection_id: input.mailboxConnectionId,
      p_state_hash: input.stateHash,
      p_redirect_uri: input.redirectUri,
      p_expires_at: input.expiresAt,
    });
    if (error != null || data == null) throw new IngestionError(errorCodeFromRpc(error));
    const row = (Array.isArray(data) ? data[0] : data) as OAuthStateRow;
    return { flowKind: row.flow_kind };
  }

  async consume(stateHash: string, redirectUri: string): Promise<{
    authorizationId: string;
    workspaceId: string;
    mailboxConnectionId: string;
    flowKind: "first_time" | "reauthorization";
  }> {
    const { data, error } = await this.serviceClient.rpc(
      "consume_mailbox_oauth_authorization",
      { p_state_hash: stateHash, p_redirect_uri: redirectUri },
    );
    if (error != null || data == null) throw new IngestionError(errorCodeFromRpc(error));
    const row = (Array.isArray(data) ? data[0] : data) as OAuthStateRow;
    return {
      authorizationId: row.authorization_id,
      workspaceId: row.workspace_id,
      mailboxConnectionId: row.mailbox_connection_id,
      flowKind: row.flow_kind,
    };
  }

  async fail(authorizationId: string, code: FailureCode): Promise<void> {
    const { error } = await this.serviceClient.rpc("fail_mailbox_oauth_authorization", {
      p_authorization_id: authorizationId,
      p_failure_code: code,
    });
    if (error != null) throw new IngestionError(errorCodeFromRpc(error));
  }

  async complete(input: {
    authorizationId: string;
    envelope: EncryptedCredentialEnvelope;
    expiresAt: string;
  }): Promise<"first_time" | "reauthorization"> {
    const { data, error } = await this.serviceClient.rpc(
      "complete_mailbox_oauth_authorization",
      {
        p_authorization_id: input.authorizationId,
        p_credential_ciphertext: input.envelope.credentialCiphertext,
        p_credential_nonce: input.envelope.credentialNonce,
        p_key_version: input.envelope.keyVersion,
        p_expires_at: input.expiresAt,
      },
    );
    if (error != null || (data !== "first_time" && data !== "reauthorization")) {
      throw new IngestionError(errorCodeFromRpc(error));
    }
    return data;
  }

  async revoke(input: {
    userToken: string;
    workspaceId: string;
    mailboxConnectionId: string;
    expectedCredentialNonce: string;
  }): Promise<void> {
    const client = userSupabaseClient(input.userToken);
    const { error } = await client.rpc("revoke_mailbox_oauth_credential", {
      p_workspace_id: input.workspaceId,
      p_mailbox_connection_id: input.mailboxConnectionId,
      p_expected_credential_nonce: input.expectedCredentialNonce,
    });
    if (error != null) throw new IngestionError(errorCodeFromRpc(error));
  }
}

export class ConnectorGmailOAuthClient {
  private readonly baseUrl: URL;

  constructor(
    connectorUrl: string,
    private readonly connectorServiceToken: string,
    allowInsecureConnector = false,
    private readonly timeoutMs = 5000,
    private readonly maxResponseBytes = 65536,
  ) {
    if (connectorServiceToken.trim() === "") throw new IngestionError("connector_untrusted_origin");
    this.timeoutMs = requirePositive(timeoutMs, "connector_untrusted_origin");
    this.maxResponseBytes = requirePositive(
      maxResponseBytes,
      "connector_untrusted_origin",
    );
    this.baseUrl = parseTrustedConnectorUrl(connectorUrl, allowInsecureConnector);
  }

  private async post(path: string, body: Record<string, unknown>): Promise<Response> {
    const deadline = timeoutController(this.timeoutMs);
    try {
      const result = await fetch(endpoint(this.baseUrl, path), {
        method: "POST",
        redirect: "manual",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.connectorServiceToken}`,
        },
        body: JSON.stringify(body),
        signal: deadline.signal,
      });
      if (result.status >= 300 && result.status < 400) {
        throw new IngestionError("connector_untrusted_origin");
      }
      if (result.url !== "") assertSameOrigin(new URL(result.url), this.baseUrl.origin);
      return result;
    } catch (error) {
      if (error instanceof IngestionError) throw error;
      throw new IngestionError("oauth_exchange_failed");
    } finally {
      deadline.cancel();
    }
  }

  async authorizationUrl(state: string, redirectUri: string): Promise<string> {
    const result = await this.post("/oauth/authorization-url", {
      state,
      redirect_uri: redirectUri,
    });
    if (!result.ok) throw new IngestionError("oauth_exchange_failed");
    const payload = await readJsonResponse(result, this.maxResponseBytes, "oauth_exchange_failed");
    if (typeof payload.authorization_url !== "string") {
      throw new IngestionError("oauth_exchange_failed");
    }
    return payload.authorization_url;
  }

  async exchange(code: string, redirectUri: string): Promise<CredentialBundle> {
    const result = await this.post("/oauth/exchange", { code, redirect_uri: redirectUri });
    if (!result.ok) {
      let providerCode = "";
      try {
        const payload = await readJsonResponse(result, this.maxResponseBytes, "oauth_exchange_failed");
        const error = recordFromUnknown(payload.error, "oauth_exchange_failed");
        providerCode = typeof error.code === "string" ? error.code : "";
      } catch (_error) {
        // Provider details are deliberately reduced to a stable local failure code.
      }
      throw new IngestionError(
        providerCode === "oauth_refresh_token_required"
          ? "oauth_refresh_token_required"
          : "oauth_exchange_failed",
      );
    }
    const payload = await readJsonResponse(result, this.maxResponseBytes, "oauth_exchange_failed");
    if (
      typeof payload.access_token !== "string" || payload.access_token === "" ||
      typeof payload.refresh_token !== "string" || payload.refresh_token === "" ||
      typeof payload.expires_at !== "string"
    ) throw new IngestionError("oauth_refresh_token_required");
    return {
      accessToken: payload.access_token,
      refreshToken: payload.refresh_token,
      expiresAt: payload.expires_at,
    };
  }

  async revoke(token: string): Promise<void> {
    const result = await this.post("/oauth/revoke", { token });
    if (result.status !== 204) throw new IngestionError("oauth_revocation_failed");
  }
}

export class ConnectorCredentialRefresher implements CredentialRefreshClient {
  private readonly baseUrl: URL;

  constructor(
    connectorUrl: string,
    private readonly connectorServiceToken: string,
    allowInsecureConnector = false,
    private readonly timeoutMs = 5000,
    private readonly maxResponseBytes = 65536,
  ) {
    if (connectorServiceToken.trim() === "") {
      throw new IngestionError("connector_untrusted_origin");
    }
    this.timeoutMs = requirePositive(timeoutMs, "connector_untrusted_origin");
    this.maxResponseBytes = requirePositive(
      maxResponseBytes,
      "connector_untrusted_origin",
    );
    this.baseUrl = parseTrustedConnectorUrl(
      connectorUrl,
      allowInsecureConnector,
    );
  }

  async refresh(
    context: {
      workspaceId: string;
      mailboxConnectionId: string;
      connectorRef: string;
      registrar: Registrar;
    },
    credentials: CredentialBundle,
  ): Promise<CredentialBundle> {
    const deadline = timeoutController(this.timeoutMs);
    try {
      const response = await fetch(endpoint(this.baseUrl, "/oauth/refresh"), {
        method: "POST",
        redirect: "manual",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.connectorServiceToken}`,
        },
        body: JSON.stringify({
          workspace_id: context.workspaceId,
          mailbox_connection_id: context.mailboxConnectionId,
          connector_ref: context.connectorRef,
          registrar: context.registrar,
          refresh_token: credentials.refreshToken,
        }),
        signal: deadline.signal,
      });
      if (response.status >= 300 && response.status < 400) {
        throw new IngestionError("connector_untrusted_origin");
      }
      if (response.url !== "") {
        assertSameOrigin(new URL(response.url), this.baseUrl.origin);
      }
      if (!response.ok) {
        throw new IngestionError("credential_refresh_failed");
      }
      const payload = await readJsonResponse(
        response,
        this.maxResponseBytes,
        "credential_refresh_failed",
        deadline.signal,
      );
      if (
        typeof payload.access_token !== "string" || payload.access_token === ""
      ) {
        throw new IngestionError("credential_refresh_failed");
      }
      return {
        accessToken: payload.access_token,
        refreshToken: typeof payload.refresh_token === "string"
          ? payload.refresh_token
          : credentials.refreshToken,
        expiresAt: typeof payload.expires_at === "string"
          ? payload.expires_at
          : undefined,
      };
    } catch (error) {
      if (error instanceof IngestionError) throw error;
      throw new IngestionError("credential_refresh_failed");
    } finally {
      deadline.cancel();
    }
  }
}

export class ConnectorMailboxClient {
  private readonly baseUrl: URL;

  constructor(
    connectorUrl: string,
    private readonly connectorServiceToken: string,
    allowInsecureConnector = false,
    private readonly timeoutMs = 5000,
    private readonly maxResponseBytes = 1048576,
    private readonly attachmentDownloadTimeoutMs = 10000,
  ) {
    if (connectorServiceToken.trim() === "") {
      throw new IngestionError("connector_untrusted_origin");
    }
    this.timeoutMs = requirePositive(timeoutMs, "connector_untrusted_origin");
    this.maxResponseBytes = requirePositive(
      maxResponseBytes,
      "connector_untrusted_origin",
    );
    this.attachmentDownloadTimeoutMs = requirePositive(
      attachmentDownloadTimeoutMs,
      "connector_untrusted_origin",
    );
    this.baseUrl = parseTrustedConnectorUrl(
      connectorUrl,
      allowInsecureConnector,
    );
  }

  async poll(context: IngestionRunContext): Promise<MailMessage[]> {
    const deadline = timeoutController(this.timeoutMs);
    try {
      const response = await fetch(endpoint(this.baseUrl, "/poll"), {
        method: "POST",
        redirect: "manual",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.connectorServiceToken}`,
          "X-Mailbox-OAuth-Token": context.credentials.accessToken,
        },
        body: JSON.stringify({
          connector_ref: context.mailbox.connectorRef,
          mailbox_connection_id: context.mailboxConnectionId,
          registrar: context.mailbox.registrar,
        }),
        signal: deadline.signal,
      });
      if (response.status >= 300 && response.status < 400) {
        throw new IngestionError("connector_untrusted_origin");
      }
      if (response.url !== "") {
        assertSameOrigin(new URL(response.url), this.baseUrl.origin);
      }
      if (!response.ok) {
        throw new IngestionError("mailbox_poll_failed");
      }
      const payload = await readJsonResponse(
        response,
        this.maxResponseBytes,
        "mailbox_poll_failed",
        deadline.signal,
      );
      const messages = payload.messages;
      if (!Array.isArray(messages)) {
        throw new IngestionError("mailbox_poll_failed");
      }

      return messages.map((rawMessage): MailMessage => {
        const message = recordFromUnknown(rawMessage);
        const attachments = message.attachments;
        if (!Array.isArray(attachments)) {
          throw new IngestionError("mailbox_poll_failed");
        }
        if (
          typeof message.message_id !== "string" ||
          message.message_id.trim() === ""
        ) {
          throw new IngestionError("mailbox_poll_failed");
        }
        const outcome = message.outcome == null
          ? undefined
          : message.outcome === "no_data" ||
              message.outcome === "unsupported_report"
          ? message.outcome
          : (() => {
            throw new IngestionError("mailbox_poll_failed");
          })();
        if (
          (outcome == null && attachments.length === 0) ||
          (outcome != null &&
            (attachments.length > 0 || context.mailbox.registrar !== "CAMS"))
        ) {
          throw new IngestionError("mailbox_poll_failed");
        }
        return {
          senderAddress: String(message.sender_address ?? ""),
          messageId: message.message_id.trim(),
          receivedAt: String(message.received_at ?? new Date().toISOString()),
          outcome,
          attachments: attachments.map(
            (rawAttachment): MailMessage["attachments"][number] => {
              const attachment = recordFromUnknown(rawAttachment);
              if (
                typeof attachment.attachment_id !== "string" ||
                attachment.attachment_id.trim() === ""
              ) {
                throw new IngestionError("mailbox_poll_failed");
              }
              if (attachment.download_url != null) {
                throw new IngestionError("connector_untrusted_origin");
              }
              return {
                attachmentId: attachment.attachment_id.trim(),
                filename: String(attachment.filename ?? "statement"),
                declaredMime: String(
                  attachment.declared_mime ?? "application/octet-stream",
                ),
                receivedAt: String(
                  attachment.received_at ?? message.received_at ??
                    new Date().toISOString(),
                ),
                expectedSha256Hex: attachment.expected_sha256_hex == null
                  ? undefined
                  : String(attachment.expected_sha256_hex),
              };
            },
          ),
        };
      });
    } catch (error) {
      if (error instanceof IngestionError) throw error;
      throw new IngestionError("mailbox_poll_failed");
    } finally {
      deadline.cancel();
    }
  }

  async downloadAttachment(
    context: IngestionRunContext,
    message: MailMessage,
    attachment: MailMessage["attachments"][number],
  ): Promise<DownloadedAttachment> {
    const deadline = timeoutController(this.attachmentDownloadTimeoutMs);
    try {
      const response = await fetch(
        endpoint(this.baseUrl, "/attachments/fetch"),
        {
          method: "POST",
          redirect: "manual",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${this.connectorServiceToken}`,
          },
          body: JSON.stringify({
            connector_ref: context.mailbox.connectorRef,
            mailbox_connection_id: context.mailboxConnectionId,
            registrar: context.mailbox.registrar,
            message_id: message.messageId,
            attachment_id: attachment.attachmentId,
          }),
          signal: deadline.signal,
        },
      );
      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get("location");
        if (location != null) {
          assertSameOrigin(
            new URL(location, this.baseUrl),
            this.baseUrl.origin,
          );
        }
        throw new IngestionError("connector_untrusted_origin");
      }
      if (!response.ok || response.body == null) {
        throw new IngestionError("mailbox_poll_failed");
      }
      if (response.url !== "") {
        assertSameOrigin(new URL(response.url), this.baseUrl.origin);
      }
      return {
        ...attachment,
        stream: response.body,
        deadlineSignal: deadline.signal,
        cancelDeadline: deadline.cancel,
      };
    } catch (error) {
      deadline.cancel();
      if (error instanceof IngestionError) throw error;
      throw new IngestionError("mailbox_poll_failed");
    }
  }
}

export class HttpMalwareScanner {
  private readonly baseUrl: URL;

  constructor(
    scannerUrl: string,
    private readonly scannerServiceToken: string,
    private readonly timeoutMs: number,
    private readonly maxResponseBytes = 4096,
    allowInsecureScanner = false,
  ) {
    if (scannerServiceToken.trim() === "") {
      throw new IngestionError("malware_scan_unavailable");
    }
    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
      throw new IngestionError("malware_scan_unavailable");
    }
    this.baseUrl = parseTrustedConnectorUrl(scannerUrl, allowInsecureScanner);
  }

  async scan(
    bytes: Uint8Array,
    context: { sha256Hex: string; filename: string },
  ): Promise<"clean"> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await fetch(this.baseUrl, {
        method: "POST",
        redirect: "manual",
        headers: {
          "Content-Type": "application/octet-stream",
          Authorization: `Bearer ${this.scannerServiceToken}`,
          "X-Content-SHA256": context.sha256Hex,
          "X-File-Name": context.filename,
        },
        body: new Uint8Array(bytes),
        signal: controller.signal,
      });
      if (response.status >= 300 && response.status < 400) {
        throw new IngestionError("malware_scan_unavailable");
      }
      if (response.url !== "") {
        assertSameOrigin(new URL(response.url), this.baseUrl.origin);
      }
      if (!response.ok) {
        throw new IngestionError("malware_scan_unavailable");
      }
      const result = await readJsonResponse(
        response,
        this.maxResponseBytes,
        "malware_scan_unavailable",
      );
      if (result.version !== "moneybowl.malware-scan.v1") {
        throw new IngestionError("malware_scan_unavailable");
      }
      if (result.verdict === "clean") {
        return "clean";
      }
      if (result.verdict === "infected") {
        throw new IngestionError("malware_detected");
      }
      throw new IngestionError("malware_scan_unavailable");
    } catch (error) {
      if (error instanceof IngestionError) throw error;
      throw new IngestionError("malware_scan_unavailable");
    } finally {
      clearTimeout(timeout);
    }
  }
}

export class SupabaseEncryptedStorage {
  constructor(
    private readonly client: SupabaseClient,
    private readonly bucket: string,
  ) {}

  async writeOriginal(input: {
    context: IngestionRunContext;
    attachment: { filename: string };
    sha256Hex: string;
    bytes: Uint8Array;
    detectedMime: string;
  }): Promise<StoredObject> {
    const path =
      `${input.context.workspaceId}/${input.context.mailboxConnectionId}/${input.sha256Hex}`;
    const { error } = await this.client.storage.from(this.bucket).upload(
      path,
      input.bytes,
      {
        contentType: input.detectedMime,
        upsert: false,
      },
    );
    if (error != null) {
      let existing: Uint8Array;
      try {
        existing = await this.readOriginal({ bucket: this.bucket, path });
      } catch (_readError) {
        throw new IngestionError("encrypted_storage_write_failed");
      }
      if (existing.byteLength !== input.bytes.byteLength) {
        throw new IngestionError("storage_object_conflict");
      }
      const existingSha = await sha256Hex(existing);
      if (existingSha !== input.sha256Hex) {
        throw new IngestionError("storage_object_conflict");
      }
    }
    return { bucket: this.bucket, path };
  }

  async readOriginal(object: StoredObject): Promise<Uint8Array> {
    const { data, error } = await this.client.storage.from(object.bucket)
      .download(object.path);
    if (error != null || data == null) {
      throw new IngestionError("encrypted_storage_read_failed");
    }
    if (data.size > DEFAULT_MAX_ATTACHMENT_BYTES) {
      throw new IngestionError("stored_object_size_mismatch");
    }
    return await readBoundedStream(data.stream(), DEFAULT_MAX_ATTACHMENT_BYTES);
  }
}

export class SupabasePersistence {
  constructor(private readonly client: SupabaseClient) {}

  async claimRun(
    input: IngestionRunClaimInput,
  ): Promise<IngestionRunClaimResult> {
    const { data, error } = await this.client.rpc(
      "claim_cams_kfintech_ingestion_run",
      {
        p_workspace_id: input.workspaceId,
        p_mailbox_connection_id: input.mailboxConnectionId,
        p_ingestion_run_id: input.ingestionRunId,
        p_registrar: input.registrar,
      },
    );
    if (error != null) {
      throw new IngestionError(errorCodeFromRpc(error));
    }
    return (Array.isArray(data) ? data[0] : data) as IngestionRunClaimResult;
  }

  async finalizeRun(
    input: IngestionRunFinalizeInput,
  ): Promise<IngestionRunSummary> {
    const { data, error } = await this.client.rpc(
      "finalize_cams_kfintech_ingestion_run",
      {
        p_workspace_id: input.workspaceId,
        p_mailbox_connection_id: input.mailboxConnectionId,
        p_ingestion_run_id: input.ingestionRunId,
        p_registrar: input.registrar,
        p_stopped_reason: input.stoppedReason ?? null,
        p_failure_code: input.failureCode ?? null,
        p_observed_attachment_count: input.observedAttachmentCount ?? null,
      },
    );
    if (error != null) {
      throw new IngestionError(errorCodeFromRpc(error));
    }
    return (Array.isArray(data) ? data[0] : data) as IngestionRunSummary;
  }

  async finalizeNoDataRun(
    input: IngestionRunClaimInput,
  ): Promise<IngestionRunSummary> {
    const { data, error } = await this.client.rpc(
      "finalize_cams_kfintech_no_data_run",
      {
        p_workspace_id: input.workspaceId,
        p_mailbox_connection_id: input.mailboxConnectionId,
        p_ingestion_run_id: input.ingestionRunId,
        p_registrar: input.registrar,
      },
    );
    if (error != null) {
      throw new IngestionError(errorCodeFromRpc(error));
    }
    return (Array.isArray(data) ? data[0] : data) as IngestionRunSummary;
  }

  async persist(input: PersistenceInput): Promise<PersistenceResult> {
    const { data, error } = await this.client.rpc(
      "persist_cams_kfintech_statement_ingestion",
      {
        p_workspace_id: input.workspaceId,
        p_mailbox_connection_id: input.mailboxConnectionId,
        p_ingestion_run_id: input.ingestionRunId,
        p_document_correlation_id: input.documentCorrelationId,
        p_provider_message_id: input.providerMessageId,
        p_provider_attachment_id: input.providerAttachmentId,
        p_attachment_attempt_key: input.attachmentAttemptKey,
        p_registrar: input.registrar,
        p_attachment_sha256: input.sha256Hex,
        p_storage_bucket: input.storage.bucket,
        p_storage_object_path: input.storage.path,
        p_detected_mime: input.detectedMime,
        p_file_type: input.fileType,
        p_size_bytes: input.sizeBytes,
        p_received_at: input.receivedAt,
        p_transactions: input.transactions,
      },
    );
    if (error != null) {
      throw new IngestionError(errorCodeFromRpc(error));
    }
    const result = (Array.isArray(data) ? data[0] : data) as PersistenceResult;
    if (result.failure_code != null) {
      throw new IngestionError(result.failure_code);
    }
    return result;
  }

  async recordFailure(input: FailureLineageInput): Promise<void> {
    const { error } = await this.client.rpc(
      "record_cams_kfintech_ingestion_failure",
      {
        p_workspace_id: input.workspaceId,
        p_mailbox_connection_id: input.mailboxConnectionId,
        p_ingestion_run_id: input.ingestionRunId,
        p_document_correlation_id: input.documentCorrelationId,
        p_provider_message_id: input.providerMessageId ?? null,
        p_provider_attachment_id: input.providerAttachmentId ?? null,
        p_attachment_attempt_key: input.attachmentAttemptKey ?? null,
        p_registrar: input.registrar,
        p_failure_code: input.failureCode,
        p_attachment_sha256: input.sha256Hex ?? null,
        p_storage_bucket: input.storage?.bucket ?? null,
        p_storage_object_path: input.storage?.path ?? null,
        p_detected_mime: input.detectedMime ?? null,
        p_file_type: input.fileType ?? null,
        p_size_bytes: input.sizeBytes ?? null,
      },
    );
    if (error != null) {
      throw new IngestionError(errorCodeFromRpc(error));
    }
  }
}

export class RemotePdfTextExtractor implements PdfTextExtractor {
  private readonly baseUrl: URL;

  constructor(
    extractorUrl: string,
    private readonly extractorServiceToken: string,
    private readonly timeoutMs: number,
    private readonly maxResponseBytes: number,
    allowInsecureExtractor = false,
  ) {
    if (extractorServiceToken.trim() === "") {
      throw new IngestionError("unsupported_statement_format");
    }
    if (
      !Number.isFinite(timeoutMs) || timeoutMs <= 0 ||
      !Number.isFinite(maxResponseBytes) || maxResponseBytes <= 0
    ) {
      throw new IngestionError("unsupported_statement_format");
    }
    this.baseUrl = parseTrustedConnectorUrl(
      extractorUrl,
      allowInsecureExtractor,
    );
  }

  async extractRows(input: {
    bytes: Uint8Array;
    registrar: Registrar;
    fileType: "CAS_PDF" | "DBF";
    filename: string;
  }): Promise<Record<string, unknown>[]> {
    if (input.bytes.byteLength < 16) {
      throw new IngestionError("unsupported_statement_format");
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await fetch(this.baseUrl, {
        method: "POST",
        redirect: "manual",
        headers: {
          "Content-Type": "application/pdf",
          Authorization: `Bearer ${this.extractorServiceToken}`,
          "X-Registrar": input.registrar,
          "X-Statement-Format": input.fileType,
          "X-File-Name": input.filename,
        },
        body: new Uint8Array(input.bytes),
        signal: controller.signal,
      });
      if (response.status >= 300 && response.status < 400) {
        throw new IngestionError("parse_failed");
      }
      if (response.url !== "") {
        assertSameOrigin(new URL(response.url), this.baseUrl.origin);
      }
      if (!response.ok) {
        throw new IngestionError("parse_failed");
      }
      const payload = await readJsonResponse(
        response,
        this.maxResponseBytes,
        "parse_failed",
      );
      if (
        payload.version !== "moneybowl.pdf-extraction.v1" ||
        payload.registrar !== input.registrar ||
        payload.statement_format !== input.fileType ||
        !Array.isArray(payload.rows)
      ) {
        throw new IngestionError("parse_failed");
      }
      return payload.rows.map((row) => recordFromUnknown(row, "parse_failed"));
    } catch (error) {
      if (error instanceof IngestionError) throw error;
      throw new IngestionError("parse_failed");
    } finally {
      clearTimeout(timeout);
    }
  }
}
