import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  ConnectorCredentialRefresher,
  ConnectorMailboxClient,
  CredentialEnvelopeCrypto,
  HttpMalwareScanner,
  RemotePdfTextExtractor,
  SupabaseWorkspaceAuthorizer,
} from "./adapters.ts";
import { readBoundedStream } from "./security.ts";
import { IngestionError, type IngestionRunContext } from "./types.ts";

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function context(): IngestionRunContext {
  return {
    workspaceId: "workspace-id",
    mailboxConnectionId: "mailbox-id",
    correlationId: "run-id",
    mailbox: {
      id: "mailbox-id",
      workspaceId: "workspace-id",
      registrar: "CAMS",
      connectorRef: "connector-ref",
      mailboxAddress: "advisor@example.test",
      allowedSenderAddresses: ["reports@camsonline.com"],
      maxAttachmentBytes: 1024,
    },
    credentials: {
      accessToken: "mailbox-oauth-access-token",
      refreshToken: "mailbox-oauth-refresh-token",
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
    },
    registrarConfig: {
      registrar: "CAMS",
      allowedSenderAddresses: ["reports@camsonline.com"],
      maxAttachmentBytes: 1024,
      maxMessagesPerPoll: 10,
      maxAttachmentsPerMessage: 5,
      maxAttachmentsPerRun: 10,
      totalBytesPerRun: 1024,
      supportedFileTypes: ["CAS_PDF", "DBF"],
    },
  };
}

function response(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status: init.status ?? 200,
    headers: { "content-type": "application/json", ...(init.headers ?? {}) },
  });
}

function delayedFetch(signal?: AbortSignal): Promise<Response> {
  return new Promise((_resolve, reject) => {
    signal?.addEventListener(
      "abort",
      () => reject(new DOMException("aborted", "AbortError")),
    );
  });
}

class FakeQuery {
  constructor(
    private readonly rows: Record<string, unknown>[],
    private readonly error: Error | null = null,
  ) {}

  select(): FakeQuery {
    return this;
  }

  eq(): FakeQuery {
    return this;
  }

  is(): FakeQuery {
    return this;
  }

  in(): FakeQuery {
    return this;
  }

  limit(): Promise<{ data: Record<string, unknown>[]; error: Error | null }> {
    return Promise.resolve({ data: this.rows, error: this.error });
  }
}

function authorizerClient(options: {
  userId?: string | null;
  profileRows?: Record<string, unknown>[];
  membershipRows?: Record<string, unknown>[];
} = {}) {
  return {
    auth: {
      getUser: () =>
        Promise.resolve({
          data: {
            user: options.userId === null
              ? null
              : { id: options.userId ?? "user-id" },
          },
          error: null,
        }),
    },
    from: (table: string) => {
      if (table === "profiles") {
        return new FakeQuery(options.profileRows ?? [{ id: "profile-id" }]);
      }
      if (table === "workspace_memberships") {
        return new FakeQuery(
          options.membershipRows ?? [{ profile_id: "profile-id" }],
        );
      }
      return new FakeQuery([]);
    },
  };
}

function authorizedRequest(token: string | null = "user-token"): Request {
  const headers = new Headers();
  if (token != null) {
    headers.set("x-user-authorization", `Bearer ${token}`);
  }
  return new Request("http://localhost", { headers });
}

Deno.test("credential envelope encrypts and decrypts one JSON bundle with AAD", async () => {
  const key = base64(crypto.getRandomValues(new Uint8Array(32)));
  const cryptoEnvelope = new CredentialEnvelopeCrypto(key);
  const encrypted = await cryptoEnvelope.encrypt(
    {
      accessToken: "access",
      refreshToken: "refresh",
      expiresAt: "2026-07-29T00:00:00Z",
    },
    "workspace-id",
    "mailbox-id",
  );

  const decrypted = await cryptoEnvelope.decrypt(
    encrypted,
    "workspace-id",
    "mailbox-id",
  );

  assertEquals(decrypted.accessToken, "access");
  assertEquals(decrypted.refreshToken, "refresh");
  assertEquals(decrypted.expiresAt, "2026-07-29T00:00:00Z");
});

