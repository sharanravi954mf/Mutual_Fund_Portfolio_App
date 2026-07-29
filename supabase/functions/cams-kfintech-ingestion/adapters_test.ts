import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  ConnectorCredentialRefresher,
  ConnectorMailboxClient,
  CredentialEnvelopeCrypto,
} from "./adapters.ts";
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
    await client.downloadAttachment(context(), {
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
