import { ParserRegistry } from "./parser.ts";
import {
  assertNoTrustedPlaintextPayload,
  assertRegistrar,
  DEFAULT_MAX_ATTACHMENT_BYTES,
  detectAndValidateFormat,
  deterministicUuid,
  errorStatus,
  jsonResponse,
  readBoundedStream,
  sha256Hex,
  validateSender,
  verifyInternalInvocation,
} from "./security.ts";
import {
  type DownloadedAttachment,
  type EmailAttachment,
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

export type AttachmentProcessingResult =
  | (PersistenceResult & {
    ok: true;
    message_id: string;
    attachment_id: string;
    document_correlation_id: string;
  })
  | {
    ok: false;
    message_id: string;
    attachment_id: string;
    document_correlation_id: string;
    error: { code: FailureCode; lineage_write_failed?: boolean };
  };

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
    downloadAttachment(
      context: IngestionRunContext,
      message: MailMessage,
      attachment: EmailAttachment,
    ): Promise<DownloadedAttachment>;
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
    claimRun(input: IngestionRunClaimInput): Promise<IngestionRunClaimResult>;
    finalizeRun(input: IngestionRunFinalizeInput): Promise<IngestionRunSummary>;
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

type RunByteCounter = {
  consumed: number;
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

function positiveLimit(value: number | undefined, fallback: number): number {
  if (value == null || !Number.isFinite(value) || value <= 0) {
    return fallback;
  }
  return Math.floor(value);
}

function maxAttachmentBytes(context: IngestionRunContext): number {
  return Math.min(
    positiveLimit(
      context.registrarConfig.maxAttachmentBytes,
      DEFAULT_MAX_ATTACHMENT_BYTES,
    ),
    DEFAULT_MAX_ATTACHMENT_BYTES,
  );
}

function attachmentAttemptKey(input: {
  context: IngestionRunContext;
  message: MailMessage;
  attachment: EmailAttachment;
}): string {
  return [
    input.context.workspaceId,
    input.context.mailboxConnectionId,
    input.message.messageId,
    input.attachment.attachmentId,
  ].join(":");
}

async function documentCorrelationId(input: {
  context: IngestionRunContext;
  message: MailMessage;
  attachment: EmailAttachment;
  sha?: string;
}): Promise<string> {
  return await deterministicUuid(attachmentAttemptKey(input));
}

async function recordFailure(
  deps: HandlerDependencies,
  input: FailureLineageInput,
): Promise<void> {
  await deps.persistence.recordFailure(input);
}

function isRunStopFailure(code: FailureCode): boolean {
  return code === "attachment_too_large" ||
    code === "attachment_limit_exceeded";
}

function terminalReplayResponse(summary: IngestionRunClaimResult): Response {
  return jsonResponse({
    data: {
      ingestion_run_id: summary.ingestion_run_id,
      run_status: summary.status,
      replay_state: summary.replay_state,
      processed_attachments: summary.successful_attachment_count,
      attempted_attachments: summary.attempted_attachment_count,
      successful_attachments: summary.successful_attachment_count,
      failed_attachments: summary.failed_attachment_count,
      duplicate_attachments: summary.duplicate_attachment_count,
      stopped_attachments: summary.stopped_attachment_count,
      stopped: summary.status === "stopped",
      stopped_reason: summary.stopped_reason ?? undefined,
      run_failure_code: summary.run_failure_code ?? undefined,
      continuation_policy: "terminal_replay_no_mailbox_poll",
      results: [],
    },
  });
}

async function processAttachment(
  deps: HandlerDependencies,
  context: IngestionRunContext,
  message: MailMessage,
  attachment: EmailAttachment,
  counter: RunByteCounter,
): Promise<AttachmentProcessingResult> {
  let sha: string | undefined;
  let storageObject: StoredObject | undefined;
  let detectedMime: string | undefined;
  let fileType: "CAS_PDF" | "DBF" | undefined;
  let sizeBytes: number | undefined;
  const correlationId = await documentCorrelationId({
    context,
    message,
    attachment,
  });
  const attemptKey = attachmentAttemptKey({ context, message, attachment });

  try {
    stage(deps, "validate_sender");
    validateSender(message.senderAddress, combineAllowlist(context));

    stage(deps, "retrieve_attachment");
    const downloaded = await deps.mailboxClient.downloadAttachment(
      context,
      message,
      attachment,
    );

    stage(deps, "read_attachment_stream");
    const totalBytesPerRun = positiveLimit(
      context.registrarConfig.totalBytesPerRun,
      DEFAULT_MAX_ATTACHMENT_BYTES,
    );
    const remainingBytes = totalBytesPerRun - counter.consumed;
    if (remainingBytes <= 0) {
      throw new IngestionError("attachment_too_large");
    }
    let bytes: Uint8Array;
    try {
      bytes = await readBoundedStream(
        downloaded.stream,
        Math.min(maxAttachmentBytes(context), remainingBytes),
        {
          signal: downloaded.deadlineSignal,
          abortCode: "mailbox_poll_failed",
        },
      );
    } finally {
      downloaded.cancelDeadline?.();
    }
    sizeBytes = bytes.byteLength;
    counter.consumed += sizeBytes;

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
    if (storedBytes.byteLength !== sizeBytes) {
      throw new IngestionError("stored_object_size_mismatch");
    }
    const storedSha = await sha256Hex(storedBytes);
    if (storedSha !== sha) {
      throw new IngestionError("stored_object_hash_mismatch");
    }

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
      ingestionRunId: context.correlationId,
      documentCorrelationId: correlationId,
      providerMessageId: message.messageId,
      providerAttachmentId: attachment.attachmentId,
      attachmentAttemptKey: attemptKey,
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
    return {
      ...result,
      ok: true,
      message_id: message.messageId,
      attachment_id: attachment.attachmentId,
      document_correlation_id: correlationId,
    };
  } catch (error) {
    const code = error instanceof IngestionError
      ? error.code
      : "persistence_failed";
    let lineageWriteFailed = false;
    try {
      await recordFailure(deps, {
        workspaceId: context.workspaceId,
        mailboxConnectionId: context.mailboxConnectionId,
        ingestionRunId: context.correlationId,
        documentCorrelationId: correlationId,
        providerMessageId: message.messageId,
        providerAttachmentId: attachment.attachmentId,
        attachmentAttemptKey: attemptKey,
        registrar: context.mailbox.registrar,
        failureCode: code,
        sha256Hex: sha,
        storage: storageObject,
        detectedMime,
        fileType,
        sizeBytes,
      });
    } catch (_lineageError) {
      lineageWriteFailed = true;
    }
    return {
      ok: false,
      message_id: message.messageId,
      attachment_id: attachment.attachmentId,
      document_correlation_id: correlationId,
      error: { code, lineage_write_failed: lineageWriteFailed || undefined },
    };
  }
}

function classifyUnknownError(error: unknown): FailureCode {
  return error instanceof IngestionError ? error.code : "persistence_failed";
}

function validateMessageAndAttachmentLimits(
  context: IngestionRunContext,
  messages: MailMessage[],
): void {
  const maxMessages = positiveLimit(
    context.registrarConfig.maxMessagesPerPoll,
    25,
  );
  const maxAttachmentsPerMessage = positiveLimit(
    context.registrarConfig.maxAttachmentsPerMessage,
    5,
  );
  const maxAttachmentsPerRun = positiveLimit(
    context.registrarConfig.maxAttachmentsPerRun,
    25,
  );
  if (messages.length === 0 || messages.length > maxMessages) {
    throw new IngestionError("mailbox_poll_failed");
  }

  let totalAttachments = 0;
  for (const message of messages) {
    if (message.attachments.length > maxAttachmentsPerMessage) {
      throw new IngestionError("attachment_limit_exceeded");
    }
    totalAttachments += message.attachments.length;
    if (totalAttachments > maxAttachmentsPerRun) {
      throw new IngestionError("attachment_limit_exceeded");
    }
  }

  if (totalAttachments === 0) {
    throw new IngestionError("mailbox_poll_failed");
  }
}

export function createCamsKfintechIngestionHandler(
  deps: HandlerDependencies,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") {
      return jsonResponse({ error: { code: "not_authorized" } }, 405);
    }

    let context: IngestionRunContext | null = null;
    let runIdentity: IngestionRunClaimInput | null = null;
    let claimSucceeded = false;
    let finalizationWriteFailed = false;
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

      runIdentity = {
        workspaceId,
        mailboxConnectionId,
        ingestionRunId: correlationId,
        registrar,
      };

      stage(deps, "claim_ingestion_run");
      const claim = await deps.persistence.claimRun(runIdentity);
      claimSucceeded = true;
      if (claim.replay_state === "terminal_replay") {
        return terminalReplayResponse(claim);
      }

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
      validateMessageAndAttachmentLimits(context, messages);

      const results: AttachmentProcessingResult[] = [];
      const counter: RunByteCounter = { consumed: 0 };
      let halted = false;
      let stoppedReason: FailureCode | undefined;
      for (const message of messages) {
        if (halted) break;
        for (const attachment of message.attachments) {
          if (halted) break;
          const result = await processAttachment(
            deps,
            context,
            message,
            attachment,
            counter,
          );
          results.push(result);
          if (!result.ok) {
            if (isRunStopFailure(result.error.code)) {
              halted = true;
              stoppedReason = result.error.code;
            } else if (result.error.code === "mailbox_poll_failed") {
              halted = true;
            }
          }
        }
      }

      stage(deps, "finalize_ingestion_run");
      const finalSummary = await deps.persistence.finalizeRun({
        workspaceId: context.workspaceId,
        mailboxConnectionId: context.mailboxConnectionId,
        ingestionRunId: context.correlationId,
        registrar: context.mailbox.registrar,
        stoppedReason,
      });

      return jsonResponse({
        data: {
          ingestion_run_id: correlationId,
          run_status: finalSummary.status,
          processed_attachments: results.filter((result) => result.ok).length,
          attempted_attachments: results.length,
          successful_attachments: finalSummary.successful_attachment_count,
          failed_attachments: finalSummary.failed_attachment_count,
          duplicate_attachments: finalSummary.duplicate_attachment_count,
          stopped_attachments: finalSummary.stopped_attachment_count,
          stopped: stoppedReason != null,
          stopped_reason: finalSummary.stopped_reason ?? stoppedReason,
          run_failure_code: finalSummary.run_failure_code ?? undefined,
          continuation_policy: "continue_after_attachment_failure",
          results,
        },
      });
    } catch (error) {
      const code = classifyUnknownError(error);
      if (runIdentity != null && claimSucceeded) {
        try {
          stage(deps, "finalize_ingestion_run");
          await deps.persistence.finalizeRun({
            ...runIdentity,
            stoppedReason: isRunStopFailure(code) ? code : undefined,
            failureCode: isRunStopFailure(code) ? undefined : code,
          });
        } catch (_finalizeError) {
          finalizationWriteFailed = true;
        }
      }
      return jsonResponse({
        error: {
          code,
          finalization_write_failed: finalizationWriteFailed || undefined,
        },
      }, errorStatus(code));
    }
  };
}
