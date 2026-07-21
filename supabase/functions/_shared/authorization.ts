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
  return token.isEmpty ? null : token;
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

export async function requireAdvisor(
  req: Request,
): Promise<AuthorizationResult> {
  const authentication = await requireAuthenticated(req);
  if ("failure" in authentication) {
    return authentication;
  }

  const client = serverClient();
  const { data, error } = await client
    .from("profiles")
    .select("id")
    .eq("user_id", authentication.userId)
    .eq("role", "admin")
    .maybeSingle();

  if (error != null || data == null) {
    return authorizationFailure(403, "Advisor access is required.");
  }

  return authentication;
}
