import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { CamsParser, KfintechParser, ParserRegistry } from "./parser.ts";
import {
  createCamsKfintechIngestionHandler,
  type HandlerDependencies,
} from "./handler.ts";
import {
  camsDbfFixture,
  chunkedStream,
  correlationId,
  mailboxConnectionId,
  streamFromBytes,
  workspaceId,
} from "./fixtures.ts";
import { readBoundedStream, sha256Hex } from "./security.ts";
import {
  IngestionError,
  type MailMessage,
  type PersistenceInput,
  type PersistenceResult,
  type RegistrarConfig,
} from "./types.ts";

const internalToken = "internal-ingestion-token";
const userToken = "workspace-advisor-token";
let fixtureCounter = 0;
const attachmentFixtureBytes = new Map<string, Uint8Array>();

function request(
  body: Record<string, unknown>,
  token = internalToken,
  authenticatedUserToken: string | null = userToken,
): Request {
  const headers: Record<string, string> = {
    authorization: `Bearer ${token}`,
    "content-type": "application/json",
  };
  if (authenticatedUserToken != null) {
    headers["x-user-authorization"] = `Bearer ${authenticatedUserToken}`;
  }
  return new Request("http://localhost/cams-kfintech-ingestion", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function validBody(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    workspace_id: workspaceId,
    mailbox_connection_id: mailboxConnectionId,
    correlation_id: correlationId,
    registrar: "CAMS",
    ...overrides,
  };
}

function message(
  bytes = camsDbfFixture(),
  overrides: Partial<MailMessage> = {},
): MailMessage {
  fixtureCounter += 1;
  const messageId = overrides.messageId ?? `message-${fixtureCounter}`;
  const attachmentId = `attachment-${fixtureCounter}`;
  attachmentFixtureBytes.set(`${messageId}:${attachmentId}`, bytes);
  return {
    senderAddress: "reports@camsonline.com",
    messageId,
    receivedAt: "2026-07-29T00:00:00Z",
    attachments: [{
      attachmentId,
      filename: "cams.dbf",
      declaredMime: "application/x-dbase",
      receivedAt: "2026-07-29T00:00:00Z",
    }],
    ...overrides,
  };
}

function attachmentFixture(
  bytes: Uint8Array,
  messageId: string,
  attachmentId: string,
  overrides: Partial<MailMessage["attachments"][number]> = {},
): MailMessage["attachments"][number] {
  attachmentFixtureBytes.set(`${messageId}:${attachmentId}`, bytes);
  return {
    attachmentId,
    filename: "cams.dbf",
    declaredMime: "application/x-dbase",
    receivedAt: "2026-07-29T00:00:00Z",
    ...overrides,
  };
}

function deps(options: {
  stages?: string[];
  messages?: MailMessage[];
  scan?: (bytes: Uint8Array) => Promise<"clean">;
  storageReadBytes?: Uint8Array;
  persist?: (input: PersistenceInput) => Promise<PersistenceResult>;
  failContext?: IngestionError;
  failureCodes?: string[];
  claimedRuns?: string[];
  finalizedRuns?: {
    runId: string;
    stoppedReason?: string;
    failureCode?: string;
    observedAttachmentCount?: number;
  }[];
  downloadCount?: { count: number };
  registrarConfig?: Partial<RegistrarConfig>;
  claimRun?: HandlerDependencies["persistence"]["claimRun"];
  finalizeRun?: HandlerDependencies["persistence"]["finalizeRun"];
  finalizeNoDataRun?: HandlerDependencies["persistence"]["finalizeNoDataRun"];
  recordFailure?: HandlerDependencies["persistence"]["recordFailure"];
  authorize?: HandlerDependencies["workspaceAuthorizer"]["authorize"];
  poll?: HandlerDependencies["mailboxClient"]["poll"];
} = {}): HandlerDependencies {
  const stages = options.stages ?? [];
  const failureCodes = options.failureCodes ?? [];
  const claimedRuns = options.claimedRuns ?? [];
  const finalizedRuns = options.finalizedRuns ?? [];
  let storedBytes: Uint8Array | null = null;

  return {
    internalToken,
    onStage: (stage) => stages.push(stage),
    workspaceAuthorizer: {
      authorize: options.authorize ?? ((req, input) => {
        if (req.headers.get("x-user-authorization") !== `Bearer ${userToken}`) {
          return Promise.reject(new IngestionError("authorization_required"));
        }
        if (input.workspaceId !== workspaceId) {
          return Promise.reject(new IngestionError("not_authorized"));
        }
        return Promise.resolve();
      }),
    },
    configRepository: {
      loadRunContext: (input) => {
        if (options.failContext != null) {
          return Promise.reject(options.failContext);
        }
        return Promise.resolve({
          workspaceId: input.workspaceId,
          mailboxConnectionId: input.mailboxConnectionId,
          correlationId: input.correlationId,
          mailbox: {
            id: input.mailboxConnectionId,
            workspaceId: input.workspaceId,
            registrar: input.registrar,
            connectorRef: "mailbox-ref",
            mailboxAddress: "advisor@example.test",
            allowedSenderAddresses: ["reports@camsonline.com"],
            maxAttachmentBytes: 1024 * 1024,
          },
          credentials: {
            accessToken: "oauth-access-token",
            refreshToken: "oauth-refresh-token",
          },
          registrarConfig: {
            registrar: input.registrar,
            allowedSenderAddresses: ["statements@kfintech.com"],
            maxAttachmentBytes: 1024 * 1024,
            maxMessagesPerPoll: 25,
            maxAttachmentsPerMessage: 5,
            maxAttachmentsPerRun: 25,
            totalBytesPerRun: 1024 * 1024,
            supportedFileTypes: ["CAS_PDF", "DBF"],
            ...options.registrarConfig,
          },
        });
      },
    },
    mailboxClient: {
      poll: options.poll ??
        (() => Promise.resolve(options.messages ?? [message()])),
      downloadAttachment: (_context, message, attachment) => {
        if (options.downloadCount != null) {
          options.downloadCount.count += 1;
        }
        const bytes = attachmentFixtureBytes.get(
          `${message.messageId}:${attachment.attachmentId}`,
        ) ?? camsDbfFixture();
        return Promise.resolve({
          ...attachment,
          stream: streamFromBytes(bytes),
        });
      },
    },
    malwareScanner: {
      scan: options.scan ?? (() => Promise.resolve("clean")),
    },
    storage: {
      writeOriginal: (input) => {
        storedBytes = input.bytes;
        return Promise.resolve({
          bucket: "ingested-documents",
          path: `${input.sha256Hex}.dbf`,
        });
      },
      readOriginal: () =>
        Promise.resolve(
          options.storageReadBytes ?? storedBytes ?? camsDbfFixture(),
        ),
    },
    parserRegistry: new ParserRegistry([
      new CamsParser(),
      new KfintechParser(),
    ]),
    persistence: {
      claimRun: options.claimRun ?? ((input) => {
        claimedRuns.push(input.ingestionRunId);
        return Promise.resolve({
          ingestion_run_id: input.ingestionRunId,
          status: "claimed",
          replay_state: "newly_claimed",
          attempted_attachment_count: 0,
          successful_attachment_count: 0,
          failed_attachment_count: 0,
          duplicate_attachment_count: 0,
          stopped_attachment_count: 0,
          observed_attachment_count: 0,
          durable_attempt_count: 0,
          lineage_gap_count: 0,
          stopped_reason: null,
          run_failure_code: null,
        });
      }),
      finalizeRun: options.finalizeRun ?? ((input) => {
        finalizedRuns.push({
          runId: input.ingestionRunId,
          stoppedReason: input.stoppedReason,
          failureCode: input.failureCode,
          observedAttachmentCount: input.observedAttachmentCount,
        });
        return Promise.resolve({
          ingestion_run_id: input.ingestionRunId,
          status: input.stoppedReason != null
            ? "stopped"
            : input.failureCode != null
            ? "failed"
            : "completed",
          attempted_attachment_count: 0,
          successful_attachment_count: 0,
          failed_attachment_count: input.failureCode != null ? 1 : 0,
          duplicate_attachment_count: 0,
          stopped_attachment_count: input.stoppedReason != null ? 1 : 0,
          observed_attachment_count: input.observedAttachmentCount ?? 0,
          durable_attempt_count: input.failureCode != null ? 1 : 0,
          lineage_gap_count: input.failureCode === "attempt_lineage_incomplete"
            ? 1
            : 0,
          stopped_reason: input.stoppedReason ?? null,
          run_failure_code: input.failureCode ?? null,
        });
      }),
      finalizeNoDataRun: options.finalizeNoDataRun ??
        ((input) =>
          Promise.resolve({
            ingestion_run_id: input.ingestionRunId,
            status: "completed",
            attempted_attachment_count: 0,
            successful_attachment_count: 0,
            failed_attachment_count: 0,
            duplicate_attachment_count: 0,
            stopped_attachment_count: 0,
            observed_attachment_count: 0,
            durable_attempt_count: 0,
            lineage_gap_count: 0,
            stopped_reason: null,
            run_failure_code: null,
          })),
      persist: options.persist ??
        (() =>
          Promise.resolve({
            document_id: "document-id",
            ingestion_log_id: "log-id",
            outbox_event_id: "event-id",
            transaction_count: 1,
            idempotent: false,
          })),
      recordFailure: options.recordFailure ?? ((input) => {
        failureCodes.push(input.failureCode);
        return Promise.resolve();
      }),
    },
  };
}

Deno.test("missing Authorization header is denied", async () => {
  const handler = createCamsKfintechIngestionHandler(deps());
  const response = await handler(
    new Request("http://localhost", {
      method: "POST",
      body: JSON.stringify(validBody()),
    }),
  );
  const body = await response.json();

  assertEquals(response.status, 401);
  assertEquals(body.error.code, "authorization_required");
});

Deno.test("invalid internal credential and normal user bearer are denied", async () => {
  const handler = createCamsKfintechIngestionHandler(deps());

  const invalid = await handler(request(validBody(), "bad-token"));
  const user = await handler(
    request(validBody(), "normal-authenticated-user-token"),
  );

  assertEquals(invalid.status, 403);
  assertEquals((await invalid.json()).error.code, "not_authorized");
  assertEquals(user.status, 403);
  assertEquals((await user.json()).error.code, "not_authorized");
});

Deno.test("trusted internal invocation is allowed", async () => {
  const handler = createCamsKfintechIngestionHandler(deps());
  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.processed_attachments, 1);
});

