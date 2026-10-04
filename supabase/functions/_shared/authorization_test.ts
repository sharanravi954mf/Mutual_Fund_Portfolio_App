import { requireAdvisor, requirePlatformAdmin } from "./authorization.ts";

function assert(value: boolean, message: string) {
  if (!value) throw new Error(message);
}

Deno.test("workspace and platform authority come from separate caller-bound RPCs", async () => {
  const previousFetch = globalThis.fetch;
  const names = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"];
  const previousEnv = names.map((name) => Deno.env.get(name));
  Deno.env.set("SUPABASE_URL", "https://authorization.invalid");
  Deno.env.set("SUPABASE_ANON_KEY", "synthetic-anon");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "synthetic-service");
  const calls: string[] = [];
  let permitted = false;
  globalThis.fetch = async (input, init) => {
    const url = input instanceof Request ? input.url : input.toString();
    calls.push(url);
    const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
    assert(headers.get("authorization") === "Bearer synthetic-user-token", "RPC must execute as caller");
    if (url.endsWith("/auth/v1/user")) {
      return new Response(JSON.stringify({ id: "synthetic-user", app_metadata: { user_role: "platform_admin" }, user_metadata: { role: "admin" } }), { headers: { "content-type": "application/json" } });
    }
    assert(url.includes("/rest/v1/rpc/"), "global profile lookup cannot authorize business access");
    return new Response(JSON.stringify(permitted), { headers: { "content-type": "application/json" } });
  };
  const request = new Request("https://function.invalid", { headers: { authorization: "Bearer synthetic-user-token" } });
  try {
    assert("failure" in await requireAdvisor(request), "stale or self-supplied role claims must not authorize");
    assert(calls.at(-1)?.endsWith("/rpc/authorize_workspace_tools") === true, "workspace utility capability required");
    permitted = true;
    assert("userId" in await requireAdvisor(request), "active workspace capability should authorize uploaded-document tools");
    permitted = false;
    assert("failure" in await requirePlatformAdmin(request), "workspace admin must not become platform admin");
    assert(calls.at(-1)?.endsWith("/rpc/is_platform_admin") === true, "platform authority must use its distinct RPC");
    const before = calls.length;
    assert("failure" in await requireAdvisor(new Request("https://function.invalid", { headers: { authorization: "Bearer " } })), "empty token denied");
    assert(calls.length === before, "empty token should not cause a network request");
  } finally {
    globalThis.fetch = previousFetch;
    names.forEach((name, index) => previousEnv[index] === undefined ? Deno.env.delete(name) : Deno.env.set(name, previousEnv[index]!));
  }
});
