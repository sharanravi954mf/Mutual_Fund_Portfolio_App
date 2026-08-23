import { bearerToken, errorStatus, sha256Hex } from "./security.ts";
import {
  type CredentialBundle,
  type EncryptedCredentialEnvelope,
  type FailureCode,
  IngestionError,
} from "./types.ts";

const STATE_TTL_MS = 10 * 60 * 1000;
const STATE_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type ConsumedAuthorization = {
  authorizationId: string;
  workspaceId: string;
  mailboxConnectionId: string;
  flowKind: "first_time" | "reauthorization";
};

export type GmailOAuthDependencies = {
  redirectUri: string;
  now?: () => Date;
  generateState?: () => string;
  workspaceAuthorizer: {
    authorize(req: Request, input: { workspaceId: string }): Promise<void>;
  };
  stateRepository: {
    begin(input: {
      userToken: string;
      workspaceId: string;
      mailboxConnectionId: string;
      stateHash: string;
      redirectUri: string;
      expiresAt: string;
    }): Promise<{ flowKind: "first_time" | "reauthorization" }>;
    consume(
      stateHash: string,
      redirectUri: string,
    ): Promise<ConsumedAuthorization>;
    fail(authorizationId: string, code: FailureCode): Promise<void>;
    complete(input: {
      authorizationId: string;
      envelope: EncryptedCredentialEnvelope;
      expiresAt: string;
    }): Promise<"first_time" | "reauthorization">;
    revoke(input: {
      userToken: string;
      workspaceId: string;
      mailboxConnectionId: string;
      expectedCredentialNonce: string;
    }): Promise<void>;
  };
  credentials: {
    encrypt(
      bundle: CredentialBundle,
      workspaceId: string,
      mailboxConnectionId: string,
    ): Promise<EncryptedCredentialEnvelope>;
    loadForRevocation(
      workspaceId: string,
      mailboxConnectionId: string,
    ): Promise<{
      bundle: CredentialBundle;
      credentialNonce: string;
    }>;
  };
  connector: {
    authorizationUrl(state: string, redirectUri: string): Promise<string>;
    exchange(code: string, redirectUri: string): Promise<CredentialBundle>;
    revoke(token: string): Promise<void>;
  };
};

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function requiredUuid(value: unknown): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw new IngestionError("oauth_request_invalid");
  }
  return value.toLowerCase();
}