Deno.test("CAMS no-data mailback completes without download scan storage or parse", async () => {
  const stages: string[] = [];
  const downloadCount = { count: 0 };
  let noDataFinalizations = 0;
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    downloadCount,
    messages: [{
      senderAddress: "reports@camsonline.com",
      messageId: "no-data-message",
      receivedAt: "2026-08-25T00:00:00Z",
      attachments: [],
      outcome: "no_data",
    }],
    finalizeNoDataRun: (input) => {
      noDataFinalizations += 1;
      return Promise.resolve({
        ingestion_run_id: input.ingestionRunId,
        status: "completed",
        attempted_attachment_count: 0,
        successful_attachment_count: 0,
        failed_attachment_count: 0,
        duplicate_attachment_count: 0,
        stopped_attachment_count: 0,
        observed_attachment_count: 0,
        durable_attempt_count: 0,
        lineage_gap_count: 0,
        stopped_reason: null,
        run_failure_code: null,
      });
    },
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.mailbox_outcome, "no_data");
  assertEquals(body.data.run_status, "completed");
  assertEquals(body.data.attempted_attachments, 0);
  assertEquals(body.data.continuation_policy, "legitimate_no_data");
  assertEquals(noDataFinalizations, 1);
  assertEquals(downloadCount.count, 0);
  assertEquals(stages.includes("malware_scan"), false);
  assertEquals(stages.includes("encrypted_storage_write"), false);
  assertEquals(stages.includes("parse"), false);
});