Deno.test("credential refresh can be re-encrypted with a fresh nonce", async () => {
  const key = base64(crypto.getRandomValues(new Uint8Array(32)));
  const cryptoEnvelope = new CredentialEnvelopeCrypto(key);
  const first = await cryptoEnvelope.encrypt(
    {
      accessToken: "old-access",
      refreshToken: "old-refresh",
      expiresAt: "2026-07-29T00:00:00Z",
    },
    "workspace-id",
    "mailbox-id",
  );
  const second = await cryptoEnvelope.encrypt(
    {
      accessToken: "new-access",
      refreshToken: "new-refresh",
      expiresAt: "2026-07-29T01:00:00Z",
    },
    "workspace-id",
    "mailbox-id",
  );
  const decrypted = await cryptoEnvelope.decrypt(
    second,
    "workspace-id",
    "mailbox-id",
  );

  assertEquals(first.credentialNonce === second.credentialNonce, false);
  assertEquals(decrypted.accessToken, "new-access");
  assertEquals(decrypted.refreshToken, "new-refresh");
});

Deno.test("credential envelope rejects invalid key nonce and wrong AAD", async () => {
  const validKey = base64(crypto.getRandomValues(new Uint8Array(32)));
  const invalidKey = base64(crypto.getRandomValues(new Uint8Array(16)));
  const cryptoEnvelope = new CredentialEnvelopeCrypto(validKey);
  const encrypted = await cryptoEnvelope.encrypt(
    {
      accessToken: "access",
    },
    "workspace-id",
    "mailbox-id",
  );

  await assertRejects(
    () =>
      new CredentialEnvelopeCrypto(invalidKey).encrypt(
        {
          accessToken: "access",
        },
        "workspace-id",
        "mailbox-id",
      ),
    IngestionError,
    "oauth_credentials_unavailable",
  );
  await assertRejects(
    () =>
      cryptoEnvelope.decrypt(
        {
          ...encrypted,
          credentialNonce: base64(new Uint8Array(8)),
        },
        "workspace-id",
        "mailbox-id",
      ),
    IngestionError,
    "oauth_credentials_unavailable",
  );
  await assertRejects(
    () => cryptoEnvelope.decrypt(encrypted, "other-workspace", "mailbox-id"),
    IngestionError,
    "oauth_credentials_unavailable",
  );
});

Deno.test("workspace authorizer accepts exactly one active advisor/admin membership", async () => {
  const authorizer = new SupabaseWorkspaceAuthorizer(
    authorizerClient() as never,
  );

  await authorizer.authorize(authorizedRequest(), {
    workspaceId: "workspace-id",
  });
});

Deno.test("workspace authorizer rejects missing authenticated user token", async () => {
  const authorizer = new SupabaseWorkspaceAuthorizer(
    authorizerClient() as never,
  );

  await assertRejects(
    () =>
      authorizer.authorize(authorizedRequest(null), {
        workspaceId: "workspace-id",
      }),
    IngestionError,
    "authorization_required",
  );
});

Deno.test("workspace authorizer fails closed for cross-workspace and non-advisor users", async () => {
  const authorizer = new SupabaseWorkspaceAuthorizer(
    authorizerClient({ membershipRows: [] }) as never,
  );

  await assertRejects(
    () =>
      authorizer.authorize(authorizedRequest(), {
        workspaceId: "other-workspace",
      }),
    IngestionError,
    "not_authorized",
  );
});

Deno.test("workspace authorizer rejects ambiguous caller profile", async () => {
  const ambiguousProfile = new SupabaseWorkspaceAuthorizer(
    authorizerClient({
      profileRows: [{ id: "profile-1" }, { id: "profile-2" }],
    }) as never,
  );

  await assertRejects(
    () =>
      ambiguousProfile.authorize(authorizedRequest(), {
        workspaceId: "workspace-id",
      }),
    IngestionError,
    "not_authorized",
  );
});

