import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  buildNseOrderStatusRequest,
  parseNseOrderStatusResponse,
} from "../_shared/nse/nse_order_status.ts";
import { createNseOrderStatusHandler } from "./handler.ts";

const EVENT = "10000000-0000-4000-8000-000000000001";
const source = {
  operation_id: "op",
  workspace_id: "ws",
  integration_account_id: "account",
  correlation_id: EVENT,
  client_code: "abc01",
  from_date: "2026-09-01",
  to_date: "2026-09-07",
  trans_type: "ALL" as const,
  order_type: "ALL" as const,
  sub_order_type: "ALL" as const,
  order_ids: ["order-1"],
  member_unique_ids: ["ignored"],
};

Deno.test("ORDER_STATUS mapper validates bounded dates, excludes date_type, and gives order_ids precedence", () => {
  assertEquals(buildNseOrderStatusRequest(source), {
    client_code: "ABC01",
    from_date: "2026-09-01",
    to_date: "2026-09-07",
    trans_type: "ALL",
    order_type: "ALL",
    sub_order_type: "ALL",
    order_ids: ["order-1"],
  });
  assertThrows(() =>
    buildNseOrderStatusRequest({ ...source, to_date: "2026-09-08" })
  );
  assertThrows(() =>
    buildNseOrderStatusRequest({
      ...source,
      order_ids: Array.from({ length: 51 }, (_, i) => `${i}`),
    })
  );
});
Deno.test("ORDER_STATUS parser accepts S empty and S INVALID rows while excluding PII", () => {
  assertEquals(
    parseNseOrderStatusResponse('{"response_status":"S","report_data":[]}')
      .recordCount,
    0,
  );
  const result = parseNseOrderStatusResponse(
    '{"response_status":"S","report_data":[{"order_status":"INVALID","amount":"10","applicant_name":"no","mobile":"no","remarks":"no"}]}',
  );
  assertEquals(result.projectedRecords, [{
    order_status: "INVALID",
    amount: "10",
  }]);
  assertEquals(
    parseNseOrderStatusResponse('{"response_status":"F","report_data":[]}')
      .nativeStatus,
    "F",
  );
  assertThrows(() => parseNseOrderStatusResponse('{"response_status":"X"}'));
});
function handler(
  response: { status: number; body: string } | null,
  calls: string[],
) {
  return createNseOrderStatusHandler({
    internalToken: "token",
    uuid: () => "20000000-0000-4000-8000-000000000001",
    persistence: {
      recoverExpired: () => Promise.resolve(),
      claimEvent: () =>
        Promise.resolve({
          event_outbox_id: EVENT,
          integration_operation_id: "op",
          attempt: 1,
          claim_state: "newly_claimed",
          claim_token: "30000000-0000-4000-8000-000000000001",
        }),
      loadSource: () => Promise.resolve(source),
      start: () => Promise.resolve(),
      finish: (input) => {
        calls.push(String(input.normalizedOutcome));
        return Promise.resolve();
      },
    },
    gateway: {
      requestHeaderMetadata: () => ({
        content_type: "application/json",
        accept: "application/json",
      }),
      submit: () => {
        calls.push("send");
        return Promise.resolve(
          response == null
            ? {
              kind: "failure" as const,
              errorCategory: "nse_network_error",
              timeout: false,
              networkFailure: true,
            }
            : {
              kind: "response" as const,
              status: response.status,
              contentType: "application/json",
              safeHeaderMetadata: {},
              rawBody: response.body,
            },
        );
      },
    },
  });
}
Deno.test("ORDER_STATUS records evidence around exactly one send and retries transport and bounded HTTP", async () => {
  const calls: string[] = [];
  const response = await handler({ status: 503, body: "x" }, calls)(
    new Request("http://local", {
      method: "POST",
      headers: { authorization: "Bearer token" },
      body: JSON.stringify({ event_outbox_id: EVENT }),
    }),
  );
  assertEquals(calls, ["send", "HTTP_FAILURE"]);
  assertEquals(response.status, 202);
  const transport: string[] = [];
  await handler(null, transport)(
    new Request("http://local", {
      method: "POST",
      headers: { authorization: "Bearer token" },
      body: JSON.stringify({ event_outbox_id: EVENT }),
    }),
  );
  assertEquals(transport, ["send", "TRANSPORT_FAILURE"]);
});
