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
} from "./types.ts";

const internalToken = "internal-ingestion-token";

function request(
  body: Record<string, unknown>,
  token = internalToken,
): Request {
  return new Request("http://localhost/cams-kfintech-ingestion", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
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
  return {
    senderAddress: "reports@camsonline.com",
    messageId: "message-1",
    receivedAt: "2026-07-29T00:00:00Z",
    attachments: [{
      filename: "cams.dbf",
      declaredMime: "application/x-dbase",
      receivedAt: "2026-07-29T00:00:00Z",
      stream: streamFromBytes(bytes),
    }],
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
} = {}): HandlerDependencies {
  const stages = options.stages ?? [];
  const failureCodes = options.failureCodes ?? [];
  let storedBytes: Uint8Array | null = null;

  return {
    internalToken,
    onStage: (stage) => stages.push(stage),
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
            supportedFileTypes: ["CAS_PDF", "DBF"],
          },
        });
      },
    },
    mailboxClient: {
      poll: () => Promise.resolve(options.messages ?? [message()]),
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
      persist: options.persist ??
        (() =>
          Promise.resolve({
            document_id: "document-id",
            ingestion_log_id: "log-id",
            outbox_event_id: "event-id",
            transaction_count: 1,
            idempotent: false,
          })),
      recordFailure: (input) => {
        failureCodes.push(input.failureCode);
        return Promise.resolve();
      },
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
    "load_credentials",
    "imap_oauth_connector",
    "poll_mailbox",
    "validate_sender",
    "read_attachment_stream",
    "calculate_sha256",
    "validate_mime_magic",
    "malware_scan",
    "encrypted_storage_write",
    "encrypted_storage_read",
    "parse",
    "persist",
    "complete_lineage",
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

  assertEquals(response.status, 409);
  assertEquals(body.error.code, "sender_not_allowed");
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

  assertEquals(response.status, 422);
  assertEquals(body.error.code, "attachment_hash_mismatch");
  assertEquals(stages.includes("malware_scan"), false);
});

Deno.test("MIME and magic mismatch is rejected", async () => {
  const handler = createCamsKfintechIngestionHandler(deps({
    messages: [message(camsDbfFixture(), {
      attachments: [{
        filename: "cams.pdf",
        declaredMime: "application/pdf",
        receivedAt: "2026-07-29T00:00:00Z",
        stream: streamFromBytes(camsDbfFixture()),
      }],
    })],
  }));

  const response = await handler(request(validBody()));
  assertEquals(response.status, 422);
  assertEquals((await response.json()).error.code, "magic_byte_mismatch");
});

Deno.test("application/octet-stream is accepted only for valid DBF magic bytes", async () => {
  const handler = createCamsKfintechIngestionHandler(deps({
    messages: [message(camsDbfFixture(), {
      attachments: [{
        filename: "cams.dbf",
        declaredMime: "application/octet-stream",
        receivedAt: "2026-07-29T00:00:00Z",
        stream: streamFromBytes(camsDbfFixture()),
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
  assertEquals(response.status, 422);
  assertEquals((await response.json()).error.code, "unsupported_media_type");
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

  assertEquals((await infected(request(validBody()))).status, 409);
  assertEquals((await unavailable(request(validBody()))).status, 422);
  assertEquals((await invalid(request(validBody()))).status, 422);
});

Deno.test("storage precedes parsing and parsing failure prevents persistence", async () => {
  const stages: string[] = [];
  let persisted = false;
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    storageReadBytes: camsDbfFixture({ AMOUNT: "bad-value" }),
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

  assertEquals(body.error.code, "parse_failed");
  assertEquals(
    stages.indexOf("encrypted_storage_read") < stages.indexOf("parse"),
    true,
  );
  assertEquals(persisted, false);
});

Deno.test("completion event occurs only after persistence", async () => {
  const stages: string[] = [];
  const handler = createCamsKfintechIngestionHandler(deps({
    stages,
    persist: () => Promise.reject(new IngestionError("persistence_failed")),
  }));

  const response = await handler(request(validBody()));
  assertEquals(response.status, 422);
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

  assertEquals((await empty(request(validBody()))).status, 422);
  assertEquals((await truncated(request(validBody()))).status, 422);
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
  assertEquals(stages, ["internal_authorization", "load_credentials"]);
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
  assertEquals(response.status, 409);
  assertEquals((await response.json()).error.code, "duplicate_attachment");
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
    storageReadBytes: camsDbfFixture({ TRX_DATE: "bad-date" }),
  }))(request(validBody()));

  assertEquals(senderFailures, ["sender_not_allowed"]);
  assertEquals(malwareFailures, ["malware_detected"]);
  assertEquals(parseFailures, ["parse_failed"]);
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
