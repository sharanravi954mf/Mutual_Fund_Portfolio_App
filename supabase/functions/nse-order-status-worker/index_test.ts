import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  buildNseOrderStatusRequest,
  parseNseOrderStatusResponse,
} from "../_shared/nse/nse_order_status.ts";
import { createNseOrderStatusWorkerHandler } from "./handler.ts";
const EVENT = "10000000-0000-4000-8000-000000000001",
  TOKEN = "20000000-0000-4000-8000-000000000001";
function dependencies(
  response: any = {
    kind: "response",
    status: 200,
    contentType: "application/json",
    headers: { content_type: "application/json" },
    body: '{"status":"S","order_status":[]}',
  },
) {
  const calls: string[] = [];
  return {
    calls,
    d: {
      internalToken: "token",
      uuid: () => "30000000-0000-4000-8000-000000000001",
      persistence: {
        recoverExpired: async () => {
          calls.push("recover");
        },
        claim: async () => ({
          event_outbox_id: EVENT,
          integration_operation_id: "40000000-0000-4000-8000-000000000001",
          attempt: 1,
          claim_state: "claimed",
          claim_token: TOKEN,
        }),
        source: async () => ({
          client_code: "MBUAT0001",
          from_date: "2026-09-01",
          to_date: "2026-09-07",
          order_status: "ALL",
          transaction_type: "ALL",
        }),
        start: async () => {
          calls.push("start");
        },
        finish: async () => {
          calls.push("finish");
        },
      },
      gateway: {
        headers: () => ({ content_type: "application/json" }),
        submit: async () => response,
      },
    },
  };
}
function request(body: unknown) {
  return new Request("http://local", {
    method: "POST",
    headers: { authorization: "Bearer token" },
    body: JSON.stringify(body),
  });
}
Deno.test("ORDER_STATUS has no date_type and accepts the bounded request", () =>
  assertEquals(
    buildNseOrderStatusRequest({
      operation_id: "x",
      client_code: "MBUAT0001",
      from_date: "2026-09-01",
      to_date: "2026-09-07",
      order_status: "ALL",
      transaction_type: "ALL",
    }),
    {
      client_code: "MBUAT0001",
      from_date: "2026-09-01",
      to_date: "2026-09-07",
      order_status: "ALL",
      transaction_type: "ALL",
    },
  ));
Deno.test("S with an empty array is successful and only counts observations", () =>
  assertEquals(
    parseNseOrderStatusResponse('{"status":"S","order_status":[]}'),
    {
      businessSuccess: true,
      nativeStatus: "S",
      observationCount: 0,
      invalidCount: 0,
    },
  ));
Deno.test("worker persists REQUEST before one NSE submission then RESULT", async () => {
  const x: any = dependencies();
  const response = await createNseOrderStatusWorkerHandler(x.d)(
    request({ event_outbox_id: EVENT }),
  );
  assertEquals(response.status, 200);
  assertEquals(x.calls, ["recover", "start", "finish"]);
});
Deno.test("only an empty no_event result maps to no_event", async () => {
  const x: any = dependencies();
  x.d.persistence.claim = (async () => ({
    event_outbox_id: null,
    integration_operation_id: null,
    attempt: 0,
    claim_state: "no_event",
    claim_token: null,
  })) as any;
  const response = await createNseOrderStatusWorkerHandler(x.d)(
    request({ event_outbox_id: EVENT }),
  );
  assertEquals(await response.json(), { data: { outcome: "no_event" } });
});