Deno.test("connector rejects arbitrary external attachment URL from poll metadata", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(response({
      messages: [{
        sender_address: "reports@camsonline.com",
        message_id: "message-1",
        received_at: "2026-07-29T00:00:00Z",
        attachments: [{
          attachment_id: "attachment-1",
          filename: "cams.dbf",
          declared_mime: "application/x-dbase",
          received_at: "2026-07-29T00:00:00Z",
          download_url: "https://attacker.example/file",
        }],
      }],
    }));
  try {
    const client = new ConnectorMailboxClient(
      "https://connector.example/ingestion",
      "connector-service-token",
    );
    await assertRejects(
      () => client.poll(context()),
      IngestionError,
      "connector_untrusted_origin",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("connector rejects redirects to another origin during attachment retrieval", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(
      new Response(null, {
        status: 302,
        headers: { location: "https://attacker.example/file" },
      }),
    );
  try {
    const client = new ConnectorMailboxClient(
      "https://connector.example/ingestion",
      "connector-service-token",
    );
    await assertRejects(
      () =>
        client.downloadAttachment(context(), {
          senderAddress: "reports@camsonline.com",
          messageId: "message-1",
          receivedAt: "2026-07-29T00:00:00Z",
          attachments: [],
        }, {
          attachmentId: "attachment-1",
          filename: "cams.dbf",
          declaredMime: "application/x-dbase",
          receivedAt: "2026-07-29T00:00:00Z",
        }),
      IngestionError,
      "connector_untrusted_origin",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("attachment retrieval uses connector service token and never mailbox OAuth token", async () => {
  const seenAuthorizations: string[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (input, init) => {
    const requestInit = init as { headers?: HeadersInit } | undefined;
    const headers = requestInit?.headers;
    const authorization = headers instanceof Headers
      ? headers.get("authorization")
      : (headers as Record<string, string> | undefined)?.Authorization;
    seenAuthorizations.push(String(authorization));
    assertEquals(
      String(input),
      "https://connector.example/ingestion/attachments/fetch",
    );
    return Promise.resolve(new Response(new Uint8Array([1, 2, 3])));
  };
  try {
    const client = new ConnectorMailboxClient(
      "https://connector.example/ingestion",
      "connector-service-token",
    );
    const downloaded = await client.downloadAttachment(context(), {
      senderAddress: "reports@camsonline.com",
      messageId: "message-1",
      receivedAt: "2026-07-29T00:00:00Z",
      attachments: [],
    }, {
      attachmentId: "attachment-1",
      filename: "cams.dbf",
      declaredMime: "application/x-dbase",
      receivedAt: "2026-07-29T00:00:00Z",
    });
    downloaded.cancelDeadline?.();

    assertEquals(seenAuthorizations, ["Bearer connector-service-token"]);
    assertEquals(
      JSON.stringify(seenAuthorizations).includes("mailbox-oauth"),
      false,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("trusted connector credential refresher returns refreshed OAuth bundle", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (input, init) => {
    assertEquals(
      String(input),
      "https://connector.example/ingestion/oauth/refresh",
    );
    const headers = (init as { headers?: Record<string, string> }).headers;
    assertEquals(headers?.Authorization, "Bearer connector-service-token");
    return Promise.resolve(response({
      access_token: "new-access",
      refresh_token: "new-refresh",
      expires_at: "2026-07-29T01:00:00Z",
    }));
  };
  try {
    const refresher = new ConnectorCredentialRefresher(
      "https://connector.example/ingestion",
      "connector-service-token",
    );
    const refreshed = await refresher.refresh({
      workspaceId: "workspace-id",
      mailboxConnectionId: "mailbox-id",
      connectorRef: "connector-ref",
      registrar: "CAMS",
    }, {
      accessToken: "old-access",
      refreshToken: "old-refresh",
      expiresAt: "2026-07-29T00:00:00Z",
    });

    assertEquals(refreshed.accessToken, "new-access");
    assertEquals(refreshed.refreshToken, "new-refresh");
    assertEquals(refreshed.expiresAt, "2026-07-29T01:00:00Z");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("connector refresh is timeout and response-size bounded", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = (_input, init) =>
      delayedFetch((init as { signal?: AbortSignal }).signal);
    await assertRejects(
      () =>
        new ConnectorCredentialRefresher(
          "https://connector.example/ingestion",
          "connector-service-token",
          false,
          1,
          1024,
        ).refresh({
          workspaceId: "workspace-id",
          mailboxConnectionId: "mailbox-id",
          connectorRef: "connector-ref",
          registrar: "CAMS",
        }, {
          accessToken: "old-access",
          refreshToken: "old-refresh",
        }),
      IngestionError,
      "credential_refresh_failed",
    );

    globalThis.fetch = () =>
      Promise.resolve(response({
        access_token: "new-access",
        refresh_token: "new-refresh",
      }));
    await assertRejects(
      () =>
        new ConnectorCredentialRefresher(
          "https://connector.example/ingestion",
          "connector-service-token",
          false,
          10,
          2,
        ).refresh({
          workspaceId: "workspace-id",
          mailboxConnectionId: "mailbox-id",
          connectorRef: "connector-ref",
          registrar: "CAMS",
        }, {
          accessToken: "old-access",
          refreshToken: "old-refresh",
        }),
      IngestionError,
      "credential_refresh_failed",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("connector poll rejects timeout oversized JSON malformed metadata and empty IDs", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = (_input, init) =>
      delayedFetch((init as { signal?: AbortSignal }).signal);
    await assertRejects(
      () =>
        new ConnectorMailboxClient(
          "https://connector.example/ingestion",
          "connector-service-token",
          false,
          1,
          1024,
        ).poll(context()),
      IngestionError,
      "mailbox_poll_failed",
    );

    globalThis.fetch = () =>
      Promise.resolve(response({
        messages: [{
          sender_address: "reports@camsonline.com",
          message_id: "message-1",
          attachments: [{ attachment_id: "attachment-1" }],
        }],
      }));
    await assertRejects(
      () =>
        new ConnectorMailboxClient(
          "https://connector.example/ingestion",
          "connector-service-token",
          false,
          10,
          2,
        ).poll(context()),
      IngestionError,
      "mailbox_poll_failed",
    );

    for (
      const payload of [
        { messages: [{}] },
        {
          messages: [{
            message_id: "",
            attachments: [{ attachment_id: "attachment-1" }],
          }],
        },
        {
          messages: [{
            message_id: "message-1",
            attachments: [{ attachment_id: "" }],
          }],
        },
      ]
    ) {
      globalThis.fetch = () => Promise.resolve(response(payload));
      await assertRejects(
        () =>
          new ConnectorMailboxClient(
            "https://connector.example/ingestion",
            "connector-service-token",
          ).poll(context()),
        IngestionError,
        "mailbox_poll_failed",
      );
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("attachment retrieval timeout covers the stream consumption deadline", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(
          new ReadableStream<Uint8Array>({
            start() {
              // Keep the response body pending until the connector deadline aborts.
            },
          }),
        ),
      );
    const downloaded = await new ConnectorMailboxClient(
      "https://connector.example/ingestion",
      "connector-service-token",
      false,
      10,
      1024,
      1,
    ).downloadAttachment(context(), {
      senderAddress: "reports@camsonline.com",
      messageId: "message-1",
      receivedAt: "2026-07-29T00:00:00Z",
      attachments: [],
    }, {
      attachmentId: "attachment-1",
      filename: "cams.dbf",
      declaredMime: "application/x-dbase",
      receivedAt: "2026-07-29T00:00:00Z",
    });

    await assertRejects(
      () =>
        readBoundedStream(downloaded.stream, 1024, {
          signal: downloaded.deadlineSignal,
          abortCode: "mailbox_poll_failed",
        }),
      IngestionError,
      "mailbox_poll_failed",
    );
    downloaded.cancelDeadline?.();
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("malware scanner validates URL token redirect timeout and schema", async () => {
  assertThrows(
    () => new HttpMalwareScanner("http://scanner.example", "t", 1),
    IngestionError,
  );
  assertThrows(
    () => new HttpMalwareScanner("https://scanner.example", "", 1),
    IngestionError,
    "malware_scan_unavailable",
  );

  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = () =>
      Promise.resolve(new Response(null, { status: 302 }));
    await assertRejects(
      () =>
        new HttpMalwareScanner("https://scanner.example", "scanner-token", 10)
          .scan(new Uint8Array([1]), {
            sha256Hex: "a".repeat(64),
            filename: "a.dbf",
          }),
      IngestionError,
      "malware_scan_unavailable",
    );

    globalThis.fetch = (_input, init) =>
      delayedFetch((init as { signal?: AbortSignal }).signal);
    await assertRejects(
      () =>
        new HttpMalwareScanner("https://scanner.example", "scanner-token", 1)
          .scan(new Uint8Array([1]), {
            sha256Hex: "a".repeat(64),
            filename: "a.dbf",
          }),
      IngestionError,
      "malware_scan_unavailable",
    );

    for (
      const payload of [
        { version: "unknown", verdict: "clean" },
        { version: "moneybowl.malware-scan.v1", verdict: "mystery" },
      ]
    ) {
      globalThis.fetch = () => Promise.resolve(response(payload));
      await assertRejects(
        () =>
          new HttpMalwareScanner("https://scanner.example", "scanner-token", 10)
            .scan(new Uint8Array([1]), {
              sha256Hex: "a".repeat(64),
              filename: "a.dbf",
            }),
        IngestionError,
        "malware_scan_unavailable",
      );
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("malware scanner handles non-2xx oversized malformed clean and infected responses", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = () => Promise.resolve(response({}, { status: 500 }));
    await assertRejects(
      () =>
        new HttpMalwareScanner("https://scanner.example", "scanner-token", 10)
          .scan(new Uint8Array([1]), {
            sha256Hex: "a".repeat(64),
            filename: "a.dbf",
          }),
      IngestionError,
      "malware_scan_unavailable",
    );

    globalThis.fetch = () =>
      Promise.resolve(
        response({ version: "moneybowl.malware-scan.v1", verdict: "clean" }),
      );
    await assertRejects(
      () =>
        new HttpMalwareScanner(
          "https://scanner.example",
          "scanner-token",
          10,
          2,
        )
          .scan(new Uint8Array([1]), {
            sha256Hex: "a".repeat(64),
            filename: "a.dbf",
          }),
      IngestionError,
      "malware_scan_unavailable",
    );

    globalThis.fetch = () => Promise.resolve(new Response("{"));
    await assertRejects(
      () =>
        new HttpMalwareScanner("https://scanner.example", "scanner-token", 10)
          .scan(new Uint8Array([1]), {
            sha256Hex: "a".repeat(64),
            filename: "a.dbf",
          }),
      IngestionError,
      "malware_scan_unavailable",
    );

    globalThis.fetch = (_input, init) => {
      const headers = (init as { headers?: Record<string, string> }).headers;
      assertEquals(headers?.Authorization, "Bearer scanner-token");
      return Promise.resolve(response({
        version: "moneybowl.malware-scan.v1",
        verdict: "clean",
      }));
    };
    assertEquals(
      await new HttpMalwareScanner(
        "https://scanner.example",
        "scanner-token",
        10,
      )
        .scan(new Uint8Array([1]), {
          sha256Hex: "a".repeat(64),
          filename: "a.dbf",
        }),
      "clean",
    );

    globalThis.fetch = () =>
      Promise.resolve(response({
        version: "moneybowl.malware-scan.v1",
        verdict: "infected",
      }));
    await assertRejects(
      () =>
        new HttpMalwareScanner("https://scanner.example", "scanner-token", 10)
          .scan(new Uint8Array([1]), {
            sha256Hex: "a".repeat(64),
            filename: "a.dbf",
          }),
      IngestionError,
      "malware_detected",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("PDF extractor validates URL token redirect timeout schema registrar and rows", async () => {
  assertThrows(
    () => new RemotePdfTextExtractor("http://extractor.example", "t", 1, 1024),
    IngestionError,
  );
  assertThrows(
    () => new RemotePdfTextExtractor("https://extractor.example", "", 1, 1024),
    IngestionError,
    "unsupported_statement_format",
  );

  const originalFetch = globalThis.fetch;
  const pdf = new TextEncoder().encode("%PDF-1.7\nbody\n%%EOF");
  try {
    globalThis.fetch = () =>
      Promise.resolve(new Response(null, { status: 302 }));
    await assertRejects(
      () =>
        new RemotePdfTextExtractor(
          "https://extractor.example",
          "extractor-token",
          10,
          1024,
        )
          .extractRows({
            registrar: "CAMS",
            fileType: "CAS_PDF",
            filename: "cas.pdf",
            bytes: pdf,
          }),
      IngestionError,
      "parse_failed",
    );

    globalThis.fetch = (_input, init) =>
      delayedFetch((init as { signal?: AbortSignal }).signal);
    await assertRejects(
      () =>
        new RemotePdfTextExtractor(
          "https://extractor.example",
          "extractor-token",
          1,
          1024,
        )
          .extractRows({
            registrar: "CAMS",
            fileType: "CAS_PDF",
            filename: "cas.pdf",
            bytes: pdf,
          }),
      IngestionError,
      "parse_failed",
    );

    for (
      const payload of [
        {
          version: "unknown",
          registrar: "CAMS",
          statement_format: "CAS_PDF",
          rows: [],
        },
        {
          version: "moneybowl.pdf-extraction.v1",
          registrar: "KFINTECH",
          statement_format: "CAS_PDF",
          rows: [],
        },
        {
          version: "moneybowl.pdf-extraction.v1",
          registrar: "CAMS",
          statement_format: "CAS_PDF",
          rows: ["bad"],
        },
      ]
    ) {
      globalThis.fetch = () => Promise.resolve(response(payload));
      await assertRejects(
        () =>
          new RemotePdfTextExtractor(
            "https://extractor.example",
            "extractor-token",
            10,
            1024,
          )
            .extractRows({
              registrar: "CAMS",
              fileType: "CAS_PDF",
              filename: "cas.pdf",
              bytes: pdf,
            }),
        IngestionError,
        "parse_failed",
      );
    }

    globalThis.fetch = (_input, init) => {
      const headers = (init as { headers?: Record<string, string> }).headers;
      assertEquals(headers?.Authorization, "Bearer extractor-token");
      return Promise.resolve(response({
        version: "moneybowl.pdf-extraction.v1",
        registrar: "CAMS",
        statement_format: "CAS_PDF",
        rows: [{ PAN: "ABCDE1234F" }],
      }));
    };
    const rows = await new RemotePdfTextExtractor(
      "https://extractor.example",
      "extractor-token",
      10,
      1024,
    ).extractRows({
      registrar: "CAMS",
      fileType: "CAS_PDF",
      filename: "cas.pdf",
      bytes: pdf,
    });
    assertEquals(rows, [{ PAN: "ABCDE1234F" }]);

    await assertRejects(
      () =>
        new RemotePdfTextExtractor(
          "https://extractor.example",
          "extractor-token",
          10,
          1024,
        )
          .extractRows({
            registrar: "CAMS",
            fileType: "CAS_PDF",
            filename: "truncated.pdf",
            bytes: new TextEncoder().encode("%PDF-1.7"),
          }),
      IngestionError,
      "unsupported_statement_format",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
