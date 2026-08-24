import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { CredentialEnvelopeCrypto } from "./adapters.ts";
import {
  createGmailOAuthHandler,
  type GmailOAuthDependencies,
} from "./oauth.ts";
import { type EncryptedCredentialEnvelope, IngestionError } from "./types.ts";

const WORKSPACE = "11111111-1111-4111-8111-111111111111";
const MAILBOX = "22222222-2222-4222-8222-222222222222";
const AUTHORIZATION = "33333333-3333-4333-8333-333333333333";
const STATE = "A".repeat(43);
const REDIRECT =
  "https://dev.example.test/functions/v1/cams-kfintech-ingestion/oauth/callback";
const HOSTED_RUNTIME_CALLBACK =
  "http://edge-runtime.internal/cams-kfintech-ingestion/oauth/callback";
const KEY = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));

type Captures = {
  stateHash?: string;
  completed?: EncryptedCredentialEnvelope;
  failed?: string;
  revoked?: boolean;
  exchangedCode?: string;
  beginRedirectUri?: string;
  consumeRedirectUri?: string;
  exchangeRedirectUri?: string;
};

function dependencies(options: {
  flowKind?: "first_time" | "reauthorization";
  consumeError?: string;
  authorize?: boolean;
  exchangeRefreshToken?: string;
  connectorError?: string;
} = {}): { deps: GmailOAuthDependencies; captures: Captures } {
  const captures: Captures = {};
  const crypto = new CredentialEnvelopeCrypto(KEY);
  const flowKind = options.flowKind ?? "first_time";
  return {
    captures,
    deps: {
      redirectUri: REDIRECT,
      now: () => new Date("2026-08-23T08:00:00Z"),
      generateState: () => STATE,
      workspaceAuthorizer: {
        authorize: async () => {
          if (options.authorize === false) {
            throw new IngestionError("not_authorized");
          }
        },
      },
      stateRepository: {
        begin: async (input) => {
          captures.stateHash = input.stateHash;
          captures.beginRedirectUri = input.redirectUri;
          assertEquals(input.redirectUri, REDIRECT);
          assertEquals(input.expiresAt, "2026-08-23T08:10:00.000Z");
          return { flowKind };
        },
        consume: async (_stateHash, redirectUri) => {
          captures.consumeRedirectUri = redirectUri;
          if (options.consumeError) {
            throw new IngestionError(
              options.consumeError as "oauth_state_invalid",
            );
          }
          return {
            authorizationId: AUTHORIZATION,
            workspaceId: WORKSPACE,
            mailboxConnectionId: MAILBOX,
            flowKind,
          };
        },
        fail: async (_id, code) => {
          captures.failed = code;
        },
        complete: async (input) => {
          captures.completed = input.envelope;
          return flowKind;
        },
        revoke: async () => {
          captures.revoked = true;
        },
      },
      credentials: {
        encrypt: (bundle, workspace, mailbox) =>
          crypto.encrypt(bundle, workspace, mailbox),
        loadForRevocation: async () => ({
          bundle: {
            accessToken: "access-secret",
            refreshToken: "refresh-secret",
          },
          credentialNonce: "nonce-fence",
        }),
      },
      connector: {
        authorizationUrl: async (state, redirect) => {
          assertEquals(state, STATE);
          assertEquals(redirect, REDIRECT);
          return `https://accounts.google.test/oauth?state=${state}`;
        },
        exchange: async (code, redirectUri) => {
          captures.exchangedCode = code;
          captures.exchangeRedirectUri = redirectUri;
          if (options.connectorError) {
            throw new IngestionError(
              options.connectorError as "oauth_exchange_failed",
            );
          }
          return {
            accessToken: "access-secret",
            refreshToken: options.exchangeRefreshToken === undefined
              ? "refresh-secret"
              : options.exchangeRefreshToken,
            expiresAt: "2026-08-23T09:00:00Z",
          };
        },
        revoke: async (token) => assertEquals(token, "refresh-secret"),
      },
    },
  };
}

function startRequest(): Request {
  return new Request(REDIRECT.replace("/oauth/callback", "/oauth/start"), {
    method: "POST",
    headers: {
      Authorization: "Bearer user-jwt",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      workspace_id: WORKSPACE,
      mailbox_connection_id: MAILBOX,
    }),
  });
}

function callback(query: string, uri = REDIRECT): Request {
  return new Request(`${uri}?${query}`, { method: "GET" });
}

Deno.test("OAuth start creates a hashed, expiring state and returns only an authorization URL", async () => {
  const { deps, captures } = dependencies();
  const response = await createGmailOAuthHandler(deps)(startRequest());
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.data.flow_kind, "first_time");
  assertEquals(captures.stateHash?.length, 64);
  assert(!JSON.stringify(body).includes("user-jwt"));
});

Deno.test("valid callback encrypts first write with existing workspace/mailbox AAD", async () => {
  const { deps, captures } = dependencies();
  const response = await createGmailOAuthHandler(deps)(
    callback(`state=${STATE}&code=one-time-code`),
  );
  assertEquals(response.status, 200);
  assertEquals(captures.exchangedCode, "one-time-code");
  assert(captures.completed != null);
  const serialized = JSON.stringify(captures.completed);
  assert(!serialized.includes("access-secret"));
  assert(!serialized.includes("refresh-secret"));
  const bundle = await new CredentialEnvelopeCrypto(KEY).decrypt(
    captures.completed!,
    WORKSPACE,
    MAILBOX,
  );
  assertEquals(bundle.refreshToken, "refresh-secret");
  const body = await response.text();
  assert(!body.includes("access-secret"));
  assert(!body.includes("refresh-secret"));
});

