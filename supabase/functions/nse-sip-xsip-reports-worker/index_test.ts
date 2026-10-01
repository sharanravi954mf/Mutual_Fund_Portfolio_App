import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { createNseSipXsipReportsHandler } from "./handler.ts";
import {
  createSipXsipReportsGateway,
  createSipXsipReportsPersistence,
} from "./adapters.ts";
import type { SipXsipReportsPersistence } from "./types.ts";
import type { SipXsipReportsSource } from "../_shared/nse/nse_sip_xsip_reports.ts";

const EVENT = "10000000-0000-4000-8000-000000000001";
const OPERATION = "10000000-0000-4000-8000-000000000002";
const CLAIM = "10000000-0000-4000-8000-000000000003";
const CALL = "10000000-0000-4000-8000-000000000004";
const TOKEN = "synthetic-token";
const source: SipXsipReportsSource = {
  operation_id: OPERATION,
  workspace_id: CALL,
  integration_account_id: CALL,
  api: "SIP_REG_REPORT",
  client_code: "SYNTHETIC1",
  pan: "AAAAA0000A",
  today: "2026-10-01",
  selectors: { mode: "client", rows: [] },
  request: { client_code: "SYNTHETIC1" },
};
const response = JSON.stringify({
  response_status: "S",
  report_data_total: "1",
  report_data: [{
    "status": "NATIVE_UNCHARACTERIZED",
    "member_code": "05418",
    "client_code": "SYNTHETIC1",
    "client_name": "SYNTHETIC HOLDER",
    "pg_bank_ref_no": "PRIVATE_REFERENCE",
    "sip_reg_number": "202501011000001",
    "sip_reg_date": "01 JAN 2025",
    "amc_name": "SYNTHETIC_SCHEME",
    "rta_scheme_code": "SYNTHETIC_SCHEME",
    "scheme_name": "SYNTHETIC_SCHEME",
    "frequency_type": "MONTHLY",
    "start_date": "01 JAN 2025",
    "end_date": "01 JAN 2025",
    "installments_amount": "1000",
    "entry_by": " ",
    "dpc_flag": " ",
    "dp_trans": " ",
    "first_order_today": " ",
    "sub_broker_code": " ",
    "euin": " ",
    "euin_declaration": " ",
    "folio_number": " ",
    "remarks": " ",
    "sub_broker_arn_code": " ",
    "no_of_installments": "1000",
    "exchange_remark": " ",
    "health_declaration_flag": " ",
    "nominee_dob": " ",
    "disclaimer_flag": " ",
    "internal_ref_no": " ",
    "primary_holder_email": " ",
    "primary_holder_mobile": " ",
    "second_holder_email": " ",
    "second_holder_mobile": " ",
    "third_holder_email": " ",
    "third_holder_mobile": " ",
    "member_unique_id": "SYNTHETIC_REF_1",
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
    source?: SipXsipReportsSource;
    now?: string;
    status?: number;
    attempt?: number;
    raw?: string;
    transportFailure?: boolean;
    errorCategory?: string;
    startFailures?: number;
    finishFailures?: number;
    interpretationMismatch?: boolean;
    sourceFailure?: boolean;
    badSource?: boolean;
    noEvent?: boolean;
  } = {},
) {
  const testSource = options.source ?? source;
  const sequence: string[] = [];
  const starts: Parameters<SipXsipReportsPersistence["start"]>[0][] = [];
  const finishes: Parameters<SipXsipReportsPersistence["finish"]>[0][] = [];
  const sent: string[] = [];
  let startFailures = options.startFailures ?? 0,
    finishFailures = options.finishFailures ?? 0;
  const persistence: SipXsipReportsPersistence = {
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
          ? {
            ...testSource,
            request: { ...testSource.request, client_code: "" },
          }
          : testSource,
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
      return Promise.resolve({
        normalized_outcome: options.interpretationMismatch
          ? "BUSINESS_FAILURE"
          : input.normalizedOutcome,
        native_remark_category: options.interpretationMismatch
          ? "sip_xsip_reports_interpretation_mismatch"
          : input.nativeRemarkCategory,
      });
    },
  };
  const handler = createNseSipXsipReportsHandler({
    internalToken: TOKEN,
    persistence,
    gateway: {
      requestHeaderMetadata: () => ({
        content_type: "application/json",
        accept: "application/json",
      }),
      submit: (body, api) => {
        assertEquals(api, testSource.api);
        sequence.push("transport");
        sent.push(body);
        return Promise.resolve(
          options.transportFailure
            ? {
              kind: "failure",
              errorCategory: options.errorCategory ?? "nse_request_timeout",
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
    now: () => new Date(options.now ?? "2026-09-30T00:00:00Z"),
    uuid: () => CALL,
  });
  return { handler, sequence, starts, finishes, sent };
}
Deno.test("SIP_XSIP_REPORTS worker: authentication and explicit event before claim", async () => {
  const s = setup();
  assertEquals((await s.handler(new Request("http://localhost"))).status, 405);
  assertEquals((await s.handler(invocation({}, "bad"))).status, 403);
  for (
    const body of [null, [], {}, { event_outbox_id: "bad" }, {
      event_outbox_id: EVENT,
      api: "TRANSACTION_DETAIL",
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
Deno.test("SIP_XSIP_REPORTS worker: one exact evidenced read and safe output with private lifecycle fields", async () => {
  const s = setup();
  const result = await s.handler(invocation());
  assertEquals(result.status, 200);
  assertEquals(await result.json(), {
    data: { outcome: "sip_xsip_reports_report_received", record_count: 1 },
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
Deno.test("SIP_XSIP_REPORTS worker: persistence acknowledgement retry never repeats transport", async () => {
  const s = setup({ startFailures: 1, finishFailures: 1 });
  assertEquals((await s.handler(invocation())).status, 200);
  assertEquals(s.starts.length, 2);
  assertEquals(s.starts[0], s.starts[1]);
  assertEquals(s.finishes.length, 2);
  assertEquals(s.finishes[0], s.finishes[1]);
  assertEquals(s.sent.length, 1);
});
Deno.test("SIP_XSIP_REPORTS worker keeps PII and diagnostics only in evidence", async () => {
  const original = console.error;
  const logs: unknown[] = [];
  console.error = (...x) => logs.push(x);
  try {
    for (
      const raw of [
        response,
        JSON.stringify({ ...JSON.parse(response), error_remark: "PRIVATE" }),
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
  Deno.test(`SIP_XSIP_REPORTS worker fails before transport ${JSON.stringify(options)}`, async () => {
    const s = setup(options);
    const result = await s.handler(invocation());
    assertEquals(result.status, status);
    assertEquals(s.sent.length, 0);
    assertEquals((await result.text()).includes("PRIVATE"), false);
  });
}
Deno.test("SIP_XSIP_REPORTS worker: permanent RESULT persistence failure is sanitized", async () => {
  const s = setup({ finishFailures: 2 });
  const result = await s.handler(invocation());
  assertEquals(result.status, 500);
  assertEquals(s.sent.length, 1);
  assertEquals((await result.text()).includes("PRIVATE"), false);
});
for (const status of [408, 429, 500, 502, 503, 504]) {
  for (const attempt of [1, 3]) {
    Deno.test(`SIP_XSIP_REPORTS bounded HTTP ${status} attempt ${attempt}`, async () => {
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
  Deno.test(`SIP_XSIP_REPORTS terminal HTTP ${status}`, async () => {
    const s = setup({ status });
    assertEquals((await s.handler(invocation())).status, 502);
    assertEquals(s.finishes[0].normalizedOutcome, "HTTP_FAILURE");
  });
}
Deno.test("SIP_XSIP_REPORTS worker: transport failures close read evidence without ambiguity", async () => {
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
    JSON.stringify({ ...JSON.parse(response), error_remark: "PRIVATE" })
      .replace(
        '"report_data_total":"1"',
        '"report_data_total":"0"',
      ),
    response.replace('"SYNTHETIC1"', '"OTHER"'),
    '{"response_status":"F","report_data_total":"0","report_data":"","error_remark":"PRIVATE"}',
  ]
) {
  Deno.test(`SIP_XSIP_REPORTS worker: unusable report ${raw.length}`, async () => {
    const s = setup({ raw });
    const result = await s.handler(invocation());
    assertEquals(result.status, 202);
    assertEquals(s.finishes[0].normalizedOutcome, "BUSINESS_FAILURE");
    assertEquals((await result.text()).includes("PRIVATE"), false);
  });
}
Deno.test("SIP_XSIP_REPORTS gateway uses exact report endpoint, existing auth, and one injected fetch", async () => {
  let calls = 0;
  const gateway = createSipXsipReportsGateway(
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
        "https://example.invalid/nsemfdesk/api/v2/reports/SIP_REG_REPORT",
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
Deno.test("SIP_XSIP_REPORTS persistence: exact endpoint RPCs and no UCC distribution", async () => {
  const names: string[] = [];
  const persistence = createSipXsipReportsPersistence({
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
    "recover_expired_nse_sip_xsip_reports_events",
    "claim_nse_sip_xsip_reports_event",
    "get_nse_sip_xsip_reports_source",
    "start_nse_sip_xsip_reports",
    "finish_nse_sip_xsip_reports",
  ]);
  const failing = createSipXsipReportsPersistence(
    {
      rpc: () => Promise.resolve({ data: null, error: { message: "PRIVATE" } }),
    } as never,
  );
  await assertRejects(
    () => failing.loadSource(OPERATION),
    Error,
    "sip_xsip_reports_persistence_unavailable",
  );
});

for (
  const [api, path] of [
    ["SIP_REG_REPORT", "SIP_REG_REPORT"],
    ["SIP_CAN_REPORT", "SIP_CAN_REPORT"],
    ["SIP_INST_DUE_REPORT", "SIP_INST_DUE_REPORT"],
    ["SIP_TOPUP_REPORT", "SIP_TOPUP_REPORT"],
    ["STEPUP_REG_REPORT", "STEPUP_REG_REPORT"],
    ["XSIP_REG_REPORT", "XSIP_REG_REPORT"],
    ["XSIP_CAN_REPORT", "XSIP_CAN_REPORT"],
    ["XSIP_INST_DUE_REPORT", "XSIP_INST_DUE_REPORT"],
    ["XSIP_TOPUP_REPORT", "XSIP_TOPUP_REPORT"],
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
    const gateway = createSipXsipReportsGateway(
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

Deno.test("B04 exact bounded bytes survive BOM, malformed UTF-8 and embedded NUL", async () => {
  for (
    const bytes of [
      new Uint8Array([0xef, 0xbb, 0xbf, 0x7b, 0x7d]),
      new Uint8Array([0xff, 0x80]),
      new Uint8Array([0x00, 0x7b, 0x7d]),
    ]
  ) {
    const gateway = createSipXsipReportsGateway({
      baseUrl: "https://example.invalid",
      loginUserId: "synthetic",
      apiKeyMember: "synthetic",
      apiSecretUser: "synthetic",
      memberCode: "synthetic",
      userAgent: "test",
    }, (() => Promise.resolve(new Response(bytes))) as typeof fetch);
    const result = await gateway.submit("{}", "SIP_CAN_REPORT");
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

Deno.test("B04 durable parser disagreement retains RESULT but never acknowledges success", async () => {
  for (
    const raw of [
      response,
      '{"response_status":"S","report_data_total":1e-400,"report_data":[]}',
    ]
  ) {
    const s = setup({ interpretationMismatch: true, raw });
    const result = await s.handler(invocation());
    assertEquals(result.status, 202);
    assertEquals(await result.json(), {
      data: {
        outcome: "sip_xsip_reports_interpretation_mismatch",
        record_count: 0,
      },
    });
    assertEquals(s.sent.length, 1);
    assertEquals(s.finishes[0].responsePayload, raw);
    assertEquals(s.finishes[0].normalizedOutcome, "SUCCESS");
  }
});

Deno.test("B04 nontransient transport failures never offer retry", async () => {
  for (
    const errorCategory of [
      "nse_response_too_large",
      "nse_response_invalid",
      "nse_request_invalid",
    ]
  ) {
    const s = setup({ transportFailure: true, errorCategory });
    const r = await s.handler(invocation());
    assertEquals(await r.json(), {
      data: { outcome: "sip_xsip_reports_transport_failed" },
    });
    assertEquals(s.sent.length, 1);
  }
});

for (
  const api of [
    "SIP_REG_REPORT",
    "SIP_CAN_REPORT",
    "SIP_INST_DUE_REPORT",
    "SIP_TOPUP_REPORT",
    "STEPUP_REG_REPORT",
    "XSIP_REG_REPORT",
    "XSIP_CAN_REPORT",
    "XSIP_INST_DUE_REPORT",
    "XSIP_TOPUP_REPORT",
  ] as const
) {
  Deno.test(`${api} worker persists one REQUEST/RESULT pair for an empty observation`, async () => {
    const raw =
      '{"response_status":"S","report_data_total":"0","report_data":[]}';
    const s = setup({
      source: { ...source, api },
      raw,
      startFailures: 1,
      finishFailures: 1,
    });
    const r = await s.handler(invocation());
    assertEquals(r.status, 200);
    assertEquals(await r.json(), {
      data: { outcome: "sip_xsip_reports_no_records", record_count: 0 },
    });
    assertEquals(s.sent.length, 1);
    assertEquals(s.starts.length, 2);
    assertEquals(s.finishes.length, 2);
    assertEquals(s.starts[0], s.starts[1]);
    assertEquals(s.finishes[0], s.finishes[1]);
    assertEquals(s.starts[0].requestPayload, s.sent[0]);
    assertEquals(s.finishes[0].responsePayload, raw);
  });
}
Deno.test("Due workers recheck supplied dates against deterministic India midnight before transport", async () => {
  for (const api of ["SIP_INST_DUE_REPORT", "XSIP_INST_DUE_REPORT"] as const) {
    const due = {
      ...source,
      api,
      today: "2026-09-29",
      request: {
        client_code: "SYNTHETIC1",
        from_date: "30-09-2026",
        to_date: "01-10-2026",
      },
    };
    const before = setup({
      source: due,
      now: "2026-09-30T18:29:59Z",
      raw: '{"response_status":"S","report_data_total":0,"report_data":[]}',
    });
    assertEquals((await before.handler(invocation())).status, 200);
    const after = setup({ source: due, now: "2026-09-30T18:30:00Z" });
    assertEquals((await after.handler(invocation())).status, 422);
    assertEquals(after.sent.length, 0);
    assertEquals(after.starts.length, 0);
  }
});
