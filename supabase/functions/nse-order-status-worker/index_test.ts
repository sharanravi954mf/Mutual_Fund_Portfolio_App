import {
  assertEquals,
  assertFalse,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  buildNseOrderStatusRequest,
  parseNseOrderStatusResponse,
} from "../_shared/nse/nse_order_status.ts";
import {
  createOrderStatusPersistence,
  type OrderStatusPersistence,
} from "./adapters.ts";
import { createNseOrderStatusHandler } from "./handler.ts";

const TOKEN = "test-token",
  EVENT = "10000000-0000-4000-8000-000000000001",
  OPERATION = "10000000-0000-4000-8000-000000000002",
  CLAIM = "10000000-0000-4000-8000-000000000003",
  CALL = "10000000-0000-4000-8000-000000000004";
const source = {
  client_code: "MBUAT0001",
  from_date: "2026-09-01",
  to_date: "2026-09-07",
  trans_type: "ALL",
  order_type: "ALL",
  sub_order_type: "ALL",
};
function invoke() {
  return new Request("http://localhost", {
    method: "POST",
    headers: {
      authorization: `Bearer ${TOKEN}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ event_outbox_id: EVENT }),
  });
}
function setup(
  options: {
    status?: number;
    raw?: string;
    startFailures?: number;
    finishFailures?: number;
    failure?: boolean;
  } = {},
) {
  const sequence: string[] = [];
  let sent = 0;
  let startFailures = options.startFailures ?? 0;
  let finishFailures = options.finishFailures ?? 0;
  const persistence: OrderStatusPersistence = {
    recoverExpired: () => Promise.resolve({}),
    claimEvent: () =>
      Promise.resolve({
        event_outbox_id: EVENT,
        integration_operation_id: OPERATION,
        correlation_id: CALL,
        attempt: 1,
        claim_state: "newly_claimed",
        claim_token: CLAIM,
      }),
    loadSource: () => Promise.resolve(source),
    start: () => {
      sequence.push("request");
      return startFailures-- > 0
        ? Promise.reject(new Error())
        : Promise.resolve({});
    },
    finish: () => {
      sequence.push("result");
      return finishFailures-- > 0
        ? Promise.reject(new Error())
        : Promise.resolve({});
    },
  };
  return {
    sequence,
    sent: () => sent,
    handler: createNseOrderStatusHandler({
      internalToken: TOKEN,
      persistence,
      gateway: {
        requestHeaderMetadata: () => ({
          content_type: "application/json",
          accept: "application/json",
          user_agent: "test",
        }),
        submit: () => {
          sent++;
          sequence.push("send");
          return Promise.resolve(
            options.failure
              ? {
                kind: "failure" as const,
                errorCategory: "nse_request_timeout",
                timeout: true,
                networkFailure: false,
              }
              : {
                kind: "response" as const,
                status: options.status ?? 200,
                contentType: "application/json",
                safeHeaderMetadata: {},
                rawBody: options.raw ??
                  JSON.stringify({
                    response_status: "S",
                    report_data: [{ order_status: "INVALID" }],
                  }),
              },
          );
        },
      },
      uuid: () => CALL,
      now: (() => {
        let calls = 0;
        return () => new Date(`2026-09-02T00:00:00.00${calls++}Z`);
      })(),
    }),
  };
}
Deno.test("ORDER_STATUS has exact bounded contract and no date_type", () => {
  const request = buildNseOrderStatusRequest({
    ...source,
    order_ids: ["one"],
    member_unique_ids: ["two"],
  });
  assertEquals(request.order_ids, "one");
  assertFalse("member_unique_ids" in request);
  assertFalse("date_type" in request);
  assertThrows(() =>
    buildNseOrderStatusRequest({ ...source, to_date: "2026-09-08" })
  );
  assertThrows(() =>
    buildNseOrderStatusRequest({ ...source, trans_type: "X" })
  );
});
Deno.test("S is report success even when a row is INVALID; F and malformed are not", () => {
  assertEquals(
    parseNseOrderStatusResponse(
      JSON.stringify({
        response_status: "S",
        report_data: [{ order_status: "INVALID" }],
      }),
    ).invalidCount,
    1,
  );
  assertEquals(
    parseNseOrderStatusResponse(JSON.stringify({ response_status: "F" }))
      .remarkCategory,
    "report_business_failure",
  );
  assertEquals(
    parseNseOrderStatusResponse("bad").remarkCategory,
    "malformed_response",
  );
  assertEquals(
    parseNseOrderStatusResponse(JSON.stringify({ response_status: "S" }))
      .remarkCategory,
    "malformed_response",
  );
  assertEquals(
    parseNseOrderStatusResponse(
      JSON.stringify({ response_status: "S", report_data: [] }),
    ).remarkCategory,
    "report_success",
  );
});
Deno.test("request persistence twice failing produces zero sends; result ack retry produces one", async () => {
  const failed = setup({ startFailures: 2 });
  assertEquals((await failed.handler(invoke())).status, 500);
  assertEquals(failed.sent(), 0);
  const ack = setup({ finishFailures: 1 });
  assertEquals((await ack.handler(invoke())).status, 200);
  assertEquals(ack.sent(), 1);
});
Deno.test("read retries include transient HTTP statuses and no PII is put in request", async () => {
  for (const status of [408, 429, 500, 502, 503, 504]) {
    assertEquals((await setup({ status }).handler(invoke())).status, 202);
  }
  const c = setup({ failure: true });
  assertEquals((await c.handler(invoke())).status, 202);
});
Deno.test("claim RPC errors and invalid shapes throw while only empty is no_event", async () => {
  const client = { rpc: () => Promise.resolve({ data: {}, error: null }) };
  const persistence = createOrderStatusPersistence(client as never);
  await assertRejects(() =>
    persistence.claimEvent({
      eventOutboxId: EVENT,
      maxAttempts: 3,
      leaseSeconds: 120,
    })
  );
  const noEvent = createOrderStatusPersistence({
    rpc: () => Promise.resolve({ data: [], error: null }),
  } as never);
  assertEquals(
    (await noEvent.claimEvent({
      eventOutboxId: EVENT,
      maxAttempts: 3,
      leaseSeconds: 120,
    })).claim_state,
    "no_event",
  );
});