Deno.test("unsupported CAMS report records sanitized failure without DBF parsing", async () => {
  const stages: string[] = [];
  const failureCodes: string[] = [];
  const downloadCount = { count: 0 };
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    failureCodes,
    downloadCount,
    messages: [{
      senderAddress: "reports@camsonline.com",
      messageId: "unsupported-report-message",
      receivedAt: "2026-08-25T00:00:00Z",
      attachments: [],
      outcome: "unsupported_report",
    }],
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.results[0].error.code, "unsupported_report");
  assertEquals(body.data.mailbox_outcomes, ["unsupported_report"]);
  assertEquals(failureCodes, ["unsupported_report"]);
  assertEquals(downloadCount.count, 0);
  assertEquals(stages.includes("parse"), false);
});

Deno.test("latest supported reports smoke mode is explicitly validated and propagated", async () => {
  let observedSmokeMode: string | undefined;
  const handler = createCamsKfintechIngestionHandler(deps({
    poll: (_context, smokeMode) => {
      observedSmokeMode = smokeMode;
      return Promise.resolve([]);
    },
  }));

  const response = await handler(request(validBody({
    smoke_mode: "latest_supported_reports",
  })));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(observedSmokeMode, "latest_supported_reports");
  assertEquals(body.data.mailbox_outcome, "no_data");
  assertEquals(body.data.attempted_attachments, 0);
});

Deno.test("invalid or non-CAMS smoke modes fail closed before run claim", async () => {
  for (
    const invalidBody of [
      validBody({ smoke_mode: "all_messages" }),
      validBody({
        registrar: "KFINTECH",
        smoke_mode: "latest_supported_reports",
      }),
    ]
  ) {
    const claimedRuns: string[] = [];
    const handler = createCamsKfintechIngestionHandler(deps({ claimedRuns }));
    const response = await handler(request(invalidBody));
    const body = await response.json();

    assertEquals(response.status, 403);
    assertEquals(body.error.code, "not_authorized");
    assertEquals(claimedRuns, []);
  }
});

Deno.test("smoke-mode no-data sender still crosses the post-read allowlist boundary", async () => {
  const failureCodes: string[] = [];
  let noDataFinalizations = 0;
  const handler = createCamsKfintechIngestionHandler(deps({
    failureCodes,
    messages: [{
      senderAddress: "attacker@example.test",
      messageId: "forged-no-data-message",
      receivedAt: "2026-08-25T00:00:00Z",
      attachments: [],
      outcome: "no_data",
    }],
    finalizeNoDataRun: () => {
      noDataFinalizations += 1;
      throw new Error("must not finalize forged no-data");
    },
  }));

  const response = await handler(request(validBody({
    smoke_mode: "latest_supported_reports",
  })));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.results[0].error.code, "sender_not_allowed");
  assertEquals(failureCodes, ["sender_not_allowed"]);
  assertEquals(noDataFinalizations, 0);
});

Deno.test("workspace authorization requires authenticated advisor context", async () => {
  const claimedRuns: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({ claimedRuns }));
  const response = await handler(request(validBody(), internalToken, null));
  const body = await response.json();

  assertEquals(response.status, 401);
  assertEquals(body.error.code, "authorization_required");
  assertEquals(claimedRuns, []);
});

Deno.test("cross-workspace ingestion is denied before run claim", async () => {
  const claimedRuns: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({ claimedRuns }));
  const response = await handler(request(validBody({
    workspace_id: "93400000-0000-0000-0000-000000000099",
  })));
  const body = await response.json();

  assertEquals(response.status, 403);
  assertEquals(body.error.code, "not_authorized");
  assertEquals(claimedRuns, []);
});