function randomState(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

async function stateHash(state: string): Promise<string> {
  return await sha256Hex(new TextEncoder().encode(state));
}

function onlyQueryValue(url: URL, name: string): string | null {
  const values = url.searchParams.getAll(name);
  if (values.length > 1) throw new IngestionError("oauth_request_invalid");
  return values[0] ?? null;
}

function requestCallbackUri(url: URL): string {
  return `${url.origin}${url.pathname}`;
}

async function parseObject(req: Request): Promise<Record<string, unknown>> {
  try {
    const parsed: unknown = await req.json();
    if (parsed == null || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("invalid");
    }
    return parsed as Record<string, unknown>;
  } catch (_error) {
    throw new IngestionError("oauth_request_invalid");
  }
}

async function markFailed(
  deps: GmailOAuthDependencies,
  authorizationId: string,
  code: FailureCode,
): Promise<never> {
  try {
    await deps.stateRepository.fail(authorizationId, code);
  } catch (_error) {
    // Preserve the original sanitized OAuth failure; the state is already consumed.
  }
  throw new IngestionError(code);
}

function validateRedirectConfiguration(redirectUri: string): void {
  let parsed: URL;
  try {
    parsed = new URL(redirectUri);
  } catch (_error) {
    throw new IngestionError("oauth_redirect_uri_mismatch");
  }
  const local = parsed.hostname === "localhost" ||
    parsed.hostname === "127.0.0.1";
  if (
    (parsed.protocol !== "https:" && !(local && parsed.protocol === "http:")) ||
    parsed.username !== "" || parsed.password !== "" || parsed.search !== "" ||
    parsed.hash !== ""
  ) {
    throw new IngestionError("oauth_redirect_uri_mismatch");
  }
}

export function createGmailOAuthHandler(
  deps: GmailOAuthDependencies,
): (req: Request) => Promise<Response> {
  validateRedirectConfiguration(deps.redirectUri);
  const now = deps.now ?? (() => new Date());
  const generateState = deps.generateState ?? randomState;

  return async (req: Request): Promise<Response> => {
    try {
      const url = new URL(req.url);
      if (url.pathname.endsWith("/oauth/start")) {
        if (req.method !== "POST") {
          return response({ error: { code: "not_authorized" } }, 405);
        }
        const userToken = bearerToken(req);
        if (userToken == null) {
          throw new IngestionError("authorization_required");
        }
        const body = await parseObject(req);
        const workspaceId = requiredUuid(body.workspace_id);
        const mailboxConnectionId = requiredUuid(body.mailbox_connection_id);
        await deps.workspaceAuthorizer.authorize(req, { workspaceId });

        const state = generateState();
        if (!STATE_PATTERN.test(state)) {
          throw new IngestionError("oauth_request_invalid");
        }
        const expiresAt = new Date(now().getTime() + STATE_TTL_MS)
          .toISOString();
        const started = await deps.stateRepository.begin({
          userToken,
          workspaceId,
          mailboxConnectionId,
          stateHash: await stateHash(state),
          redirectUri: deps.redirectUri,
          expiresAt,
        });
        const authorizationUrl = await deps.connector.authorizationUrl(
          state,
          deps.redirectUri,
        );
        return response({
          data: {
            authorization_url: authorizationUrl,
            flow_kind: started.flowKind,
            expires_at: expiresAt,
          },
        });
      }

      if (url.pathname.endsWith("/oauth/callback")) {
        if (req.method !== "GET") {
          return response({ error: { code: "not_authorized" } }, 405);
        }
        if (requestCallbackUri(url) !== deps.redirectUri) {
          throw new IngestionError("oauth_redirect_uri_mismatch");
        }
        const state = onlyQueryValue(url, "state");
        if (state == null || !STATE_PATTERN.test(state)) {
          throw new IngestionError("oauth_state_invalid");
        }
        const consumed = await deps.stateRepository.consume(
          await stateHash(state),
          deps.redirectUri,
        );
        if (onlyQueryValue(url, "error") != null) {
          return await markFailed(
            deps,
            consumed.authorizationId,
            "oauth_provider_error",
          );
        }
        const code = onlyQueryValue(url, "code");
        if (code == null || code.trim() === "" || code.length > 8192) {
          return await markFailed(
            deps,
            consumed.authorizationId,
            "oauth_code_required",
          );
        }

        let bundle: CredentialBundle;
        try {
          bundle = await deps.connector.exchange(code, deps.redirectUri);
        } catch (error) {
          const failure = error instanceof IngestionError
            ? error.code
            : "oauth_exchange_failed";
          return await markFailed(deps, consumed.authorizationId, failure);
        }
        if (bundle.refreshToken == null || bundle.refreshToken.trim() === "") {
          return await markFailed(
            deps,
            consumed.authorizationId,
            "oauth_refresh_token_required",
          );
        }
        if (
          bundle.expiresAt == null ||
          !Number.isFinite(Date.parse(bundle.expiresAt))
        ) {
          return await markFailed(
            deps,
            consumed.authorizationId,
            "oauth_exchange_failed",
          );
        }
        const envelope = await deps.credentials.encrypt(
          bundle,
          consumed.workspaceId,
          consumed.mailboxConnectionId,
        );
        const flowKind = await deps.stateRepository.complete({
          authorizationId: consumed.authorizationId,
          envelope,
          expiresAt: bundle.expiresAt,
        });
        return response({
          data: {
            status: "connected",
            mailbox_connection_id: consumed.mailboxConnectionId,
            flow_kind: flowKind,
          },
        });
      }

      if (url.pathname.endsWith("/oauth/revoke")) {
        if (req.method !== "POST") {
          return response({ error: { code: "not_authorized" } }, 405);
        }
        const userToken = bearerToken(req);
        if (userToken == null) {
          throw new IngestionError("authorization_required");
        }
        const body = await parseObject(req);
        const workspaceId = requiredUuid(body.workspace_id);
        const mailboxConnectionId = requiredUuid(body.mailbox_connection_id);
        await deps.workspaceAuthorizer.authorize(req, { workspaceId });
        const loaded = await deps.credentials.loadForRevocation(
          workspaceId,
          mailboxConnectionId,
        );
        const token = loaded.bundle.refreshToken ?? loaded.bundle.accessToken;
        try {
          await deps.connector.revoke(token);
        } catch (_error) {
          throw new IngestionError("oauth_revocation_failed");
        }
        await deps.stateRepository.revoke({
          userToken,
          workspaceId,
          mailboxConnectionId,
          expectedCredentialNonce: loaded.credentialNonce,
        });
        return response({
          data: { status: "revoked", reauthorization_required: true },
        });
      }

      return response({ error: { code: "not_authorized" } }, 404);
    } catch (error) {
      const code = error instanceof IngestionError
        ? error.code
        : "oauth_request_invalid";
      return response({ error: { code } }, errorStatus(code));
    }
  };
}
