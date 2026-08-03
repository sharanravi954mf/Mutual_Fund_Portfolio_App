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
};

type FailureCall = {
  eventOutboxId: string;
  workerId: string;
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
  recordFailureError?: string;
  applyCalls?: ApplyCall[];
  failureCalls?: FailureCall[];
  logs?: Record<string, unknown>[];
} = {}) {
  const applyCalls = options.applyCalls ?? [];
  const failureCalls = options.failureCalls ?? [];
  const logs = options.logs ?? [];
  const persistence: Persistence = {
    claimEvent: async () => options.event ?? claimedEvent(),
    loadOrder: async () =>
      options.loadedOrder === undefined ? order() : options.loadedOrder,
    listRules: async () => options.rules ?? [rule()],
    applyDecision: async (input) => {
      applyCalls.push(input);
      if (options.applyError != null) {
        return { data: null, error: { message: options.applyError } };
      }
      return { data: order({ status: input.decision }), error: null };
    },
    recordFailure: async (input) => {
      failureCalls.push(input);
      if (options.recordFailureError != null) {
        return { error: { message: options.recordFailureError } };
      }
      return { error: null };
    },
  };

  return {
    handler: createOrderAutoApprovalWorkerHandler({
      internalToken: TOKEN,
      persistence,
      workerId: () => WORKER_ID,
      log: (entry) => logs.push(entry),
    }),
    applyCalls,
    failureCalls,
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

  const response = await handler(request({ max_attempts: 4 }));
  const body = await response.json();

  assertEquals(response.status, 202);
  assertEquals(body.error.code, "temporary_rule_repository_error");
  assertEquals(body.data.outcome, "retry_scheduled");
  assertEquals(applyCalls.length, 1);
  assertEquals(failureCalls[0].eventOutboxId, EVENT_ID);
  assertEquals(failureCalls[0].workerId, WORKER_ID);
  assertEquals(failureCalls[0].retryable, true);
  assertEquals(failureCalls[0].maxAttempts, 4);
});

Deno.test("non-order outbox events are terminally rejected", async () => {
  const { handler, applyCalls, failureCalls } = deps({
    event: claimedEvent({ event_type: "statement.imported" }),
  });

  const response = await handler(request());
  const body = await response.json();

  assertEquals(response.status, 422);
  assertEquals(body.error.code, "invalid_event_type");
  assertEquals(applyCalls.length, 0);
  assertEquals(failureCalls[0].retryable, false);
});

Deno.test("test fixtures use UUID-shaped event-bound correlations", () => {
  assert(EVENT_ID.match(/^[0-9a-f-]{36}$/));
  assertEquals(claimedEvent().correlation_id, claimedEvent().event_outbox_id);
});