Deno.test("inactive workspace ingestion is denied before run claim", async () => {
  const claimedRuns: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    claimedRuns,
    authorize: () => Promise.reject(new IngestionError("not_authorized")),
  }));
  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 403);
  assertEquals(body.error.code, "not_authorized");
  assertEquals(claimedRuns, []);
});

Deno.test("non-advisor workspace members cannot start ingestion", async () => {
  const claimedRuns: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    claimedRuns,
    authorize: () => Promise.reject(new IngestionError("not_authorized")),
  }));
  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 403);
  assertEquals(body.error.code, "not_authorized");
  assertEquals(claimedRuns, []);
});

Deno.test("request payload cannot carry trusted plaintext secrets", async () => {
  const handler = createCamsKfintechIngestionHandler(deps());
  const response = await handler(
    request(validBody({ oauth_access_token: "do-not-accept" })),
  );
  const body = await response.json();

  assertEquals(response.status, 403);
  assertEquals(body.error.code, "not_authorized");
});

Deno.test("pipeline stages execute in the required order", async () => {
  const stages: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({ stages }));
  const response = await handler(request(validBody()));

  assertEquals(response.status, 200);
  assertEquals(stages, [
    "internal_authorization",
    "workspace_authorization",
    "claim_ingestion_run",
    "load_credentials",
    "imap_oauth_connector",
    "poll_mailbox",
    "validate_sender",
    "retrieve_attachment",
    "read_attachment_stream",
    "calculate_sha256",
    "validate_mime_magic",
    "malware_scan",
    "encrypted_storage_write",
    "encrypted_storage_read",
    "parse",
    "persist",
    "complete_lineage",
    "finalize_ingestion_run",
  ]);
});

Deno.test("terminal run replay returns immutable summary without mailbox polling", async () => {
  const stages: string[] = [];
  const downloadCount = { count: 0 };
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    downloadCount,
    failContext: new IngestionError("oauth_credentials_unavailable"),
    claimRun: (input) =>
      Promise.resolve({
        ingestion_run_id: input.ingestionRunId,
        status: "completed",
        replay_state: "terminal_replay",
        attempted_attachment_count: 2,
        successful_attachment_count: 1,
        failed_attachment_count: 0,
        duplicate_attachment_count: 1,
        stopped_attachment_count: 0,
        observed_attachment_count: 2,
        durable_attempt_count: 2,
        lineage_gap_count: 0,
        stopped_reason: null,
        run_failure_code: null,
      }),
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.replay_state, "terminal_replay");
  assertEquals(body.data.attempted_attachments, 2);
  assertEquals(body.data.duplicate_attachments, 1);
  assertEquals(downloadCount.count, 0);
  assertEquals(stages, [
    "internal_authorization",
    "workspace_authorization",
    "claim_ingestion_run",
  ]);
});

Deno.test("active run replay returns in-progress without execution side effects", async () => {
  const stages: string[] = [];
  const downloadCount = { count: 0 };
  let persistCount = 0;
  const finalizedRuns: {
    runId: string;
    stoppedReason?: string;
    failureCode?: string;
    observedAttachmentCount?: number;
  }[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    downloadCount,
    finalizedRuns,
    failContext: new IngestionError("oauth_credentials_unavailable"),
    persist: () => {
      persistCount += 1;
      return Promise.reject(new IngestionError("persistence_failed"));
    },
    claimRun: (input) =>
      Promise.resolve({
        ingestion_run_id: input.ingestionRunId,
        status: "claimed",
        replay_state: "active_in_progress",
        attempted_attachment_count: 1,
        successful_attachment_count: 0,
        failed_attachment_count: 0,
        duplicate_attachment_count: 0,
        stopped_attachment_count: 0,
        observed_attachment_count: 1,
        durable_attempt_count: 1,
        lineage_gap_count: 0,
        stopped_reason: null,
        run_failure_code: null,
      }),
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 202);
  assertEquals(body.data.replay_state, "active_in_progress");
  assertEquals(body.data.code, "ingestion_run_in_progress");
  assertEquals(
    body.data.continuation_policy,
    "active_run_in_progress_no_mailbox_poll",
  );
  assertEquals(downloadCount.count, 0);
  assertEquals(persistCount, 0);
  assertEquals(finalizedRuns, []);
  assertEquals(stages, [
    "internal_authorization",
    "workspace_authorization",
    "claim_ingestion_run",
  ]);
});

Deno.test("sender validation precedes scan storage and parse", async () => {
  const stages: string[] = [];
  const failureCodes: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    failureCodes,
    messages: [
      message(camsDbfFixture(), { senderAddress: "attacker@example.test" }),
    ],
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.results[0].error.code, "sender_not_allowed");
  assertEquals(stages.includes("retrieve_attachment"), false);
  assertEquals(stages.includes("malware_scan"), false);
  assertEquals(stages.includes("encrypted_storage_write"), false);
  assertEquals(stages.includes("parse"), false);
  assertEquals(failureCodes, ["sender_not_allowed"]);
});

Deno.test("digest and MIME magic validation precede malware scan", async () => {
  const stages: string[] = [];
  const badAttachment = message(camsDbfFixture());
  badAttachment.attachments[0].expectedSha256Hex = "0".repeat(64);
  const handler = createCamsKfintechIngestionHandler(
    deps({ stages, messages: [badAttachment] }),
  );

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.results[0].error.code, "attachment_hash_mismatch");
  assertEquals(stages.includes("malware_scan"), false);
});

