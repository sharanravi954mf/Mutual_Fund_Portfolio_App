import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

export type AuthorizationFailure = {
  status: number;
  message: string;
};

export type AuthorizationResult =
  | { userId: string }
  | { failure: AuthorizationFailure };

function authorizationFailure(status: number, message: string): AuthorizationResult {
  return { failure: { status, message } };
}

function accessTokenFromRequest(req: Request): string | null {
  const header = req.headers.get("authorization");
  if (header == null || !header.startsWith("Bearer ")) {
    return null;
  }

  const token = header.substring("Bearer ".length).trim();
  return token.length === 0 ? null : token;
}

function serverClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL") || "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "",
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
}

export async function requireAuthenticated(
  req: Request,
): Promise<AuthorizationResult> {
  const accessToken = accessTokenFromRequest(req);
  if (accessToken == null) {
    return authorizationFailure(401, "Authentication is required.");
  }

  const client = serverClient();
  const { data, error } = await client.auth.getUser(accessToken);
  if (error != null || data.user == null) {
    return authorizationFailure(401, "Authentication is required.");
  }

  return { userId: data.user.id };
}

async function requireCapability(
  req: Request,
  capability: "authorize_workspace_tools" | "is_platform_admin",
): Promise<AuthorizationResult> {
  const authentication = await requireAuthenticated(req);
  if ("failure" in authentication) {
    return authentication;
  }

  // Execute as the caller so the database checks current account/membership
  // lifecycle. Never authorize tenant actions from a global profile label.
  const client = createClient(
    Deno.env.get("SUPABASE_URL") || "",
    Deno.env.get("SUPABASE_ANON_KEY") || "",
    { global: { headers: { Authorization: req.headers.get("authorization")! } },
      auth: { autoRefreshToken: false, persistSession: false } },
  );
  const { data, error } = await client.rpc(capability);

  if (error != null || data !== true) {
    return authorizationFailure(403, "Authorized access is required.");
  }

  return authentication;
}

export function requireAdvisor(req: Request): Promise<AuthorizationResult> {
  return requireCapability(req, "authorize_workspace_tools");
}

export function requirePlatformAdmin(req: Request): Promise<AuthorizationResult> {
  return requireCapability(req, "is_platform_admin");
}
