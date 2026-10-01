import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { createNseProvOrdersHandler } from "./handler.ts";
import {
  createProvOrdersGateway,
  createProvOrdersPersistence,
} from "./adapters.ts";
import type { ProvOrdersPersistence } from "./types.ts";
import type { NseProvOrdersSource } from "../_shared/nse/nse_prov_orders.ts";

const EVENT = "10000000-0000-4000-8000-000000000001";
const OPERATION = "10000000-0000-4000-8000-000000000002";
const CLAIM = "10000000-0000-4000-8000-000000000003";
const CALL = "10000000-0000-4000-8000-000000000004";
const TOKEN = "synthetic-token";
const source: NseProvOrdersSource = {
  operation_id: OPERATION,
  workspace_id: CALL,
  integration_account_id: CALL,
  request: {
    from_date: "2023-11-10",
    to_date: "2023-11-16",
    trans_type: "ALL",
    order_type: "ALL",
    sub_order_type: "ALL",
    client_code: "SYNTHETIC1",
    order_status: "",
    settlement_type: "",
    order_ids: "",
    member_unique_ids: "",
    date_type: "REQUEST DATE",
  },
};
const response = JSON.stringify({
  response_status: "S",
  report_data_total: "1",
  error_remark: "",
  report_data: [{
    client_code: "SYNTHETIC1",
    order_id: "123",
    order_status: "INVALID",
    email: "private@moneybowl.invalid",
  }],
});
function invocation(body: unknown = { event_outbox_id: EVENT }, token = TOKEN) {
  return new Request("http://localhost", {
    method: "POST",
    headers: { authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
}
function setup(
  options: {
    status?: number;
    attempt?: number;
    raw?: string;
    transportFailure?: boolean;
    startFailures?: number;
    finishFailures?: number;
    sourceFailure?: boolean;
    badSource?: boolean;
    noEvent?: boolean;
  } = {},
) {
  const sequence: string[] = [];
  const starts: Parameters<ProvOrdersPersistence["start"]>[0][] = [];
  const finishes: Parameters<ProvOrdersPersistence["finish"]>[0][] = [];
  const sent: string[] = [];
  let startFailures = options.startFailures ?? 0,
    finishFailures = options.finishFailures ?? 0;
  const persistence: ProvOrdersPersistence = {
    recoverExpired: () => {
      sequence.push("recover");
      return Promise.resolve({});
    },
    claimEvent: () => {
      sequence.push("claim");
      return Promise.resolve({
        event_outbox_id: EVENT,
        integration_operation_id: OPERATION,
        correlation_id: CALL,
        claim_token: CLAIM,
        attempt: options.attempt ?? 1,
        claim_state: options.noEvent ? "no_event" : "newly_claimed",
      });
    },
    loadSource: (id) => {
      assertEquals(id, OPERATION);
      sequence.push("source");
      if (options.sourceFailure) return Promise.reject(new Error("PRIVATE"));
      return Promise.resolve(
        options.badSource
          ? { ...source, request: { ...source.request, client_code: "" } }
          : source,
      );
    },
    start: (input) => {
      sequence.push("request");
      starts.push(input);
      if (startFailures-- > 0) return Promise.reject(new Error("PRIVATE"));
      return Promise.resolve({});
    },
    finish: (input) => {
      sequence.push("result");
      finishes.push(input);
      if (finishFailures-- > 0) return Promise.reject(new Error("PRIVATE"));
      return Promise.resolve({});
    },
  };
  const handler = createNseProvOrdersHandler({
    internalToken: TOKEN,
    persistence,
    gateway: {
      requestHeaderMetadata: () => ({
        content_type: "application/json",
        accept: "application/json",
      }),
      submit: (body) => {
        sequence.push("transport");
        sent.push(body);
        return Promise.resolve(
          options.transportFailure
            ? {
              kind: "failure",
              errorCategory: "nse_request_timeout",
              timeout: true,
              networkFailure: false,
            }
            : {
              kind: "response",
              status: options.status ?? 200,
              contentType: "application/json",
              safeHeaderMetadata: { content_type: "application/json" },
              rawBody: options.raw ?? response,
            },
        );
      },
    },
    now: () => new Date("2026-09-30T00:00:00Z"),
    uuid: () => CALL,
  });
  return { handler, sequence, starts, finishes, sent };
}
Deno.test("PROV_ORDERS worker: authentication and explicit event before claim", async () => {
  const s = setup();
  assertEquals((await s.handler(new Request("http://localhost"))).status, 405);
  assertEquals((await s.handler(invocation({}, "bad"))).status, 403);
  for (const body of [null, [], {}, { event_outbox_id: "bad" }]) {
    assertEquals((await s.handler(invocation(body))).status, 400);
  }
  assertEquals(
    (await s.handler(
      new Request("http://localhost", {
        method: "POST",
        headers: { authorization: `Bearer ${TOKEN}` },
        body: "{",
      }),
    )).status,
    400,
  );
  assertEquals(s.sequence, []);
});
Deno.test("PROV_ORDERS worker: one exact evidenced read and safe output for INVALID order", async () => {
  const s = setup();
  const result = await s.handler(invocation());
  assertEquals(result.status, 200);
  assertEquals(await result.json(), {
    data: { outcome: "prov_orders_report_received", record_count: 1 },
  });
  assertEquals(s.sequence, [
    "recover",
    "claim",
    "source",
    "request",
    "transport",
    "result",
  ]);
  assertEquals(s.sent, [s.starts[0].requestPayload]);
  assertEquals(JSON.parse(s.sent[0]), source.request);
  assertEquals(s.finishes[0].responsePayload, response);
  assertEquals(s.finishes[0].normalizedOutcome, "SUCCESS");
});
Deno.test("PROV_ORDERS worker: persistence acknowledgement retry never repeats transport", async () => {
  const s = setup({ startFailures: 1, finishFailures: 1 });
  assertEquals((await s.handler(invocation())).status, 200);
  assertEquals(s.starts.length, 2);
  assertEquals(s.starts[0], s.starts[1]);
  assertEquals(s.finishes.length, 2);
  assertEquals(s.finishes[0], s.finishes[1]);
  assertEquals(s.sent.length, 1);
});
Deno.test("PROV_ORDERS worker: historical success diagnostic stays in RESULT, never response or logs", async () => {
  const logs: unknown[][] = [];
  const original = {
    log: console.log,
    info: console.info,
    warn: console.warn,
    error: console.error,
    debug: console.debug,
  };
  for (const level of ["log", "info", "warn", "error", "debug"] as const) {
    console[level] = (...args: unknown[]) => {
      logs.push(args);
    };
  }
  try {
    // The empty case reconstructs request 20's safe historical schema/categories.
    // The nonempty case is synthetic coverage of the same diagnostic policy.
    for (const rows of [[], JSON.parse(response).report_data]) {
      const raw = JSON.stringify({
        response_status: "S",
        report_data_total: String(rows.length),
        report_data: rows,
        error_remark: "SYNTHETIC PRIVATE UAT DIAGNOSTIC",
      });
      const s = setup({ raw, startFailures: 1, finishFailures: 1 });
      const result = await s.handler(invocation());
      const category = rows.length === 0
        ? "prov_orders_no_records"
        : "prov_orders_report_received";
      assertEquals(result.status, 200);
      assertEquals(await result.json(), {
        data: { outcome: category, record_count: rows.length },
      });
      assertEquals(s.sent.length, 1);
      assertEquals(s.finishes.length, 2);
      assertEquals(s.finishes[0], s.finishes[1]);
      assertEquals(s.finishes[0].responsePayload, raw);
      const { responsePayload: _raw, ...metadata } = s.finishes[0];
      assertEquals(metadata.normalizedOutcome, "SUCCESS");
      assertEquals(metadata.nativeStatusValue, "S");
      assertEquals(metadata.nativeRemarkCategory, category);
      assertEquals(metadata.errorCategory, null);
      assertEquals(JSON.stringify(metadata).includes("PRIVATE"), false);
    }
    assertEquals(logs, []);
  } finally {
    Object.assign(console, original);
  }
});
for (
  const [options, status] of [
    [{ startFailures: 2 }, 500],
    [{ sourceFailure: true }, 503],
    [{ badSource: true }, 422],
    [{ noEvent: true }, 404],
  ] as const
) {
  Deno.test(`PROV_ORDERS worker fails before transport ${JSON.stringify(options)}`, async () => {
    const s = setup(options);
    const result = await s.handler(invocation());
    assertEquals(result.status, status);
    assertEquals(s.sent.length, 0);
    assertEquals((await result.text()).includes("PRIVATE"), false);
  });
}
Deno.test("PROV_ORDERS worker: permanent RESULT persistence failure is sanitized", async () => {
  const s = setup({ finishFailures: 2 });
  const result = await s.handler(invocation());
  assertEquals(result.status, 500);
  assertEquals(s.sent.length, 1);
  assertEquals((await result.text()).includes("PRIVATE"), false);
});
for (const status of [408, 429, 500, 502, 503, 504]) {
  for (const attempt of [1, 3]) {
    Deno.test(`PROV_ORDERS bounded HTTP ${status} attempt ${attempt}`, async () => {
      const s = setup({ status, attempt, raw: "PRIVATE" });
      const result = await s.handler(invocation());
      assertEquals(result.status, attempt < 3 ? 202 : 502);
      assertEquals(s.finishes[0].normalizedOutcome, "HTTP_FAILURE");
      assertEquals(s.finishes[0].nativeStatusValue, null);
      assertEquals(s.finishes[0].responsePayload, "PRIVATE");
      assertEquals((await result.text()).includes("PRIVATE"), false);
    });
  }
}
for (const status of [400, 401, 403, 404, 501]) {
  Deno.test(`PROV_ORDERS terminal HTTP ${status}`, async () => {
    const s = setup({ status });
    assertEquals((await s.handler(invocation())).status, 502);
    assertEquals(s.finishes[0].normalizedOutcome, "HTTP_FAILURE");
  });
}
Deno.test("PROV_ORDERS worker: transport failures close read evidence without ambiguity", async () => {
  for (const attempt of [1, 3]) {
    const s = setup({ transportFailure: true, attempt });
    await s.handler(invocation());
    assertEquals(s.finishes[0].normalizedOutcome, "TRANSPORT_FAILURE");
    assertEquals(s.finishes[0].responsePayload, "");
  }
});
for (
  const raw of [
    "PRIVATE",
    response.replace('"error_remark":""', '"error_remark":"PRIVATE"').replace(
      '"report_data_total":"1"',
      '"report_data_total":"0"',
    ),
    response.replace('"SYNTHETIC1"', '"OTHER"'),
    '{"response_status":"F","report_data_total":"0","report_data":"","error_remark":"PRIVATE"}',
  ]
) {
  Deno.test(`PROV_ORDERS worker: unusable report ${raw.length}`, async () => {
    const s = setup({ raw });
    const result = await s.handler(invocation());
    assertEquals(result.status, 202);
    assertEquals(s.finishes[0].normalizedOutcome, "BUSINESS_FAILURE");
    assertEquals((await result.text()).includes("PRIVATE"), false);
  });
}
Deno.test("PROV_ORDERS gateway uses exact report endpoint, existing auth, and one injected fetch", async () => {
  let calls = 0;
  const gateway = createProvOrdersGateway(
    {
      baseUrl: "https://example.invalid",
      loginUserId: "synthetic",
      apiKeyMember: "synthetic",
      apiSecretUser: "synthetic",
      memberCode: "synthetic",
      userAgent: "MoneyBowl-Test",
    },
    ((_url, init) => {
      calls++;
      assertEquals(
        String(_url),
        "https://example.invalid/nsemfdesk/api/v2/reports/PROV_ORDERS",
      );
      assertEquals(init?.method, "POST");
      assertEquals(init?.redirect, "error");
      assertEquals(init?.body, JSON.stringify(source.request));
      assertEquals(new Headers(init?.headers).has("authorization"), true);
      return Promise.resolve(
        new Response(response, {
          status: 200,
          headers: {
            "content-type": "application/json",
            "set-cookie": "PRIVATE",
          },
        }),
      );
    }) as typeof fetch,
  );
  const result = await gateway.submit(JSON.stringify(source.request));
  assertEquals(calls, 1);
  assertEquals(result.kind, "response");
  if (result.kind === "response") {
    assertEquals(result.safeHeaderMetadata, {
      content_type: "application/json",
    });
  }
});
Deno.test("PROV_ORDERS persistence: exact endpoint RPCs and no UCC distribution", async () => {
  const names: string[] = [];
  const persistence = createProvOrdersPersistence({
    rpc: (name: string) => {
      names.push(name);
      return Promise.resolve({
        data: name.startsWith("claim_") ? [{ claim_state: "no_event" }] : {},
        error: null,
      });
    },
  } as never);
  await persistence.recoverExpired({ eventOutboxId: EVENT, maxAttempts: 3 });
  await persistence.claimEvent({
    eventOutboxId: EVENT,
    maxAttempts: 3,
    leaseSeconds: 120,
  });
  await persistence.loadSource(OPERATION);
  const s = setup();
  await s.handler(invocation());
  await persistence.start(s.starts[0]);
  await persistence.finish(s.finishes[0]);
  assertEquals(names, [
    "recover_expired_nse_prov_orders_events",
    "claim_nse_prov_orders_event",
    "get_nse_prov_orders_source",
    "start_nse_prov_orders",
    "finish_nse_prov_orders",
  ]);
  const failing = createProvOrdersPersistence(
    {
      rpc: () => Promise.resolve({ data: null, error: { message: "PRIVATE" } }),
    } as never,
  );
  await assertRejects(
    () => failing.loadSource(OPERATION),
    Error,
    "prov_orders_persistence_unavailable",
  );
});