Deno.test("MIME and magic mismatch is rejected", async () => {
  const messageId = "mime-message";
  const attachmentId = "mime-attachment";
  const handler = createCamsKfintechIngestionHandler(deps({
    messages: [message(camsDbfFixture(), {
      messageId,
      attachments: [{
        ...attachmentFixture(camsDbfFixture(), messageId, attachmentId),
        filename: "cams.pdf",
        declaredMime: "application/pdf",
      }],
    })],
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.data.results[0].error.code, "magic_byte_mismatch");
});

Deno.test("application/octet-stream is accepted only for valid DBF magic bytes", async () => {
  const messageId = "octet-message";
  const attachmentId = "octet-attachment";
  const handler = createCamsKfintechIngestionHandler(deps({
    messages: [message(camsDbfFixture(), {
      messageId,
      attachments: [{
        ...attachmentFixture(camsDbfFixture(), messageId, attachmentId),
        filename: "cams.dbf",
        declaredMime: "application/octet-stream",
      }],
    })],
  }));

  const response = await handler(request(validBody()));
  assertEquals(response.status, 200);
});

Deno.test("unsupported file format is rejected", async () => {
  const handler = createCamsKfintechIngestionHandler(deps({
    messages: [message(new TextEncoder().encode("not a statement"))],
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.data.results[0].error.code, "unsupported_media_type");
});

Deno.test("malware scan result controls progression", async () => {
  const infected = createCamsKfintechIngestionHandler(deps({
    scan: () => Promise.reject(new IngestionError("malware_detected")),
  }));
  const unavailable = createCamsKfintechIngestionHandler(deps({
    scan: () => Promise.reject(new IngestionError("malware_scan_unavailable")),
  }));
  const invalid = createCamsKfintechIngestionHandler(deps({
    scan: () => Promise.reject(new IngestionError("malware_scan_unavailable")),
  }));

  const infectedResponse = await infected(request(validBody()));
  const unavailableResponse = await unavailable(request(validBody()));
  const invalidResponse = await invalid(request(validBody()));
  assertEquals(
    (await infectedResponse.json()).data.results[0].error.code,
    "malware_detected",
  );
  assertEquals(
    (await unavailableResponse.json()).data.results[0].error.code,
    "malware_scan_unavailable",
  );
  assertEquals(
    (await invalidResponse.json()).data.results[0].error.code,
    "malware_scan_unavailable",
  );
});

Deno.test("storage precedes parsing and parsing failure prevents persistence", async () => {
  const stages: string[] = [];
  let persisted = false;
  const badBytes = camsDbfFixture({ AMOUNT: "bad-value" });
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    messages: [message(badBytes)],
    persist: () => {
      persisted = true;
      return Promise.resolve({
        document_id: "unexpected-document",
        ingestion_log_id: null,
        outbox_event_id: null,
        transaction_count: 0,
        idempotent: false,
      });
    },
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(body.data.results[0].error.code, "parse_failed");
  assertEquals(
    stages.indexOf("encrypted_storage_read") < stages.indexOf("parse"),
    true,
  );
  assertEquals(persisted, false);
});

Deno.test("stored object hash mismatch prevents parser invocation", async () => {
  const stages: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    storageReadBytes: camsDbfFixture({ FOLIO_NO: "DIFFERENT" }),
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(body.data.results[0].error.code, "stored_object_hash_mismatch");
  assertEquals(stages.includes("parse"), false);
});

Deno.test("stored object size mismatch prevents parser invocation", async () => {
  const stages: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    storageReadBytes: camsDbfFixture().slice(0, 64),
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(body.data.results[0].error.code, "stored_object_size_mismatch");
  assertEquals(stages.includes("parse"), false);
});

Deno.test("completion event occurs only after persistence", async () => {
  const stages: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    persist: () => Promise.reject(new IngestionError("persistence_failed")),
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.data.results[0].error.code, "persistence_failed");
  assertEquals(stages.includes("complete_lineage"), false);
});

Deno.test("valid attachment remains in memory and no raw bytes are logged", async () => {
  const logs: unknown[][] = [];
  const originalLog = console.log;
  const originalError = console.error;
  console.log = (...args: unknown[]) => logs.push(args);
  console.error = (...args: unknown[]) => logs.push(args);
  try {
    const handler = createCamsKfintechIngestionHandler(deps());
    const response = await handler(request(validBody()));
    assertEquals(response.status, 200);
    assertEquals(JSON.stringify(logs).includes("ABCDE1234F"), false);
    assertEquals(JSON.stringify(logs).includes("FOLIO1001"), false);
  } finally {
    console.log = originalLog;
    console.error = originalError;
  }
});

Deno.test("oversized stream is aborted before complete buffering", async () => {
  let pulls = 0;
  await assertRejects(
    () =>
      readBoundedStream(chunkedStream(10, 10, (count) => pulls = count), 25),
    Error,
    "attachment_too_large",
  );
  assertEquals(pulls < 10, true);
});

Deno.test("empty and truncated files fail closed", async () => {
  const empty = createCamsKfintechIngestionHandler(deps({
    messages: [message(new Uint8Array())],
  }));
  const truncated = createCamsKfintechIngestionHandler(deps({
    messages: [message(new Uint8Array([0x03, 0x01]))],
  }));

  const emptyResponse = await empty(request(validBody()));
  const truncatedResponse = await truncated(request(validBody()));
  assertEquals(
    (await emptyResponse.json()).data.results[0].error.code,
    "unsupported_statement_format",
  );
  assertEquals(
    (await truncatedResponse.json()).data.results[0].error.code,
    "unsupported_media_type",
  );
});

Deno.test("credentials are loaded by trusted identifier and missing credentials fail closed", async () => {
  const stages: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    failContext: new IngestionError("oauth_credentials_unavailable"),
  }));
  const response = await handler(request(validBody()));

  assertEquals(response.status, 422);
  assertEquals(
    (await response.json()).error.code,
    "oauth_credentials_unavailable",
  );
  assertEquals(stages, [
    "internal_authorization",
    "workspace_authorization",
    "claim_ingestion_run",
    "load_credentials",
    "finalize_ingestion_run",
  ]);
});

