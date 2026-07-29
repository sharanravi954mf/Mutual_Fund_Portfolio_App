import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.39.8";
import type { PdfTextExtractor } from "./parser.ts";
import { DEFAULT_MAX_ATTACHMENT_BYTES } from "./security.ts";
import {
  type CredentialBundle,
  type FailureCode,
  type FailureLineageInput,
  IngestionError,
  type IngestionRunContext,
  type MailMessage,
  type PersistenceInput,
  type PersistenceResult,
  type Registrar,
  type StoredObject,
} from "./types.ts";

const knownFailureCodes: Set<string> = new Set([
  "mailbox_connection_not_found",
  "attachment_hash_mismatch",
  "duplicate_attachment",
  "unsupported_registrar",
  "unsupported_statement_format",
  "parse_failed",
  "persistence_failed",
]);

type CipherRow = {
  access_token_ciphertext: string;
  refresh_token_ciphertext: string | null;
  nonce: string;
  key_version: number;
  expires_at: string | null;
};

function b64ToBytes(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}

function bytesToText(value: ArrayBuffer): string {
  return new TextDecoder().decode(value);
}

async function importAesKey(rawBase64: string): Promise<CryptoKey> {
  if (rawBase64.trim() === "") {
    throw new IngestionError("oauth_credentials_unavailable");
  }
  return await crypto.subtle.importKey(
    "raw",
    b64ToBytes(rawBase64),
    "AES-GCM",
    false,
    ["decrypt"],
  );
}

async function decryptAesGcm(
  ciphertextBase64: string,
  nonceBase64: string,
  key: CryptoKey,
  additionalData: string,
): Promise<string> {
  try {
    const plaintext = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: b64ToBytes(nonceBase64),
        additionalData: new TextEncoder().encode(additionalData),
      },
      key,
      b64ToBytes(ciphertextBase64),
    );
    return bytesToText(plaintext);
  } catch (_error) {
    throw new IngestionError("oauth_credentials_unavailable");
  }
}

function recordFromUnknown(value: unknown): Record<string, unknown> {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    throw new IngestionError("mailbox_poll_failed");
  }
  return value as Record<string, unknown>;
}

export function supabaseClient(serviceRoleKey: string): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL") || "", serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

export class SupabaseConfigRepository {
  constructor(
    private readonly client: SupabaseClient,
    private readonly credentialKeyBase64: string,
  ) {}

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

    const { data: config, error: configError } = await this.client
      .from("registrar_configs")
      .select(
        "registrar, allowed_sender_addresses, max_attachment_bytes, supported_file_types",
      )
      .eq("registrar", input.registrar)
      .eq("is_active", true)
      .or(`workspace_id.eq.${input.workspaceId},workspace_id.is.null`)
      .limit(1)
      .maybeSingle();

    if (configError != null || config == null) {
      throw new IngestionError("unsupported_registrar");
    }

    const credentials = await this.loadCredentials(
      input.workspaceId,
      input.mailboxConnectionId,
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
        maxAttachmentBytes: config.max_attachment_bytes ??
          DEFAULT_MAX_ATTACHMENT_BYTES,
        supportedFileTypes: config.supported_file_types ?? ["CAS_PDF", "DBF"],
      },
    };
  }

  private async loadCredentials(
    workspaceId: string,
    mailboxConnectionId: string,
  ): Promise<CredentialBundle> {
    const { data, error } = await this.client
      .from("mailbox_oauth_credentials")
      .select(
        "access_token_ciphertext, refresh_token_ciphertext, nonce, key_version, expires_at",
      )
      .eq("workspace_id", workspaceId)
      .eq("mailbox_connection_id", mailboxConnectionId)
      .maybeSingle<CipherRow>();

    if (error != null || data == null) {
      throw new IngestionError("oauth_credentials_unavailable");
    }

    const key = await importAesKey(this.credentialKeyBase64);
    const aad = `${workspaceId}:${mailboxConnectionId}:${data.key_version}`;
    const accessToken = await decryptAesGcm(
      data.access_token_ciphertext,
      data.nonce,
      key,
      aad,
    );
    const refreshToken = data.refresh_token_ciphertext == null
      ? undefined
      : await decryptAesGcm(
        data.refresh_token_ciphertext,
        data.nonce,
        key,
        aad,
      );

    return {
      accessToken,
      refreshToken,
      expiresAt: data.expires_at ?? undefined,
    };
  }
}

export class ConnectorMailboxClient {
  constructor(private readonly connectorUrl: string) {}

