import { ParserRegistry } from "./parser.ts";
import {
  assertNoTrustedPlaintextPayload,
  assertRegistrar,
  DEFAULT_MAX_ATTACHMENT_BYTES,
  detectAndValidateFormat,
  errorStatus,
  jsonResponse,
  readBoundedStream,
  sha256Hex,
  validateSender,
  verifyInternalInvocation,
} from "./security.ts";
import {
  type EmailAttachment,
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

export type HandlerDependencies = {
  internalToken: string;
  configRepository: {
    loadRunContext(input: {
      workspaceId: string;
      mailboxConnectionId: string;
      correlationId: string;
      registrar: Registrar;
    }): Promise<IngestionRunContext>;
  };
  mailboxClient: {
    poll(context: IngestionRunContext): Promise<MailMessage[]>;
  };
  malwareScanner: {
    scan(
      bytes: Uint8Array,
      context: { sha256Hex: string; filename: string },
    ): Promise<"clean">;
  };
  storage: {
    writeOriginal(input: {
      context: IngestionRunContext;
      attachment: EmailAttachment;
      sha256Hex: string;
      bytes: Uint8Array;
      detectedMime: string;
    }): Promise<StoredObject>;
    readOriginal(object: StoredObject): Promise<Uint8Array>;
  };
  parserRegistry: ParserRegistry;
  persistence: {
    persist(input: PersistenceInput): Promise<PersistenceResult>;
    recordFailure(input: FailureLineageInput): Promise<void>;
  };
  onStage?: (stage: string) => void;
};

type RequestBody = {
  workspace_id?: unknown;
  mailbox_connection_id?: unknown;
  correlation_id?: unknown;
  registrar?: unknown;
};

function requiredString(value: unknown): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new IngestionError("not_authorized");
  }
  return value.trim();
}

function stage(deps: HandlerDependencies, name: string): void {
  deps.onStage?.(name);
}

function combineAllowlist(context: IngestionRunContext): string[] {
  return [
    ...context.mailbox.allowedSenderAddresses,
    ...context.registrarConfig.allowedSenderAddresses,
  ];
}

async function processAttachment(
  deps: HandlerDependencies,
  context: IngestionRunContext,
  message: MailMessage,
  attachment: EmailAttachment,
): Promise<PersistenceResult> {
  let sha: string | undefined;
  let storageObject: StoredObject | undefined;
  let detectedMime: string | undefined;
  let fileType: "CAS_PDF" | "DBF" | undefined;
  let sizeBytes: number | undefined;

  try {
    stage(deps, "validate_sender");
    validateSender(message.senderAddress, combineAllowlist(context));

    stage(deps, "read_attachment_stream");
    const maxBytes = Math.min(
      context.registrarConfig.maxAttachmentBytes ||
        DEFAULT_MAX_ATTACHMENT_BYTES,
      DEFAULT_MAX_ATTACHMENT_BYTES,
    );
    const bytes = await readBoundedStream(attachment.stream, maxBytes);
    sizeBytes = bytes.byteLength;

    stage(deps, "calculate_sha256");
    sha = await sha256Hex(bytes);
    if (
      attachment.expectedSha256Hex != null &&
      attachment.expectedSha256Hex !== sha
    ) {
      throw new IngestionError("attachment_hash_mismatch");
    }

    stage(deps, "validate_mime_magic");
    const format = detectAndValidateFormat(attachment.declaredMime, bytes);
    detectedMime = format.detectedMime;
    fileType = format.fileType;
    if (!context.registrarConfig.supportedFileTypes.includes(fileType)) {
      throw new IngestionError("unsupported_statement_format");
    }

    stage(deps, "malware_scan");
    await deps.malwareScanner.scan(bytes, {
      sha256Hex: sha,
      filename: attachment.filename,
    });

    stage(deps, "encrypted_storage_write");
    storageObject = await deps.storage.writeOriginal({
      context,
      attachment,
      sha256Hex: sha,
      bytes,
      detectedMime,
    });

    stage(deps, "encrypted_storage_read");
    const storedBytes = await deps.storage.readOriginal(storageObject);

    stage(deps, "parse");
    const transactions = await deps.parserRegistry.parse({
      registrar: context.mailbox.registrar,
      fileType,
      filename: attachment.filename,
      bytes: storedBytes,
    });

    stage(deps, "persist");
    const result = await deps.persistence.persist({
      workspaceId: context.workspaceId,
      mailboxConnectionId: context.mailboxConnectionId,
      correlationId: context.correlationId,
      registrar: context.mailbox.registrar,
      sha256Hex: sha,
      storage: storageObject,
      detectedMime,
      fileType,
      sizeBytes,
      receivedAt: attachment.receivedAt || message.receivedAt,
      transactions,
    });

    stage(deps, "complete_lineage");
    return result;
  } catch (error) {
    const code = error instanceof IngestionError
      ? error.code
      : "persistence_failed";
    await deps.persistence.recordFailure({
      workspaceId: context.workspaceId,
      mailboxConnectionId: context.mailboxConnectionId,
      correlationId: context.correlationId,
      registrar: context.mailbox.registrar,
      failureCode: code,
      sha256Hex: sha,
      storage: storageObject,
      detectedMime,
      fileType,
      sizeBytes,
    });
    throw error;
  }
}