Deno.test("run is claimed before polling and finalized after poll failure", async () => {
  const stages: string[] = [];
  const failureCodes: string[] = [];
  const claimedRuns: string[] = [];
  const finalizedRuns: {
    runId: string;
    stoppedReason?: string;
    failureCode?: string;
    observedAttachmentCount?: number;
  }[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    failureCodes,
    claimedRuns,
    finalizedRuns,
    messages: [],
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 422);
  assertEquals(body.error.code, "mailbox_poll_failed");
  assertEquals(stages.slice(0, 5), [
    "internal_authorization",
    "workspace_authorization",
    "claim_ingestion_run",
    "load_credentials",
    "imap_oauth_connector",
  ]);
  assertEquals(claimedRuns, [correlationId]);
  assertEquals(failureCodes, []);
  assertEquals(finalizedRuns, [{
    runId: correlationId,
    stoppedReason: undefined,
    failureCode: "mailbox_poll_failed",
    observedAttachmentCount: 0,
  }]);
});

Deno.test("OAuth values never appear in response logs or errors", async () => {
  const logs: unknown[][] = [];
  const originalWarn = console.warn;
  console.warn = (...args: unknown[]) => logs.push(args);
  try {
    const handler = createCamsKfintechIngestionHandler(deps({
      failContext: new IngestionError("oauth_credentials_unavailable"),
    }));
    const response = await handler(request(validBody()));
    const text = await response.text();

    assertEquals(text.includes("oauth-access-token"), false);
    assertEquals(text.includes("oauth-refresh-token"), false);
    assertEquals(JSON.stringify(logs).includes("oauth-access-token"), false);
  } finally {
    console.warn = originalWarn;
  }
});

