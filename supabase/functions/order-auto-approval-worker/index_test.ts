import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { createOrderAutoApprovalWorkerHandler } from "./handler.ts";
import type {
  AutoApprovalRule,
  ClaimedOrderEvent,
  OrderRecord,
  Persistence,
} from "./types.ts";

const TOKEN = "issue-33-worker-token";
const WORKER_ID = "a3300000-0000-4000-8000-000000000001";
const CLAIM_TOKEN = "a3300000-0000-4000-8000-000000000901";
const EVENT_ID = "a3300000-0000-4000-8000-000000000101";
const RETRY_EVENT_ID = "a3300000-0000-4000-8000-000000000102";
const STALE_EVENT_ID = "a3300000-0000-4000-8000-000000000103";
const ORDER_ID = "a3300000-0000-4000-8000-000000000201";
const OTHER_ORDER_ID = "a3300000-0000-4000-8000-000000000202";
const WORKSPACE_ID = "a3300000-0000-4000-8000-000000000301";
const INVESTOR_ID = "a3300000-0000-4000-8000-000000000401";
const RULE_ID = "a3300000-0000-4000-8000-000000000501";

type ApplyCall = {
  orderId: string;
  decision: string;
  ruleId: string | null;
  ruleVersion: number | null;
  correlationId: string;
  claimToken: string;
};

type FailureCall = {
  eventOutboxId: string;
  claimToken: string;
  errorCode: string;
  errorMessage: string | null;
  retryable: boolean;
  maxAttempts: number;
};

function claimedEvent(
  options: Partial<ClaimedOrderEvent> = {},
): ClaimedOrderEvent {
  return {
    event_outbox_id: EVENT_ID,
    order_id: ORDER_ID,
    payload: { order_id: ORDER_ID, category: "Equity" },
    correlation_id: EVENT_ID,
    attempt: 1,
    claim_state: "newly_claimed",
    event_status: "processing",
    event_type: "order.created",
    entity_type: "order_request",
    claim_token: CLAIM_TOKEN,
    claim_expires_at: "2026-08-03T20:30:00.000Z",
    ...options,
  };
}

function order(options: Partial<OrderRecord> = {}): OrderRecord {
  return {
    id: ORDER_ID,
    workspace_id: WORKSPACE_ID,
    investor_profile_id: INVESTOR_ID,
    scheme_code: "SCH-ISSUE-33",
    type: "buy",
    amount: 5000,
    units: null,
    status: "pending_qualification",
    auto_approval_correlation_id: null,
    ...options,
  };
}

function rule(options: Partial<AutoApprovalRule> = {}): AutoApprovalRule {
  return {
    id: RULE_ID,
    workspace_id: WORKSPACE_ID,
    transaction_type: "buy",
    min_amount: 0,
    max_amount: 10000,
    trusted_client_only: false,
    category_restrictions: null,
    effective_from: "2026-08-01T00:00:00.000Z",
    effective_to: null,
    is_active: true,
    rule_version: 7,
    ...options,
  };
}

