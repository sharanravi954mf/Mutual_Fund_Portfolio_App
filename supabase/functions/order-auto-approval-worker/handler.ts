import type {
  AutoApprovalRule,
  ClaimedOrderEvent,
  Decision,
  OrderRecord,
  Persistence,
  RpcError,
  RuleEvaluationContext,
} from "./types.ts";

export type HandlerDependencies = {
  internalToken: string;
  maxAttempts: number;
  leaseSeconds: number;
  persistence: Persistence;
  log?: (entry: Record<string, unknown>) => void;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const nonRetryableCodes = new Set([
  "idempotency_conflict",
  "stale_order_state",
  "event_not_found",
  "event_order_mismatch",
  "invalid_event_type",
  "invalid_event_entity_type",
  "invalid_correlation_id",
  "event_not_claimed",
  "event_already_completed",
  "claim_not_owned",
  "rule_not_found",
  "rule_inactive",
  "rule_workspace_mismatch",
  "rule_version_mismatch",
  "invalid_qualification_decision",
  "invalid_event_order_binding",
  "order_not_found",
]);

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function bearerToken(req: Request): string | null {
  const header = req.headers.get("authorization");
  if (header == null || !header.startsWith("Bearer ")) return null;
  const token = header.substring("Bearer ".length).trim();
  return token.length === 0 ? null : token;
}

function requiredUuid(value: unknown): string | null {
  return typeof value === "string" && uuidPattern.test(value) ? value : null;
}

function numeric(value: string | number | null): number | null {
  if (value == null) return null;
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function errorCode(error: RpcError | null): string {
  if (error == null) return "unknown_error";
  const message = error.message ?? "";
  const match = message.match(/([a-z][a-z0-9_]+)$/);
  return match?.[1] ?? error.code ?? "unknown_error";
}

function payloadOrderId(event: ClaimedOrderEvent): string | null {
  const value = event.payload?.order_id;
  return typeof value === "string" ? value : null;
}

function ruleMatches(
  order: OrderRecord,
  rule: AutoApprovalRule,
  context: RuleEvaluationContext,
): boolean {
  if (!rule.is_active) return false;
  if (rule.workspace_id !== order.workspace_id) return false;
  if (rule.transaction_type !== order.type) return false;
  if (rule.trusted_client_only && !context.investor_is_trusted) return false;

  const now = Date.now();
  if (Date.parse(rule.effective_from) > now) return false;
  if (rule.effective_to != null && Date.parse(rule.effective_to) <= now) {
    return false;
  }

  const amount = numeric(order.amount);
  if (amount == null) return false;

  const min = numeric(rule.min_amount);
  if (min != null && amount < min) return false;

  const max = numeric(rule.max_amount);
  if (max != null && amount > max) return false;

  if (
    rule.category_restrictions != null && rule.category_restrictions.length > 0
  ) {
    if (
      context.scheme_category == null ||
      !rule.category_restrictions.includes(context.scheme_category)
    ) {
      return false;
    }
  }

  return true;
}

function decide(
  order: OrderRecord,
  rules: AutoApprovalRule[],
  context: RuleEvaluationContext,
): Decision {
  const matchingRule = rules.find((rule) => ruleMatches(order, rule, context));
  if (matchingRule == null) {
    return { decision: "pending_review", rule_id: null, rule_version: null };
  }

  return {
    decision: "auto_approved",
    rule_id: matchingRule.id,
    rule_version: matchingRule.rule_version,
  };
}

async function recordFailure(
  deps: HandlerDependencies,
  input: {
    event: ClaimedOrderEvent;
    errorCode: string;
    errorMessage?: string | null;
    maxAttempts: number;
    retryable?: boolean;
    outcome?: string;
  },
): Promise<Response> {
  const eventOutboxId = input.event.event_outbox_id;
  const retryable = input.retryable ?? !nonRetryableCodes.has(input.errorCode);

  if (eventOutboxId == null) {
    return jsonResponse({ error: { code: input.errorCode } }, 422);
  }

  let failure;
  try {
    failure = await deps.persistence.recordFailure({
      eventOutboxId,
      claimToken: input.event.claim_token ?? "",
      errorCode: input.errorCode,
      errorMessage: input.errorMessage ?? null,
      retryable,
      maxAttempts: input.maxAttempts,
    });
  } catch (error) {
    const code = safeErrorCode(error, "failure_recording_failed");
    logOutcome(
      deps,
      input.event,
      input.errorCode,
      input.outcome ?? "failure_recording_failed",
    );
    return jsonResponse({
      error: {
        code: "failure_recording_failed",
        original_error_code: input.errorCode,
        failure_error_code: code,
      },
    }, 500);
  }

  if (failure.error != null) {
    const code = errorCode(failure.error);
    logOutcome(
      deps,
      input.event,
      input.errorCode,
      input.outcome ?? "failure_recording_failed",
    );
    return jsonResponse({
      error: {
        code: "failure_recording_failed",
        original_error_code: input.errorCode,
        failure_error_code: code,
      },
    }, 500);
  }

  const outcome = input.outcome ??
    (retryable ? "retry_scheduled" : "terminal_failure");
  logOutcome(deps, input.event, input.errorCode, outcome);
  return jsonResponse(
    { error: { code: input.errorCode }, data: { outcome } },
    retryable ? 202 : 422,
  );
}

function logOutcome(
  deps: HandlerDependencies,
  event: ClaimedOrderEvent,
  code: string | null,
  outcome: string,
): void {
  deps.log?.({
    event_outbox_id: event.event_outbox_id,
    order_id: event.order_id,
    correlation_id: event.correlation_id,
    attempt: event.attempt,
    claim_token: event.claim_token,
    outcome,
    error_code: code,
  });
}

function safeErrorCode(
  error: unknown,
  fallback = "worker_unexpected_error",
): string {
  if (error instanceof Error) {
    const match = error.message.match(/([a-z][a-z0-9_]+)$/);
    return match?.[1] ?? fallback;
  }
  return fallback;
}

export function createOrderAutoApprovalWorkerHandler(
  deps: HandlerDependencies,
): (req: Request) => Promise<Response> {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response("ok");
    if (req.method !== "POST") {
      return jsonResponse({ error: { code: "method_not_allowed" } }, 405);
    }

    if (
      deps.internalToken.trim().length === 0 ||
      bearerToken(req) !== deps.internalToken
    ) {
      return jsonResponse({ error: { code: "not_authorized" } }, 403);
    }

    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch (_error) {
      body = {};
    }

    const eventOutboxId = body.event_outbox_id == null
      ? null
      : requiredUuid(body.event_outbox_id);
    if (body.event_outbox_id != null && eventOutboxId == null) {
      return jsonResponse({ error: { code: "invalid_event_outbox_id" } }, 400);
    }

    let event: ClaimedOrderEvent;
    try {
      event = await deps.persistence.claimEvent({
        eventOutboxId,
        maxAttempts: deps.maxAttempts,
        leaseSeconds: deps.leaseSeconds,
      });
    } catch (error) {
      const code = safeErrorCode(error, "event_claim_failed");
      deps.log?.({
        event_outbox_id: eventOutboxId,
        order_id: null,
        correlation_id: eventOutboxId,
        attempt: 0,
        claim_token: null,
        outcome: "claim_failed",
        error_code: code,
      });
      return jsonResponse({ error: { code: "event_claim_failed" } }, 500);
    }

    if (event.claim_state === "no_event") {
      logOutcome(deps, event, null, "no_event");
      return jsonResponse({ data: { outcome: "no_event" } });
    }
    if (event.claim_state === "not_found") {
      logOutcome(deps, event, "event_not_found", "not_found");
      return jsonResponse({ error: { code: "event_not_found" } }, 404);
    }
    if (event.claim_state === "active_in_progress") {
      logOutcome(deps, event, "event_in_progress", "active_in_progress");
      return jsonResponse({ error: { code: "event_in_progress" } }, 409);
    }
    if (event.claim_state === "terminal_failed") {
      logOutcome(deps, event, "event_retry_exhausted", "terminal_failed");
      return jsonResponse({ error: { code: "event_retry_exhausted" } }, 409);
    }
    if (event.claim_state === "invalid_event") {
      logOutcome(deps, event, "invalid_event_type", "invalid_event");
      return jsonResponse({ error: { code: "invalid_event_type" } }, 422);
    }
    if (event.claim_state === "completed_replay") {
      logOutcome(deps, event, null, "idempotent_replay");
      return jsonResponse({
        data: {
          outcome: "idempotent_replay",
          correlation_id: event.correlation_id,
        },
      });
    }

    if (event.event_type !== "order.created") {
      return await recordFailure(deps, {
        event,
        errorCode: "invalid_event_type",
        errorMessage: event.event_type,
        retryable: false,
        maxAttempts: deps.maxAttempts,
      });
    }

    if (event.entity_type !== "order_request") {
      return await recordFailure(deps, {
        event,
        errorCode: "invalid_event_entity_type",
        errorMessage: event.entity_type,
        retryable: false,
        maxAttempts: deps.maxAttempts,
      });
    }

    if (
      event.correlation_id == null ||
      event.correlation_id !== event.event_outbox_id
    ) {
      return await recordFailure(deps, {
        event,
        errorCode: "invalid_correlation_id",
        retryable: false,
        maxAttempts: deps.maxAttempts,
      });
    }

    const orderId = event.order_id;
    if (orderId == null || !uuidPattern.test(orderId)) {
      return await recordFailure(deps, {
        event,
        errorCode: "invalid_event_order_binding",
        retryable: false,
        maxAttempts: deps.maxAttempts,
      });
    }

    const payloadBoundOrderId = payloadOrderId(event);
    if (payloadBoundOrderId != null && payloadBoundOrderId !== orderId) {
      return await recordFailure(deps, {
        event,
        errorCode: "event_order_mismatch",
        errorMessage:
          `payload order ${payloadBoundOrderId} does not match event entity ${orderId}`,
        retryable: false,
        maxAttempts: deps.maxAttempts,
      });
    }

    let order: OrderRecord | null;
    try {
      order = await deps.persistence.loadOrder(orderId);
    } catch (error) {
      return await recordFailure(deps, {
        event,
        errorCode: safeErrorCode(error, "order_load_failed"),
        retryable: true,
        maxAttempts: deps.maxAttempts,
      });
    }
    if (order == null) {
      return await recordFailure(deps, {
        event,
        errorCode: "order_not_found",
        retryable: false,
        maxAttempts: deps.maxAttempts,
      });
    }

    if (order.status !== "pending_qualification") {
      const outcome =
        order.auto_approval_correlation_id === event.correlation_id
          ? "idempotent_replay"
          : "stale";
      if (outcome === "idempotent_replay") {
        logOutcome(deps, event, null, outcome);
        return jsonResponse({
          data: { outcome, correlation_id: event.correlation_id },
        });
      }
      return await recordFailure(deps, {
        event,
        errorCode: "stale_order_state",
        errorMessage: order.status,
        retryable: false,
        maxAttempts: deps.maxAttempts,
        outcome,
      });
    }

    let context: RuleEvaluationContext;
    try {
      context = await deps.persistence.loadRuleEvaluationContext({
        workspaceId: order.workspace_id,
        investorProfileId: order.investor_profile_id,
        schemeCode: order.scheme_code,
      });
    } catch (error) {
      return await recordFailure(deps, {
        event,
        errorCode: safeErrorCode(error, "rule_context_load_failed"),
        retryable: true,
        maxAttempts: deps.maxAttempts,
      });
    }

    let rules: AutoApprovalRule[];
    try {
      rules = await deps.persistence.listRules({
        workspaceId: order.workspace_id,
        transactionType: order.type,
      });
    } catch (error) {
      return await recordFailure(deps, {
        event,
        errorCode: safeErrorCode(error, "rule_load_failed"),
        retryable: true,
        maxAttempts: deps.maxAttempts,
      });
    }
    const decision = decide(order, rules, context);

    if (event.claim_token == null) {
      return await recordFailure(deps, {
        event,
        errorCode: "claim_token_required",
        retryable: false,
        maxAttempts: deps.maxAttempts,
      });
    }

    let applied;
    try {
      applied = await deps.persistence.applyDecision({
        orderId,
        decision: decision.decision,
        ruleId: decision.rule_id,
        ruleVersion: decision.rule_version,
        correlationId: event.correlation_id,
        claimToken: event.claim_token,
      });
    } catch (error) {
      return await recordFailure(deps, {
        event,
        errorCode: safeErrorCode(error, "decision_apply_failed"),
        retryable: true,
        maxAttempts: deps.maxAttempts,
      });
    }

    if (applied.error != null) {
      const code = errorCode(applied.error);
      return await recordFailure(deps, {
        event,
        errorCode: code,
        errorMessage: applied.error.message ?? null,
        retryable: !nonRetryableCodes.has(code),
        maxAttempts: deps.maxAttempts,
        outcome: code === "stale_order_state" ? "stale" : undefined,
      });
    }

    logOutcome(deps, event, null, decision.decision);
    return jsonResponse({
      data: {
        outcome: decision.decision,
        event_outbox_id: event.event_outbox_id,
        order_id: orderId,
        correlation_id: event.correlation_id,
        attempt: event.attempt,
        rule_id: decision.rule_id,
        rule_version: decision.rule_version,
      },
    });
  };
}