function classifyUnknownError(error: unknown): FailureCode {
  return error instanceof IngestionError ? error.code : "persistence_failed";
}

export function createCamsKfintechIngestionHandler(
  deps: HandlerDependencies,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") {
      return jsonResponse({ error: { code: "not_authorized" } }, 405);
    }

    let context: IngestionRunContext | null = null;
    let pollFailureRecorded = false;
    try {
      stage(deps, "internal_authorization");
      await verifyInternalInvocation(req, deps.internalToken);

      let body: RequestBody;
      try {
        body = await req.json();
      } catch (_error) {
        throw new IngestionError("not_authorized");
      }
      assertNoTrustedPlaintextPayload(body as Record<string, unknown>);

      const registrar = assertRegistrar(body.registrar);
      const workspaceId = requiredString(body.workspace_id);
      const mailboxConnectionId = requiredString(body.mailbox_connection_id);
      const correlationId = requiredString(body.correlation_id);

      stage(deps, "load_credentials");
      context = await deps.configRepository.loadRunContext({
        workspaceId,
        mailboxConnectionId,
        correlationId,
        registrar,
      });

      stage(deps, "imap_oauth_connector");
      stage(deps, "poll_mailbox");
      const messages = await deps.mailboxClient.poll(context);
      const attachments = messages.flatMap((message) =>
        message.attachments.map((attachment) => ({ message, attachment }))
      );
      if (attachments.length === 0) {
        await deps.persistence.recordFailure({
          workspaceId: context.workspaceId,
          mailboxConnectionId: context.mailboxConnectionId,
          correlationId: context.correlationId,
          registrar: context.mailbox.registrar,
          failureCode: "mailbox_poll_failed",
        });
        pollFailureRecorded = true;
        throw new IngestionError("mailbox_poll_failed");
      }

      const results: PersistenceResult[] = [];
      for (const item of attachments) {
        results.push(
          await processAttachment(deps, context, item.message, item.attachment),
        );
      }

      return jsonResponse({
        data: {
          processed_attachments: results.length,
          results,
          correlation_id: correlationId,
        },
      });
    } catch (error) {
      const code = classifyUnknownError(error);
      if (
        context != null && code === "mailbox_poll_failed" &&
        !pollFailureRecorded
      ) {
        await deps.persistence.recordFailure({
          workspaceId: context.workspaceId,
          mailboxConnectionId: context.mailboxConnectionId,
          correlationId: context.correlationId,
          registrar: context.mailbox.registrar,
          failureCode: code,
        });
      }
      return jsonResponse({ error: { code } }, errorStatus(code));
    }
  };
}