function request(body: Record<string, unknown> = {}): Request {
  return new Request("http://localhost/order-auto-approval-worker", {
    method: "POST",
    headers: {
      authorization: `Bearer ${TOKEN}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function deps(options: {
  event?: ClaimedOrderEvent;
  loadedOrder?: OrderRecord | null;
  rules?: AutoApprovalRule[];
  applyError?: string;
  applyThrowsError?: string;
  recordFailureError?: string;
  loadOrderError?: string;
  loadContextError?: string;
  listRulesError?: string;
  investorIsTrusted?: boolean;
  schemeCategory?: string | null;
  applyCalls?: ApplyCall[];
  failureCalls?: FailureCall[];
  claimCalls?: {
    eventOutboxId: string | null;
    maxAttempts: number;
    leaseSeconds: number;
  }[];
  logs?: Record<string, unknown>[];
} = {}) {
  const applyCalls = options.applyCalls ?? [];
  const failureCalls = options.failureCalls ?? [];
  const claimCalls = options.claimCalls ?? [];
  const logs = options.logs ?? [];
  const persistence: Persistence = {
    claimEvent: (input) => {
      claimCalls.push(input);
      return Promise.resolve(options.event ?? claimedEvent());
    },
    loadOrder: () => {
      if (options.loadOrderError != null) {
        throw new Error(options.loadOrderError);
      }
      return Promise.resolve(
        options.loadedOrder === undefined ? order() : options.loadedOrder,
      );
    },
    loadRuleEvaluationContext: () => {
      if (options.loadContextError != null) {
        throw new Error(options.loadContextError);
      }
      return Promise.resolve({
        investor_is_trusted: options.investorIsTrusted ?? false,
        scheme_category: options.schemeCategory === undefined
          ? "Equity"
          : options.schemeCategory,
      });
    },
    listRules: () => {
      if (options.listRulesError != null) {
        throw new Error(options.listRulesError);
      }
      return Promise.resolve(options.rules ?? [rule()]);
    },
    applyDecision: (input) => {
      applyCalls.push(input);
      if (options.applyThrowsError != null) {
        throw new Error(options.applyThrowsError);
      }
      if (options.applyError != null) {
        return Promise.resolve({
          data: null,
          error: { message: options.applyError },
        });
      }
      return Promise.resolve({
        data: order({ status: input.decision }),
        error: null,
      });
    },
    recordFailure: (input) => {
      failureCalls.push(input);
      if (options.recordFailureError != null) {
        return Promise.resolve({
          error: { message: options.recordFailureError },
        });
      }
      return Promise.resolve({ error: null });
    },
  };

  return {
    handler: createOrderAutoApprovalWorkerHandler({
      internalToken: TOKEN,
      maxAttempts: 3,
      leaseSeconds: 120,
      persistence,
      log: (entry) => logs.push(entry),
    }),
    applyCalls,
    failureCalls,
    claimCalls,
    logs,
  };
}

Deno.test("order auto-approval worker requires internal bearer token", async () => {
  const { handler, applyCalls } = deps();
  const response = await handler(
    new Request("http://localhost", { method: "POST" }),
  );
  const body = await response.json();

  assertEquals(response.status, 403);
  assertEquals(body.error.code, "not_authorized");
  assertEquals(applyCalls.length, 0);
});

Deno.test("auto_approved decision uses event_outbox id as UUID correlation and validated rule payload", async () => {
  const { handler, applyCalls, logs } = deps();

  const response = await handler(
    request({ event_outbox_id: EVENT_ID, worker_id: WORKER_ID }),
  );
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.outcome, "auto_approved");
  assertEquals(body.data.correlation_id, EVENT_ID);
  assertEquals(body.data.rule_id, RULE_ID);
  assertEquals(body.data.rule_version, 7);
  assertEquals(applyCalls, [{
    orderId: ORDER_ID,
    decision: "auto_approved",
    ruleId: RULE_ID,
    ruleVersion: 7,
    correlationId: EVENT_ID,
    claimToken: CLAIM_TOKEN,
  }]);
  assertEquals(logs[0].event_outbox_id, EVENT_ID);
  assertEquals(logs[0].correlation_id, EVENT_ID);
  assertEquals(logs[0].attempt, 1);
  assertEquals(logs[0].outcome, "auto_approved");
});

Deno.test("pending_review decision sends null rule id and rule version", async () => {
  const { handler, applyCalls } = deps({ rules: [] });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.outcome, "pending_review");
  assertEquals(body.data.rule_id, null);
  assertEquals(body.data.rule_version, null);
  assertEquals(applyCalls[0].decision, "pending_review");
  assertEquals(applyCalls[0].ruleId, null);
  assertEquals(applyCalls[0].ruleVersion, null);
  assertEquals(applyCalls[0].correlationId, EVENT_ID);
});

Deno.test("retry reuses the same event-bound correlation id and logs deterministic attempt", async () => {
  const { handler, applyCalls, logs } = deps({
    event: claimedEvent({
      event_outbox_id: RETRY_EVENT_ID,
      correlation_id: RETRY_EVENT_ID,
      attempt: 2,
      claim_state: "retry_claimed",
    }),
  });

  const response = await handler(request({ event_outbox_id: RETRY_EVENT_ID }));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.correlation_id, RETRY_EVENT_ID);
  assertEquals(body.data.attempt, 2);
  assertEquals(applyCalls[0].correlationId, RETRY_EVENT_ID);
  assertEquals(logs[0].attempt, 2);
});

Deno.test("event/order payload mismatch is rejected before decision write", async () => {
  const { handler, applyCalls, failureCalls } = deps({
    event: claimedEvent({
      payload: { order_id: OTHER_ORDER_ID },
    }),
  });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 422);
  assertEquals(body.error.code, "event_order_mismatch");
  assertEquals(applyCalls.length, 0);
  assertEquals(failureCalls[0].eventOutboxId, EVENT_ID);
  assertEquals(failureCalls[0].errorCode, "event_order_mismatch");
  assertEquals(failureCalls[0].claimToken, CLAIM_TOKEN);
  assertEquals(failureCalls[0].retryable, false);
});

Deno.test("same completed event replay is idempotent and skips decision/audit writes", async () => {
  const { handler, applyCalls, failureCalls } = deps({
    event: claimedEvent({
      claim_state: "completed_replay",
      event_status: "completed",
      attempt: 1,
    }),
  });

  const response = await handler(request({ event_outbox_id: EVENT_ID }));
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.outcome, "idempotent_replay");
  assertEquals(body.data.correlation_id, EVENT_ID);
  assertEquals(applyCalls.length, 0);
  assertEquals(failureCalls.length, 0);
});

Deno.test("different event against resolved order is classified stale without changing decision", async () => {
  const { handler, applyCalls, failureCalls } = deps({
    event: claimedEvent({
      event_outbox_id: STALE_EVENT_ID,
      correlation_id: STALE_EVENT_ID,
      attempt: 1,
    }),
    loadedOrder: order({
      status: "auto_approved",
      auto_approval_correlation_id: EVENT_ID,
    }),
  });

  const response = await handler(request({ event_outbox_id: STALE_EVENT_ID }));
  const body = await response.json();

  assertEquals(response.status, 422);
  assertEquals(body.error.code, "stale_order_state");
  assertEquals(body.data.outcome, "stale");
  assertEquals(applyCalls.length, 0);
  assertEquals(failureCalls[0].eventOutboxId, STALE_EVENT_ID);
  assertEquals(failureCalls[0].retryable, false);
});

Deno.test("active in-progress claim prevents duplicate worker processing", async () => {
  const { handler, applyCalls, failureCalls } = deps({
    event: claimedEvent({ claim_state: "active_in_progress" }),
  });

  const response = await handler(request({ event_outbox_id: EVENT_ID }));
  const body = await response.json();

  assertEquals(response.status, 409);
  assertEquals(body.error.code, "event_in_progress");
  assertEquals(applyCalls.length, 0);
  assertEquals(failureCalls.length, 0);
});

Deno.test("retryable decision errors are recorded for deterministic retry", async () => {
  const { handler, applyCalls, failureCalls } = deps({
    applyError: "temporary_rule_repository_error",
  });

  const response = await handler(
    request({ max_attempts: 4, worker_id: WORKER_ID }),
  );
  const body = await response.json();

  assertEquals(response.status, 202);
  assertEquals(body.error.code, "temporary_rule_repository_error");
  assertEquals(body.data.outcome, "retry_scheduled");
  assertEquals(applyCalls.length, 1);
  assertEquals(failureCalls[0].eventOutboxId, EVENT_ID);
  assertEquals(failureCalls[0].claimToken, CLAIM_TOKEN);
  assertEquals(failureCalls[0].retryable, true);
  assertEquals(failureCalls[0].maxAttempts, 3);
});

Deno.test("non-order outbox events are terminally rejected", async () => {
  const { handler, applyCalls, failureCalls } = deps({
    event: claimedEvent({
      claim_state: "invalid_event",
      event_type: "statement.imported",
    }),
  });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 422);
  assertEquals(body.error.code, "invalid_event_type");
  assertEquals(applyCalls.length, 0);
  assertEquals(failureCalls.length, 0);
});

Deno.test("request body cannot override server retry or lease policy", async () => {
  const { handler, claimCalls } = deps();

  const response = await handler(request({
    event_outbox_id: EVENT_ID,
    worker_id: WORKER_ID,
    max_attempts: 9,
    lease_seconds: 999,
  }));

  assertEquals(response.status, 200);
  assertEquals(claimCalls[0], {
    eventOutboxId: EVENT_ID,
    maxAttempts: 3,
    leaseSeconds: 120,
  });
});

Deno.test("trusted-client-only rule auto-approves only from authoritative trust context", async () => {
  const trustedRule = rule({ trusted_client_only: true });
  const trusted = deps({ rules: [trustedRule], investorIsTrusted: true });
  const trustedResponse = await trusted.handler(request());
  const trustedBody = await trustedResponse.json();

  assertEquals(trustedResponse.status, 200);
  assertEquals(trustedBody.data.outcome, "auto_approved");
  assertEquals(trusted.applyCalls[0].ruleId, RULE_ID);

  const untrusted = deps({ rules: [trustedRule], investorIsTrusted: false });
  const untrustedResponse = await untrusted.handler(request());
  const untrustedBody = await untrustedResponse.json();

  assertEquals(untrustedResponse.status, 200);
  assertEquals(untrustedBody.data.outcome, "pending_review");
  assertEquals(untrusted.applyCalls[0].ruleId, null);
});

Deno.test("cross-workspace trust cannot satisfy a trusted-client-only rule", async () => {
  const { handler, applyCalls } = deps({
    rules: [rule({ trusted_client_only: true })],
    investorIsTrusted: false,
  });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.outcome, "pending_review");
  assertEquals(applyCalls[0].ruleId, null);
});

Deno.test("category rules use database context and ignore event payload category", async () => {
  const { handler, applyCalls } = deps({
    event: claimedEvent({ payload: { order_id: ORDER_ID, category: "Debt" } }),
    rules: [rule({ category_restrictions: ["Equity"] })],
    schemeCategory: "Equity",
  });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.outcome, "auto_approved");
  assertEquals(applyCalls[0].ruleId, RULE_ID);
});

Deno.test("category mismatch falls back to pending_review", async () => {
  const { handler, applyCalls } = deps({
    rules: [rule({ category_restrictions: ["Equity"] })],
    schemeCategory: "Debt",
  });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.outcome, "pending_review");
  assertEquals(applyCalls[0].ruleId, null);
});

Deno.test("future and expired rules do not match", async () => {
  const { handler, applyCalls } = deps({
    rules: [
      rule({ effective_from: "2999-01-01T00:00:00.000Z" }),
      rule({ effective_to: "2000-01-01T00:00:00.000Z" }),
    ],
  });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 200);
  assertEquals(body.data.outcome, "pending_review");
  assertEquals(applyCalls[0].ruleId, null);
});

Deno.test("unexpected load failures are recorded as retryable claim failures", async () => {
  const { handler, failureCalls, logs } = deps({
    loadContextError: "database_unavailable",
  });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 202);
  assertEquals(body.error.code, "database_unavailable");
  assertEquals(failureCalls[0].retryable, true);
  assertEquals(failureCalls[0].claimToken, CLAIM_TOKEN);
  assertEquals(logs[0].claim_token, CLAIM_TOKEN);
});

Deno.test("unexpected order load failures are recorded as retryable claim failures", async () => {
  const { handler, failureCalls } = deps({
    loadOrderError: "order_repository_unavailable",
  });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 202);
  assertEquals(body.error.code, "order_repository_unavailable");
  assertEquals(failureCalls[0].retryable, true);
  assertEquals(failureCalls[0].claimToken, CLAIM_TOKEN);
});

Deno.test("unexpected rule load failures are recorded as retryable claim failures", async () => {
  const { handler, failureCalls } = deps({
    listRulesError: "rule_repository_unavailable",
  });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 202);
  assertEquals(body.error.code, "rule_repository_unavailable");
  assertEquals(failureCalls[0].retryable, true);
  assertEquals(failureCalls[0].claimToken, CLAIM_TOKEN);
});

Deno.test("unexpected decision apply throws are recorded as retryable claim failures", async () => {
  const { handler, failureCalls } = deps({
    applyThrowsError: "decision_repository_unavailable",
  });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 202);
  assertEquals(body.error.code, "decision_repository_unavailable");
  assertEquals(failureCalls[0].retryable, true);
  assertEquals(failureCalls[0].claimToken, CLAIM_TOKEN);
});

Deno.test("failure recording outage is surfaced with structured fallback log", async () => {
  const { handler, failureCalls, logs } = deps({
    loadOrderError: "order_repository_unavailable",
    recordFailureError: "failure_repository_unavailable",
  });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 500);
  assertEquals(body.error.code, "failure_recording_failed");
  assertEquals(body.error.original_error_code, "order_repository_unavailable");
  assertEquals(body.error.failure_error_code, "failure_repository_unavailable");
  assertEquals(failureCalls[0].claimToken, CLAIM_TOKEN);
  assertEquals(logs[0].outcome, "failure_recording_failed");
  assertEquals(logs[0].claim_token, CLAIM_TOKEN);
});

Deno.test("test fixtures use UUID-shaped event-bound correlations", () => {
  assert(EVENT_ID.match(/^[0-9a-f-]{36}$/));
  assertEquals(claimedEvent().correlation_id, claimedEvent().event_outbox_id);
});
