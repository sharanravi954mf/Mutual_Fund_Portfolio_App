import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { createNseMandateStatusHandler } from "./handler.ts";
import {
  createMandateStatusGateway,
  createMandateStatusPersistence,
} from "./adapters.ts";
import type { MandateStatusPersistence } from "./types.ts";
import type { MandateStatusSource } from "../_shared/nse/nse_mandate_status.ts";

const EVENT = "10000000-0000-4000-8000-000000000001";
const OPERATION = "10000000-0000-4000-8000-000000000002";
const CLAIM = "10000000-0000-4000-8000-000000000003";
const CALL = "10000000-0000-4000-8000-000000000004";
const TOKEN = "synthetic-token";
const source: MandateStatusSource = {
  operation_id: OPERATION,
  workspace_id: CALL,
  integration_account_id: CALL,
  api: "MANDATE_STATUS",
  client_code: "SYNTHETIC1",
  pan: "AAAAA0000A",
  request: { client_code: "SYNTHETIC1" },
};
const response = JSON.stringify({
  response_status: "S",
  report_data_total: "1",
  error_remark: "",
  report_data: [{
    mandateId: "12345",
    clientCode: "SYNTHETIC1",
    memberCode: "TEST",
    memberMandateId: "",
    bankAccountNumber: "PRIVATE",
    status: "APPROVED",
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
    source?: MandateStatusSource;
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
  const starts: Parameters<MandateStatusPersistence["start"]>[0][] = [];
  const finishes: Parameters<MandateStatusPersistence["finish"]>[0][] = [];
  const sent: string[] = [];
  let startFailures = options.startFailures ?? 0,
    finishFailures = options.finishFailures ?? 0;
  const persistence: MandateStatusPersistence = {
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
          : options.source ?? source,
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
  const handler = createNseMandateStatusHandler({
    internalToken: TOKEN,
    persistence,
    gateway: {
      requestHeaderMetadata: () => ({
        content_type: "application/json",
        accept: "application/json",
      }),
      submit: (body, api) => {
        assertEquals(api, (options.source ?? source).api);
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
              rawBodyBase64: btoa(options.raw ?? response),
            },
        );
      },
    },
    now: () => new Date("2026-09-30T00:00:00Z"),
    uuid: () => CALL,
  });
  return { handler, sequence, starts, finishes, sent };
}
Deno.test("MANDATE_STATUS worker: authentication and explicit event before claim", async () => {
  const s = setup();
  assertEquals((await s.handler(new Request("http://localhost"))).status, 405);
  assertEquals((await s.handler(invocation({}, "bad"))).status, 403);
  for (
    const body of [null, [], {}, { event_outbox_id: "bad" }, {
      event_outbox_id: EVENT,
      api: "FATCA_REPORT",
    }]
  ) {
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
Deno.test("MANDATE_STATUS worker: one exact evidenced read and safe output with private authorization fields", async () => {
  const s = setup();
  const result = await s.handler(invocation());
  assertEquals(result.status, 200);
  assertEquals(await result.json(), {
    data: { outcome: "mandate_status_unique_match_received", record_count: 1 },
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
Deno.test("MANDATE_STATUS worker: persistence acknowledgement retry never repeats transport", async () => {
  const s = setup({ startFailures: 1, finishFailures: 1 });
  assertEquals((await s.handler(invocation())).status, 200);
  assertEquals(s.starts.length, 2);
  assertEquals(s.starts[0], s.starts[1]);
  assertEquals(s.finishes.length, 2);
  assertEquals(s.finishes[0], s.finishes[1]);
  assertEquals(s.sent.length, 1);
});
Deno.test("MANDATE_STATUS worker keeps PII and diagnostics only in evidence", async () => {
  const original = console.error;
  const logs: unknown[] = [];
  console.error = (...x) => logs.push(x);
  try {
    for (
      const raw of [
        response,
        response.replace('"error_remark":""', '"error_remark":"PRIVATE"'),
      ]
    ) {
      const s = setup({ raw });
      const r = await s.handler(invocation());
      assertEquals((await r.text()).includes("PRIVATE"), false);
      assertEquals(s.finishes[0].responsePayload, raw);
      const { responsePayload: _, ...metadata } = s.finishes[0];
      assertEquals(JSON.stringify(metadata).includes("PRIVATE"), false);
    }
    assertEquals(logs, []);
  } finally {
    console.error = original;
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
  Deno.test(`MANDATE_STATUS worker fails before transport ${JSON.stringify(options)}`, async () => {
    const s = setup(options);
    const result = await s.handler(invocation());
    assertEquals(result.status, status);
    assertEquals(s.sent.length, 0);
    assertEquals((await result.text()).includes("PRIVATE"), false);
  });
}
Deno.test("MANDATE_STATUS worker: permanent RESULT persistence failure is sanitized", async () => {
  const s = setup({ finishFailures: 2 });
  const result = await s.handler(invocation());
  assertEquals(result.status, 500);
  assertEquals(s.sent.length, 1);
  assertEquals((await result.text()).includes("PRIVATE"), false);
});
for (const status of [408, 429, 500, 502, 503, 504]) {
  for (const attempt of [1, 3]) {
    Deno.test(`MANDATE_STATUS bounded HTTP ${status} attempt ${attempt}`, async () => {
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
  Deno.test(`MANDATE_STATUS terminal HTTP ${status}`, async () => {
    const s = setup({ status });
    assertEquals((await s.handler(invocation())).status, 502);
    assertEquals(s.finishes[0].normalizedOutcome, "HTTP_FAILURE");
  });
}
Deno.test("MANDATE_STATUS worker: transport failures close read evidence without ambiguity", async () => {
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
  Deno.test(`MANDATE_STATUS worker: unusable report ${raw.length}`, async () => {
    const s = setup({ raw });
    const result = await s.handler(invocation());
    assertEquals(result.status, 202);
    assertEquals(s.finishes[0].normalizedOutcome, "BUSINESS_FAILURE");
    assertEquals((await result.text()).includes("PRIVATE"), false);
  });
}
Deno.test("MANDATE_STATUS gateway uses exact report endpoint, existing auth, and one injected fetch", async () => {
  let calls = 0;
  const gateway = createMandateStatusGateway(
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
        "https://example.invalid/nsemfdesk/api/v2/reports/MANDATE_STATUS",
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
  const result = await gateway.submit(
    JSON.stringify(source.request),
    source.api,
  );
  assertEquals(calls, 1);
  assertEquals(result.kind, "response");
  if (result.kind === "response") {
    assertEquals(result.safeHeaderMetadata, {
      content_type: "application/json",
    });
  }
});
Deno.test("MANDATE_STATUS persistence: exact endpoint RPCs and no UCC distribution", async () => {
  const names: string[] = [];
  const persistence = createMandateStatusPersistence({
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
    "recover_expired_nse_mandate_status_events",
    "claim_nse_mandate_status_event",
    "get_nse_mandate_status_source",
    "start_nse_mandate_status",
    "finish_nse_mandate_status",
  ]);
  const failing = createMandateStatusPersistence(
    {
      rpc: () => Promise.resolve({ data: null, error: { message: "PRIVATE" } }),
    } as never,
  );
  await assertRejects(
    () => failing.loadSource(OPERATION),
    Error,
    "mandate_status_persistence_unavailable",
  );
});

for (
  const [api, path] of [
    ["MANDATE_STATUS", "MANDATE_STATUS"],
  ] as const
) {
  Deno.test(`${api} gateway: exact path and bounded response failures`, async () => {
    const config = {
      baseUrl: "https://example.invalid",
      loginUserId: "synthetic",
      apiKeyMember: "synthetic",
      apiSecretUser: "synthetic",
      memberCode: "synthetic",
      userAgent: "MoneyBowl-Test",
    };
    let calls = 0;
    const gateway = createMandateStatusGateway(
      config,
      ((_url, init) => {
        calls++;
        assertEquals(
          String(_url),
          `https://example.invalid/nsemfdesk/api/v2/reports/${path}`,
        );
        assertEquals(init?.method, "POST");
        assertEquals(init?.body, "{}");
        assertEquals(init?.redirect, "error");
        return Promise.resolve(new Response("x".repeat(1048577)));
      }) as typeof fetch,
    );
    const result = await gateway.submit("{}", api);
    assertEquals(calls, 1);
    assertEquals(result.kind, "failure");
    if (result.kind === "failure") {
      assertEquals(result.errorCategory, "nse_response_too_large");
    }
  });
}

Deno.test("B07 exact bounded bytes survive BOM, malformed UTF-8 and embedded NUL", async () => {
  for (
    const bytes of [
      new Uint8Array([0xef, 0xbb, 0xbf, 0x7b, 0x7d]),
      new Uint8Array([0xff, 0x80]),
      new Uint8Array([0x00, 0x7b, 0x7d]),
    ]
  ) {
    const gateway = createMandateStatusGateway({
      baseUrl: "https://example.invalid",
      loginUserId: "synthetic",
      apiKeyMember: "synthetic",
      apiSecretUser: "synthetic",
      memberCode: "synthetic",
      userAgent: "test",
    }, (() => Promise.resolve(new Response(bytes))) as typeof fetch);
    const result = await gateway.submit("{}", "MANDATE_STATUS");
    assertEquals(result.kind, "response");
    if (result.kind === "response") {
      assertEquals(
        Uint8Array.from(atob(result.rawBodyBase64), (c) => c.charCodeAt(0)),
        bytes,
      );
      assertEquals(result.rawBody, bytes[0] === 0xef ? "\ufeff{}" : "");
    }
  }
});
