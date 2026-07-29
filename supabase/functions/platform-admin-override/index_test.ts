import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  createPlatformAdminOverrideHandler,
  type AuthClient,
  type RpcClient,
} from "./handler.ts";

type RpcCall = {
  fn: string;
  args: Record<string, unknown>;
};

function request(body: Record<string, unknown>, token = "valid-token"): Request {
  return new Request("http://localhost/platform-admin-override", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function validPayload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    workspace_id: "97200000-0000-0000-0000-000000000001",
    entity_type: "family_delegations",
    entity_id: "97400000-0000-0000-0000-000000000001",
    owner_profile_id: "97100000-0000-0000-0000-000000000003",
    delegate_profile_id: "97100000-0000-0000-0000-000000000009",
    action: "family_delegation.restore_access",
    reason: "Restore consent-backed access after identity-link correction",
    correlation_id: "97900000-0000-0000-0000-000000000001",
    ...overrides,
  };
}

function fakeAuth(valid = true): AuthClient {
  return {
    auth: {
      getUser: () =>
        Promise.resolve({
          data: valid ? { user: { id: "user-id" } } : { user: null },
          error: valid ? null : new Error("bad token"),
        }),
    },
  };
}

function fakeClient(
  calls: RpcCall[],
  results: Record<string, { data?: unknown; error?: { message: string } }> = {},
): RpcClient {
  return {
    rpc: (fn, args) => {
      calls.push({ fn, args });
      const result = results[fn] ?? { data: { ok: true } };
      return Promise.resolve({
        data: result.data ?? null,
        error: result.error ?? null,
      });
    },
  };
}

Deno.test("platform admin override requires Authorization header", async () => {
  const handler = createPlatformAdminOverrideHandler({
    authenticateClient: fakeAuth(),
    userClientForToken: () => fakeClient([]),
    serviceClient: fakeClient([]),
  });

  const response = await handler(new Request("http://localhost", { method: "POST" }));
  const body = await response.json();

  assertEquals(response.status, 401);
  assertEquals(body.error.code, "authorization_required");
});

Deno.test("platform admin override denies invalid token before RPC calls", async () => {
  const calls: RpcCall[] = [];
  const handler = createPlatformAdminOverrideHandler({
    authenticateClient: fakeAuth(false),
    userClientForToken: () => fakeClient(calls),
    serviceClient: fakeClient(calls),
  });

  const response = await handler(request(validPayload(), "invalid-token"));
  const body = await response.json();

  assertEquals(response.status, 401);
  assertEquals(body.error.code, "invalid_token");
  assertEquals(calls.length, 0);
});

Deno.test("platform admin override requires explicit target, reason, and correlation", async () => {
  const handler = createPlatformAdminOverrideHandler({
    authenticateClient: fakeAuth(),
    userClientForToken: () => fakeClient([]),
    serviceClient: fakeClient([]),
  });

  const response = await handler(request(validPayload({ reason: "" })));
  const body = await response.json();

  assertEquals(response.status, 400);
  assertEquals(body.error.code, "explicit_target_fields_required");
});

Deno.test("platform admin override calls attempted audit before mutation and succeeded terminal", async () => {
  const userCalls: RpcCall[] = [];
  const serviceCalls: RpcCall[] = [];
  const handler = createPlatformAdminOverrideHandler({
    authenticateClient: fakeAuth(),
    userClientForToken: () => fakeClient(userCalls),
    serviceClient: fakeClient(serviceCalls, {
      platform_admin_restore_family_delegation_access: {
        data: { id: "97400000-0000-0000-0000-000000000001", is_active: true },
      },
      finish_platform_admin_override_attempt: { data: "audit-id" },
    }),
  });

  const response = await handler(request(validPayload()));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(userCalls[0].fn, "begin_platform_admin_override_attempt");
  assertEquals(serviceCalls[0].fn, "platform_admin_restore_family_delegation_access");
  assertEquals(serviceCalls[1].fn, "finish_platform_admin_override_attempt");
  assertEquals(serviceCalls[1].args.p_event_type, "override.succeeded");
  assertExists(body.data);
});

Deno.test("platform admin override appends denied terminal after business denial", async () => {
  const serviceCalls: RpcCall[] = [];
  const handler = createPlatformAdminOverrideHandler({
    authenticateClient: fakeAuth(),
    userClientForToken: () => fakeClient([]),
    serviceClient: fakeClient(serviceCalls, {
      platform_admin_restore_family_delegation_access: {
        error: { message: "owner_consent_not_recorded" },
      },
      finish_platform_admin_override_attempt: { data: "terminal-id" },
    }),
  });

  const response = await handler(request(validPayload()));
  const body = await response.json();

  assertEquals(response.status, 403);
  assertEquals(body.error.code, "owner_consent_not_recorded");
  assertEquals(serviceCalls[1].fn, "finish_platform_admin_override_attempt");
  assertEquals(serviceCalls[1].args.p_event_type, "override.denied");
  assertEquals(serviceCalls[1].args.p_error_code, "owner_consent_not_recorded");
});

Deno.test("platform admin override reports retryable outcome failure after successful mutation", async () => {
  const handler = createPlatformAdminOverrideHandler({
    authenticateClient: fakeAuth(),
    userClientForToken: () => fakeClient([]),
    serviceClient: fakeClient([], {
      platform_admin_restore_family_delegation_access: { data: { is_active: true } },
      finish_platform_admin_override_attempt: {
        error: { message: "temporary_outcome_failure" },
      },
    }),
  });

  const response = await handler(request(validPayload()));
  const body = await response.json();

  assertEquals(response.status, 202);
  assertEquals(body.error.code, "override_outcome_write_failed");
});