Deno.test("identical attachment retry returns idempotent persistence result", async () => {
  const handler = createCamsKfintechIngestionHandler(deps({
    persist: () =>
      Promise.resolve({
        document_id: "document-id",
        ingestion_log_id: "log-id",
        outbox_event_id: "event-id",
        transaction_count: 1,
        idempotent: true,
      }),
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();
  assertEquals(body.data.results[0].idempotent, true);
});

Deno.test("conflicting digest correlation binding is rejected", async () => {
  const handler = createCamsKfintechIngestionHandler(deps({
    persist: () => Promise.reject(new IngestionError("duplicate_attachment")),
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.data.results[0].error.code, "duplicate_attachment");
});

Deno.test("concurrent identical ingestion resolves idempotently", async () => {
  const handler = createCamsKfintechIngestionHandler(deps({
    persist: () =>
      Promise.resolve({
        document_id: "same-document",
        ingestion_log_id: "same-log",
        outbox_event_id: "same-event",
        transaction_count: 1,
        idempotent: true,
      }),
  }));

  const [first, second] = await Promise.all([
    handler(request(validBody())),
    handler(request(validBody())),
  ]);

  assertEquals(first.status, 200);
  assertEquals(second.status, 200);
  assertEquals(
    (await first.json()).data.results[0].outbox_event_id,
    "same-event",
  );
  assertEquals(
    (await second.json()).data.results[0].outbox_event_id,
    "same-event",
  );
});

Deno.test("validation malware and parsing failures record stable lineage", async () => {
  const senderFailures: string[] = [];
  const malwareFailures: string[] = [];
  const parseFailures: string[] = [];

  await createCamsKfintechIngestionHandler(deps({
    failureCodes: senderFailures,
    messages: [
      message(camsDbfFixture(), { senderAddress: "bad@example.test" }),
    ],
  }))(request(validBody()));

  await createCamsKfintechIngestionHandler(deps({
    failureCodes: malwareFailures,
    scan: () => Promise.reject(new IngestionError("malware_detected")),
  }))(request(validBody()));

  await createCamsKfintechIngestionHandler(deps({
    failureCodes: parseFailures,
    messages: [message(camsDbfFixture({ TRX_DATE: "bad-date" }))],
  }))(request(validBody()));

  assertEquals(senderFailures, ["sender_not_allowed"]);
  assertEquals(malwareFailures, ["malware_detected"]);
  assertEquals(parseFailures, ["parse_failed"]);
});

Deno.test("two valid attachments in one run both persist with separate document correlations", async () => {
  const messageId = "multi-message";
  const first = attachmentFixture(camsDbfFixture(), messageId, "attachment-a");
  const second = attachmentFixture(
    camsDbfFixture({ FOLIO_NO: "FOLIO2002", AMOUNT: "300.00" }),
    messageId,
    "attachment-b",
  );
  const documentCorrelations: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    messages: [message(camsDbfFixture(), {
      messageId,
      attachments: [first, second],
    })],
    persist: (input) => {
      documentCorrelations.push(input.documentCorrelationId);
      return Promise.resolve({
        document_id: `document-${documentCorrelations.length}`,
        ingestion_log_id: `log-${documentCorrelations.length}`,
        outbox_event_id: `event-${documentCorrelations.length}`,
        transaction_count: input.transactions.length,
        idempotent: false,
      });
    },
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.attempted_attachments, 2);
  assertEquals(body.data.processed_attachments, 2);
  assertEquals(documentCorrelations.length, 2);
  assertEquals(documentCorrelations[0] === documentCorrelations[1], false);
});

Deno.test("retrying a run reports per-attachment idempotent results without duplicate persistence side effects", async () => {
  const handler = createCamsKfintechIngestionHandler(deps({
    persist: () =>
      Promise.resolve({
        document_id: "document-id",
        ingestion_log_id: "log-id",
        outbox_event_id: "event-id",
        transaction_count: 1,
        idempotent: true,
      }),
  }));

  const first = await handler(request(validBody()));
  const second = await handler(request(validBody()));

  assertEquals((await first.json()).data.results[0].idempotent, true);
  assertEquals((await second.json()).data.results[0].idempotent, true);
});

Deno.test("attachment-count limit stops before any attachment retrieval", async () => {
  const downloadCount = { count: 0 };
  const messageId = "limit-message";
  const handler = createCamsKfintechIngestionHandler(deps({
    downloadCount,
    registrarConfig: { maxAttachmentsPerRun: 1 },
    messages: [message(camsDbfFixture(), {
      messageId,
      attachments: [
        attachmentFixture(camsDbfFixture(), messageId, "limit-a"),
        attachmentFixture(camsDbfFixture(), messageId, "limit-b"),
      ],
    })],
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 422);
  assertEquals(body.error.code, "attachment_limit_exceeded");
  assertEquals(downloadCount.count, 0);
});

Deno.test("oversized attachment stops further fetching", async () => {
  const downloadCount = { count: 0 };
  const messageId = "oversize-message";
  const handler = createCamsKfintechIngestionHandler(deps({
    downloadCount,
    registrarConfig: { maxAttachmentBytes: 8 },
    messages: [message(camsDbfFixture(), {
      messageId,
      attachments: [
        attachmentFixture(camsDbfFixture(), messageId, "oversize-a"),
        attachmentFixture(camsDbfFixture(), messageId, "oversize-b"),
      ],
    })],
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.results[0].error.code, "attachment_too_large");
  assertEquals(downloadCount.count, 1);
  assertEquals(body.data.stopped, true);
  assertEquals(body.data.stopped_reason, "attachment_too_large");
});

Deno.test("attachment download timeout stops later retrieval", async () => {
  const downloadCount = { count: 0 };
  const messageId = "timeout-message";
  const controller = new AbortController();
  const customDeps = deps({
    downloadCount,
    messages: [message(camsDbfFixture(), {
      messageId,
      attachments: [
        attachmentFixture(camsDbfFixture(), messageId, "timeout-a"),
        attachmentFixture(camsDbfFixture(), messageId, "timeout-b"),
      ],
    })],
  });
  customDeps.mailboxClient.downloadAttachment = (
    _context,
    _message,
    attachment,
  ) => {
    downloadCount.count += 1;
    const stream = new ReadableStream<Uint8Array>();
    setTimeout(() => controller.abort(), 0);
    return Promise.resolve({
      ...attachment,
      stream,
      deadlineSignal: controller.signal,
      cancelDeadline: () => {},
    });
  };

  const response = await createCamsKfintechIngestionHandler(customDeps)(
    request(validBody()),
  );
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.results[0].error.code, "mailbox_poll_failed");
  assertEquals(body.data.stopped, false);
  assertEquals(downloadCount.count, 1);
});

Deno.test("run byte limit stops later message downloads without false lineage", async () => {
  const downloadCount = { count: 0 };
  const firstMessageId = "run-limit-first";
  const secondMessageId = "run-limit-second";
  const failureCodes: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    downloadCount,
    failureCodes,
    registrarConfig: { totalBytesPerRun: 8 },
    messages: [
      message(camsDbfFixture(), {
        messageId: firstMessageId,
        attachments: [
          attachmentFixture(camsDbfFixture(), firstMessageId, "run-limit-a"),
        ],
      }),
      message(camsDbfFixture(), {
        messageId: secondMessageId,
        attachments: [
          attachmentFixture(camsDbfFixture(), secondMessageId, "run-limit-b"),
        ],
      }),
    ],
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(downloadCount.count, 1);
  assertEquals(body.data.attempted_attachments, 1);
  assertEquals(body.data.results[0].message_id, firstMessageId);
  assertEquals(body.data.stopped, true);
  assertEquals(failureCodes, ["attachment_too_large"]);
});

Deno.test("failure RPC outage preserves original attachment error", async () => {
  const finalizedRuns: {
    runId: string;
    stoppedReason?: string;
    failureCode?: string;
    observedAttachmentCount?: number;
  }[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    finalizedRuns,
    messages: [
      message(camsDbfFixture(), { senderAddress: "bad@example.test" }),
    ],
    recordFailure: () =>
      Promise.reject(new IngestionError("persistence_failed")),
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.results[0].error.code, "sender_not_allowed");
  assertEquals(body.data.results[0].error.lineage_write_failed, true);
  assertEquals(body.data.run_failure_code, "attempt_lineage_incomplete");
  assertEquals(finalizedRuns, [{
    runId: correlationId,
    stoppedReason: undefined,
    failureCode: "attempt_lineage_incomplete",
    observedAttachmentCount: 1,
  }]);
});

Deno.test("one durable success plus a lineage gap finalizes partially failed", async () => {
  let successCount = 0;
  const handler = createCamsKfintechIngestionHandler(deps({
    messages: [
      message(camsDbfFixture(), { messageId: "lineage-success" }),
      message(camsDbfFixture(), {
        messageId: "lineage-failure",
        senderAddress: "bad@example.test",
      }),
    ],
    persist: () => {
      successCount += 1;
      return Promise.resolve({
        document_id: "document-id",
        ingestion_log_id: "log-id",
        outbox_event_id: "event-id",
        transaction_count: 1,
        idempotent: false,
      });
    },
    recordFailure: () =>
      Promise.reject(new IngestionError("persistence_failed")),
    finalizeRun: (input) =>
      Promise.resolve({
        ingestion_run_id: input.ingestionRunId,
        status: "partially_failed",
        attempted_attachment_count: successCount,
        successful_attachment_count: successCount,
        failed_attachment_count: 0,
        duplicate_attachment_count: 0,
        stopped_attachment_count: 0,
        observed_attachment_count: input.observedAttachmentCount ?? 0,
        durable_attempt_count: successCount,
        lineage_gap_count: (input.observedAttachmentCount ?? 0) - successCount,
        stopped_reason: null,
        run_failure_code: input.failureCode ?? null,
      }),
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.run_status, "partially_failed");
  assertEquals(body.data.run_failure_code, "attempt_lineage_incomplete");
  assertEquals(body.data.observed_attachments, 2);
  assertEquals(body.data.durable_attempts, 1);
  assertEquals(body.data.lineage_gap_count, 1);
  assertEquals(body.data.results[1].error.code, "sender_not_allowed");
});

Deno.test("multiple durable successes plus one lineage gap never completes", async () => {
  const bytes = camsDbfFixture();
  const first = attachmentFixture(bytes, "lineage-multi", "att-1");
  const second = attachmentFixture(bytes, "lineage-multi", "att-2");
  const third = attachmentFixture(bytes, "lineage-multi-bad", "att-3");
  let successCount = 0;
  const handler = createCamsKfintechIngestionHandler(deps({
    messages: [
      message(bytes, {
        messageId: "lineage-multi",
        attachments: [first, second],
      }),
      message(bytes, {
        messageId: "lineage-multi-bad",
        senderAddress: "bad@example.test",
        attachments: [third],
      }),
    ],
    persist: () => {
      successCount += 1;
      return Promise.resolve({
        document_id: `document-${successCount}`,
        ingestion_log_id: `log-${successCount}`,
        outbox_event_id: `event-${successCount}`,
        transaction_count: 1,
        idempotent: false,
      });
    },
    recordFailure: () =>
      Promise.reject(new IngestionError("persistence_failed")),
    finalizeRun: (input) =>
      Promise.resolve({
        ingestion_run_id: input.ingestionRunId,
        status: "partially_failed",
        attempted_attachment_count: successCount,
        successful_attachment_count: successCount,
        failed_attachment_count: 0,
        duplicate_attachment_count: 0,
        stopped_attachment_count: 0,
        observed_attachment_count: input.observedAttachmentCount ?? 0,
        durable_attempt_count: successCount,
        lineage_gap_count: (input.observedAttachmentCount ?? 0) - successCount,
        stopped_reason: null,
        run_failure_code: input.failureCode ?? null,
      }),
  }));

  const response = await handler(request(validBody()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.run_status, "partially_failed");
  assertEquals(body.data.run_failure_code, "attempt_lineage_incomplete");
  assertEquals(body.data.observed_attachments, 3);
  assertEquals(body.data.durable_attempts, 2);
  assertEquals(body.data.lineage_gap_count, 1);
  assertEquals(body.data.results[2].error.code, "sender_not_allowed");
});

Deno.test("SHA-256 is computed from attachment bytes inside worker", async () => {
  let persistedSha = "";
  const bytes = camsDbfFixture();
  const expected = await sha256Hex(bytes);
  const handler = createCamsKfintechIngestionHandler(deps({
    messages: [message(bytes)],
    persist: (input) => {
      persistedSha = input.sha256Hex;
      return Promise.resolve({
        document_id: "document-id",
        ingestion_log_id: "log-id",
        outbox_event_id: "event-id",
        transaction_count: 1,
        idempotent: false,
      });
    },
  }));

  const response = await handler(request(validBody()));
  assertEquals(response.status, 200);
  assertEquals(persistedSha, expected);
});