Deno.test("Hosted Edge callback accepts its runtime origin while preserving the configured external redirect binding", async () => {
  const { deps, captures } = dependencies();
  const handler = createGmailOAuthHandler(deps);

  assertEquals((await handler(startRequest())).status, 200);
  const response = await handler(
    callback(`state=${STATE}&code=one-time-code`, HOSTED_RUNTIME_CALLBACK),
  );

  assertEquals(response.status, 200);
  assertEquals(captures.beginRedirectUri, REDIRECT);
  assertEquals(captures.consumeRedirectUri, REDIRECT);
  assertEquals(captures.exchangeRedirectUri, REDIRECT);
});

Deno.test("configured callback requires the strict public Supabase function route", () => {
  for (
    const redirectUri of [
      "https://dev.example.test/cams-kfintech-ingestion/oauth/callback",
      "https://dev.example.test/functions/v1/other/callback",
      "https://dev.example.test/functions/v1/foo/cams-kfintech-ingestion/oauth/callback",
      "https://dev.example.test/functions/v1//oauth/callback",
    ]
  ) {
    const { deps } = dependencies();
    deps.redirectUri = redirectUri;
    assertThrows(
      () => createGmailOAuthHandler(deps),
      IngestionError,
      "oauth_redirect_uri_mismatch",
    );
  }
});

Deno.test("invalid, expired, and replayed state are rejected deterministically", async () => {
  for (
    const [error, status] of [
      ["oauth_state_invalid", 422],
      ["oauth_state_expired", 422],
      ["oauth_state_replayed", 409],
    ] as const
  ) {
    const { deps } = dependencies({ consumeError: error });
    const response = await createGmailOAuthHandler(deps)(
      callback(`state=${STATE}&code=code`),
    );
    assertEquals(response.status, status);
    assertEquals((await response.json()).error.code, error);
  }
});

Deno.test("callback is GET-only and rejects missing or malformed state", async () => {
  const { deps } = dependencies();
  const handler = createGmailOAuthHandler(deps);
  assertEquals(
    (await handler(new Request(REDIRECT, { method: "POST" }))).status,
    405,
  );
  assertEquals((await handler(callback("code=code"))).status, 422);
  const malformedState = await handler(callback("state=short&code=code"));
  assertEquals(malformedState.status, 422);
  assertEquals(
    (await malformedState.json()).error.code,
    "oauth_state_invalid",
  );
});

Deno.test("callback rejects every pathname outside the two configured deterministic forms", async () => {
  const { deps, captures } = dependencies();
  const handler = createGmailOAuthHandler(deps);
  const invalidPathnames = [
    "/other-function/oauth/callback",
    "/foo/cams-kfintech-ingestion/oauth/callback",
    "/cams-kfintech-ingestion/other/callback",
    "/unrelated",
  ];

  for (const pathname of invalidPathnames) {
    const mismatch = await handler(
      callback(
        `state=${STATE}&code=code`,
        `http://edge-runtime.internal${pathname}`,
      ),
    );
    assertEquals(mismatch.status, 422);
    assertEquals(
      (await mismatch.json()).error.code,
      "oauth_redirect_uri_mismatch",
    );
  }
  assertEquals(captures.consumeRedirectUri, undefined);
});

Deno.test("Google error, missing code, exchange error, and missing refresh token consume then fail", async () => {
  const cases = [
    {
      query: `state=${STATE}&error=access_denied`,
      expected: "oauth_provider_error",
    },
    { query: `state=${STATE}`, expected: "oauth_code_required" },
    {
      query: `state=${STATE}&code=code`,
      expected: "oauth_exchange_failed",
      connectorError: "oauth_exchange_failed",
    },
    {
      query: `state=${STATE}&code=code`,
      expected: "oauth_refresh_token_required",
      exchangeRefreshToken: "",
    },
  ];
  for (const test of cases) {
    const { deps, captures } = dependencies(test);
    const response = await createGmailOAuthHandler(deps)(callback(test.query));
    assertEquals((await response.json()).error.code, test.expected);
    assertEquals(captures.failed, test.expected);
  }
});

Deno.test("reauthorization replaces through the same encrypted completion path", async () => {
  const { deps, captures } = dependencies({ flowKind: "reauthorization" });
  const start = await createGmailOAuthHandler(deps)(startRequest());
  assertEquals((await start.json()).data.flow_kind, "reauthorization");
  const complete = await createGmailOAuthHandler(deps)(
    callback(`state=${STATE}&code=code`),
  );
  assertEquals((await complete.json()).data.flow_kind, "reauthorization");
  assert(captures.completed != null);
});

Deno.test("revocation is authorized and leaves mailbox requiring reauthorization", async () => {
  const { deps, captures } = dependencies();
  const revoke = REDIRECT.replace("/oauth/callback", "/oauth/revoke");
  const response = await createGmailOAuthHandler(deps)(
    new Request(revoke, {
      method: "POST",
      headers: {
        Authorization: "Bearer user-jwt",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        workspace_id: WORKSPACE,
        mailbox_connection_id: MAILBOX,
      }),
    }),
  );
  assertEquals(response.status, 200);
  assertEquals(captures.revoked, true);
  assertEquals((await response.json()).data.reauthorization_required, true);
});

Deno.test("OAuth start preserves advisor/admin authorization boundary", async () => {
  const { deps } = dependencies({ authorize: false });
  const response = await createGmailOAuthHandler(deps)(startRequest());
  assertEquals(response.status, 403);
  assertEquals((await response.json()).error.code, "not_authorized");
});
