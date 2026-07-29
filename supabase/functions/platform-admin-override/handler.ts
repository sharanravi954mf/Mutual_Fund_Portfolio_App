export type RpcError = {
  code?: string;
  message?: string;
};

export type RpcResult<T = unknown> = {
  data: T | null;
  error: RpcError | null;
};

export type RpcClient = {
  rpc: (fn: string, args: Record<string, unknown>) => Promise<RpcResult>;
};

export type AuthClient = {
  auth: {
    getUser: (token: string) => Promise<{
      data: { user: { id: string } | null } | null;
      error: unknown;
    }>;
  };
};

export type HandlerDependencies = {
  authenticateClient: AuthClient;
  userClientForToken: (token: string) => RpcClient;
  serviceClient: RpcClient;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const knownDeniedCodes = new Set([
  "target_binding_mismatch",
  "owner_consent_not_recorded",
  "delegation_expired",
  "delegation_not_found",
  "override_attempt_not_found",
  "unsupported_override_action",
  "unsupported_entity_type",
]);

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function bearerToken(req: Request): string | null {
  const header = req.headers.get("authorization");
  if (header == null || !header.startsWith("Bearer ")) {
    return null;
  }

  const token = header.substring("Bearer ".length).trim();
  return token.length === 0 ? null : token;
}

function requiredString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function errorCode(error: RpcError | null): string {
  if (error == null) {
    return "unknown_error";
  }

  const message = error.message ?? "";
  const match = message.match(/([a-z][a-z0-9_]+)$/);
  return match?.[1] ?? error.code ?? "unknown_error";
}

async function appendTerminalOutcome(
  serviceClient: RpcClient,
  correlationId: string,
  eventType: "override.succeeded" | "override.denied" | "override.failed",
  code: string | null,
): Promise<RpcResult> {
  return await serviceClient.rpc("finish_platform_admin_override_attempt", {
    p_correlation_id: correlationId,
    p_event_type: eventType,
    p_error_code: code,
  });
}

async function callActionRpc(
  serviceClient: RpcClient,
  payload: Record<string, unknown>,
): Promise<RpcResult> {
  const action = payload.action;
  const rpcArgs = {
    p_correlation_id: payload.correlation_id,
    p_workspace_id: payload.workspace_id,
    p_delegation_id: payload.entity_id,
    p_owner_profile_id: payload.owner_profile_id,
    p_delegate_profile_id: payload.delegate_profile_id,
  };

  if (action === "family_delegation.read") {
    return await serviceClient.rpc(
      "platform_admin_read_family_delegation_support_projection",
      rpcArgs,
    );
  }

  if (action === "family_delegation.restore_access") {
    return await serviceClient.rpc(
      "platform_admin_restore_family_delegation_access",
      rpcArgs,
    );
  }

  return {
    data: null,
    error: { message: "unsupported_override_action" },
  };
}

export function createPlatformAdminOverrideHandler(
  deps: HandlerDependencies,
): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    if (req.method !== "POST") {
      return jsonResponse({ error: { code: "method_not_allowed" } }, 405);
    }

    const token = bearerToken(req);
    if (token == null) {
      return jsonResponse({ error: { code: "authorization_required" } }, 401);
    }

    const authentication = await deps.authenticateClient.auth.getUser(token);
    if (authentication.error != null || authentication.data?.user == null) {
      return jsonResponse({ error: { code: "invalid_token" } }, 401);
    }

    let payload: Record<string, unknown>;
    try {
      payload = await req.json();
    } catch (_error) {
      return jsonResponse({ error: { code: "invalid_json" } }, 400);
    }

    const workspaceId = requiredString(payload.workspace_id);
    const entityType = requiredString(payload.entity_type);
    const entityId = requiredString(payload.entity_id);
    const action = requiredString(payload.action);
    const reason = requiredString(payload.reason);
    const correlationId = requiredString(payload.correlation_id);
    const ownerProfileId = requiredString(payload.owner_profile_id);
    const delegateProfileId = requiredString(payload.delegate_profile_id);

    if (
      workspaceId == null || entityType == null || entityId == null ||
      action == null || reason == null || correlationId == null ||
      ownerProfileId == null || delegateProfileId == null
    ) {
      return jsonResponse({ error: { code: "explicit_target_fields_required" } }, 400);
    }

    const normalizedPayload = {
      workspace_id: workspaceId,
      entity_type: entityType,
      entity_id: entityId,
      action,
      reason,
      correlation_id: correlationId,
      owner_profile_id: ownerProfileId,
      delegate_profile_id: delegateProfileId,
    };

    const userClient = deps.userClientForToken(token);
    const attempt = await userClient.rpc("begin_platform_admin_override_attempt", {
      p_workspace_id: workspaceId,
      p_entity_type: entityType,
      p_entity_id: entityId,
      p_action: action,
      p_reason: reason,
      p_correlation_id: correlationId,
    });

    if (attempt.error != null) {
      return jsonResponse({ error: { code: errorCode(attempt.error) } }, 403);
    }

    const actionResult = await callActionRpc(deps.serviceClient, normalizedPayload);
    if (actionResult.error != null) {
      const code = errorCode(actionResult.error);
      const terminalType = knownDeniedCodes.has(code)
        ? "override.denied"
        : "override.failed";
      const terminal = await appendTerminalOutcome(
        deps.serviceClient,
        correlationId,
        terminalType,
        code,
      );

      if (terminal.error != null) {
        return jsonResponse({
          error: {
            code: "override_outcome_write_failed",
            original_error_code: code,
          },
        }, 202);
      }

      return jsonResponse({ error: { code } }, terminalType === "override.denied" ? 403 : 500);
    }

    const terminal = await appendTerminalOutcome(
      deps.serviceClient,
      correlationId,
      "override.succeeded",
      null,
    );

    if (terminal.error != null) {
      return jsonResponse({
        error: {
          code: "override_outcome_write_failed",
        },
      }, 202);
    }

    return jsonResponse({
      data: actionResult.data,
      correlation_id: correlationId,
    });
  };
}