  async poll(context: IngestionRunContext): Promise<MailMessage[]> {
    if (this.connectorUrl.trim() === "") {
      throw new IngestionError("mailbox_poll_failed");
    }
    const response = await fetch(this.connectorUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${context.credentials.accessToken}`,
      },
      body: JSON.stringify({
        connector_ref: context.mailbox.connectorRef,
        mailbox_connection_id: context.mailboxConnectionId,
        registrar: context.mailbox.registrar,
      }),
    });
    if (!response.ok) {
      throw new IngestionError("mailbox_poll_failed");
    }
    const payload = recordFromUnknown(await response.json());
    const messages = payload.messages;
    if (!Array.isArray(messages)) {
      throw new IngestionError("mailbox_poll_failed");
    }

    return await Promise.all(
      messages.map(async (rawMessage): Promise<MailMessage> => {
        const message = recordFromUnknown(rawMessage);
        const attachments = message.attachments;
        if (!Array.isArray(attachments)) {
          throw new IngestionError("mailbox_poll_failed");
        }
        return {
          senderAddress: String(message.sender_address ?? ""),
          messageId: String(message.message_id ?? ""),
          receivedAt: String(message.received_at ?? new Date().toISOString()),
          attachments: await Promise.all(
            attachments.map(async (rawAttachment) => {
              const attachment = recordFromUnknown(rawAttachment);
              const attachmentResponse = await fetch(
                String(attachment.download_url ?? ""),
                {
                  headers: {
                    Authorization: `Bearer ${context.credentials.accessToken}`,
                  },
                },
              );
              if (!attachmentResponse.ok || attachmentResponse.body == null) {
                throw new IngestionError("mailbox_poll_failed");
              }
              return {
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
                stream: attachmentResponse.body,
              };
            }),
          ),
        };
      }),
    );
  }
}

export class HttpMalwareScanner {
  constructor(
    private readonly scannerUrl: string,
    private readonly timeoutMs: number,
  ) {}

  async scan(
    bytes: Uint8Array,
    context: { sha256Hex: string; filename: string },
  ): Promise<"clean"> {
    if (this.scannerUrl.trim() === "") {
      throw new IngestionError("malware_scan_unavailable");
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await fetch(this.scannerUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/octet-stream",
          "X-Content-SHA256": context.sha256Hex,
          "X-File-Name": context.filename,
        },
        body: bytes,
        signal: controller.signal,
      });
      if (!response.ok) {
        throw new IngestionError("malware_scan_unavailable");
      }
      const result = await response.json();
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
    if (
      error != null && !String(error.message).toLowerCase().includes("exists")
    ) {
      throw new IngestionError("encrypted_storage_write_failed");
    }
    return { bucket: this.bucket, path };
  }

  async readOriginal(object: StoredObject): Promise<Uint8Array> {
    const { data, error } = await this.client.storage.from(object.bucket)
      .download(object.path);
    if (error != null || data == null) {
      throw new IngestionError("encrypted_storage_read_failed");
    }
    return new Uint8Array(await data.arrayBuffer());
  }
}

export class SupabasePersistence {
  constructor(private readonly client: SupabaseClient) {}

  async persist(input: PersistenceInput): Promise<PersistenceResult> {
    const { data, error } = await this.client.rpc(
      "persist_cams_kfintech_statement_ingestion",
      {
        p_workspace_id: input.workspaceId,
        p_mailbox_connection_id: input.mailboxConnectionId,
        p_correlation_id: input.correlationId,
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
      const code = error.message?.match(/([a-z][a-z0-9_]+)$/)?.[1] ??
        "persistence_failed";
      throw new IngestionError(
        knownFailureCodes.has(code)
          ? code as FailureCode
          : "persistence_failed",
      );
    }
    return (Array.isArray(data) ? data[0] : data) as PersistenceResult;
  }

  async recordFailure(input: FailureLineageInput): Promise<void> {
    await this.client.rpc("record_cams_kfintech_ingestion_failure", {
      p_workspace_id: input.workspaceId,
      p_mailbox_connection_id: input.mailboxConnectionId,
      p_correlation_id: input.correlationId,
      p_registrar: input.registrar,
      p_failure_code: input.failureCode,
      p_attachment_sha256: input.sha256Hex ?? null,
      p_storage_bucket: input.storage?.bucket ?? null,
      p_storage_object_path: input.storage?.path ?? null,
      p_detected_mime: input.detectedMime ?? null,
      p_file_type: input.fileType ?? null,
      p_size_bytes: input.sizeBytes ?? null,
    });
  }
}

export class RemotePdfTextExtractor implements PdfTextExtractor {
  constructor(private readonly extractorUrl: string) {}

  async extractText(bytes: Uint8Array, registrar: Registrar): Promise<string> {
    if (this.extractorUrl.trim() === "") {
      throw new IngestionError("unsupported_statement_format");
    }
    const response = await fetch(this.extractorUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/pdf",
        "X-Registrar": registrar,
      },
      body: bytes,
    });
    if (!response.ok) {
      throw new IngestionError("parse_failed");
    }
    const payload = await response.json();
    if (typeof payload.text !== "string") {
      throw new IngestionError("parse_failed");
    }
    return payload.text;
  }
}
