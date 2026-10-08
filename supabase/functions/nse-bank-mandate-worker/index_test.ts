import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  type Action,
  createHandler,
  PATHS,
  type Persistence,
  type Result,
  serializeRequest,
  type Source,
} from "./handler.ts";
import { gateway } from "./adapters.ts";
const EVENT = "10000000-0000-4000-8000-000000000001";
const OP = "10000000-0000-4000-8000-000000000002";
const CLAIM = "10000000-0000-4000-8000-000000000003";
const CALL = "10000000-0000-4000-8000-000000000004";
function source(action: Action): Source {
  const bank = {
    client_code: "TEST1",
    account_no: "12345678902",
    ifsc_code: "SBIN0000018",
  };
  return {
    operation_id: OP,
    kind: "WRITE",
    action,
    path: PATHS[action],
    request: action === "MANDATE"
      ? {
        reg_data: [{
          ...bank,
          amount: "100.00",
          mandate_type: "X",
          ac_type: "SB",
          start_date: "06/10/2026",
          end_date: "06/10/2027",
          member_mandate_no: "MB1234567890abcdef12",
        }],
      }
      : {
        bank_dtl: [{
          ...bank,
          account_type: "SB",
          micr_no: "",
          action_type: action === "BANK_ADD" ? "ADD" : "DEL",
          default_bank_flag: "N",
        }],
      },
  };
}
function setup(
  action: Action,
  options: {
    startFailures?: number;
    finishFailures?: number;
    delivery?: Result["delivery"];
    sourceFailure?: boolean;
    noClaim?: boolean;
    gatewayThrow?: boolean;
  } = {},
) {
  const sequence: string[] = [];
  const starts: unknown[] = [];
  const finishes: unknown[] = [];
  const sent: string[] = [];
  let sf = options.startFailures ?? 0, ff = options.finishFailures ?? 0;
  const persistence: Persistence = {
    claim: () => {
      sequence.push("claim");
      return Promise.resolve(
        options.noClaim ? null : {
          event_id: EVENT,
          operation_id: OP,
          claim_token: CLAIM,
          attempt: 1,
        },
      );
    },
    source: () => {
      sequence.push("source");
      return options.sourceFailure
        ? Promise.reject(new Error("PRIVATE"))
        : Promise.resolve(source(action));
    },
    start: (input) => {
      sequence.push("request");
      starts.push(input);
      return sf-- > 0
        ? Promise.reject(new Error("PRIVATE"))
        : Promise.resolve({});
    },
    finish: (input) => {
      sequence.push("result");
      finishes.push(input);
      return ff-- > 0
        ? Promise.reject(new Error("PRIVATE"))
        : Promise.resolve({ outcome: "b07_success" });
    },
    reconcile: () => {
      sequence.push("reconcile");
      return Promise.resolve({});
    },
  };
  const handler = createHandler({
    token: "synthetic",
    persistence,
    uuid: () => CALL,
    now: () => new Date("2026-10-06T12:00:00Z"),
    submit: (body) => {
      sequence.push("transport");
      sent.push(body);
      return options.gatewayThrow
        ? Promise.reject(new Error("PRIVATE"))
        : Promise.resolve({
          delivery: options.delivery ?? "SENT_WITH_RESULT",
          bodyBase64: btoa("PRIVATE"),
          httpStatus: 200,
          headers: {},
        });
    },
  });
  const invoke = (
    body: unknown = { event_outbox_id: EVENT },
    token = "synthetic",
  ) =>
    handler(
      new Request("http://localhost", {
        method: "POST",
        headers: { authorization: `Bearer ${token}` },
        body: JSON.stringify(body),
      }),
    );
  return { invoke, sequence, starts, finishes, sent };
}
for (const action of ["MANDATE", "BANK_ADD", "BANK_DEL"] as const) {
  Deno.test(`B07 ${action} exact frozen request before one transport`, async () => {
    const s = setup(action);
    assertEquals((await s.invoke()).status, 200);
    assertEquals(s.sequence, [
      "claim",
      "source",
      "request",
      "transport",
      "result",
    ]);
    assertEquals(s.sent, [JSON.stringify(source(action).request)]);
  });
  Deno.test(`B07 ${action} request persistence retry does not repeat transport`, async () => {
    const s = setup(action, { startFailures: 1 });
    await s.invoke();
    assertEquals(s.starts.length, 2);
    assertEquals(s.starts[0], s.starts[1]);
    assertEquals(s.sent.length, 1);
  });
  Deno.test(`B07 ${action} result persistence retry does not repeat transport`, async () => {
    const s = setup(action, { finishFailures: 1 });
    await s.invoke();
    assertEquals(s.finishes.length, 2);
    assertEquals(s.finishes[0], s.finishes[1]);
    assertEquals(s.sent.length, 1);
  });
  Deno.test(`B07 ${action} failed evidence prevents HTTP`, async () => {
    const s = setup(action, { startFailures: 2 });
    assertEquals((await s.invoke()).status, 500);
    assertEquals(s.sent, []);
  });
  Deno.test(`B07 ${action} authority failure before transport`, async () => {
    const s = setup(action, { sourceFailure: true });
    assertEquals((await s.invoke()).status, 500);
    assertEquals(s.sent, []);
    assertEquals(s.starts, []);
  });
  Deno.test(`B07 ${action} ambiguous transport is captured once`, async () => {
    const s = setup(action, { gatewayThrow: true });
    const res = await s.invoke();
    assertEquals(s.sent.length, 1);
    const f = s.finishes[0] as Parameters<Persistence["finish"]>[0];
    assertEquals(f.result.delivery, "MAYBE_SENT");
    assertEquals(await res.json(), { outcome: "evidence_recorded" });
  });
  Deno.test(`B07 ${action} exhausted persistence never repeats HTTP`, async () => {
    const s = setup(action, { finishFailures: 2 });
    const res = await s.invoke();
    assertEquals(res.status, 500);
    assertEquals(s.sent.length, 1);
    assertEquals(await res.json(), { outcome: "b07_worker_failed" });
  });
  Deno.test(`B07 ${action} event-only input and authentication`, async () => {
    const s = setup(action);
    assertEquals((await s.invoke({}, "bad")).status, 403);
    for (
      const extra of [
        { action },
        { account_no: "PRIVATE" },
        { client_code: "PRIVATE" },
        { authority: true },
        { request: source(action).request },
      ]
    ) {
      assertEquals(
        (await s.invoke({ event_outbox_id: EVENT, ...extra })).status,
        400,
      );
    }
    assertEquals(s.sequence, []);
  });
  Deno.test(`B07 ${action} no claim means no HTTP`, async () => {
    const s = setup(action, { noClaim: true });
    assertEquals((await s.invoke()).status, 404);
    assertEquals(s.sent, []);
  });
  Deno.test(`B07 ${action} substituted path and payload fail closed`, () => {
    assertThrows(() =>
      serializeRequest({ ...source(action), path: "https://example.invalid" })
    );
    assertThrows(() =>
      serializeRequest({ ...source(action), request: { arbitrary: true } })
    );
  });
}
const config = {
  environment: "DEV" as const,
  allowedReadApis: [],
  baseUrl: "https://nseinvestuat.nseindia.com",
  loginUserId: "test",
  apiKeyMember: "test",
  apiSecretUser: "test",
  memberCode: "test",
  userAgent: "test",
};
Deno.test("B07 rejects Production configuration before HTTP", () => {
  assertThrows(() =>
    gateway({ ...config, baseUrl: "https://www.nseinvest.com" })
  );
  assertThrows(() =>
    gateway({ ...config, baseUrl: config.baseUrl + "/alternate" })
  );
});
Deno.test("B07 gateway captures exact bytes and disables redirects", async () => {
  let calls = 0;
  const body = new Uint8Array([0, 255, 10]);
  const send = gateway(config, (_url, init) => {
    calls++;
    assertEquals(init?.redirect, "error");
    return Promise.resolve(new Response(body, { status: 200 }));
  });
  const s = source("BANK_ADD");
  const result = await send(serializeRequest(s), s);
  assertEquals(result.bodyBase64, btoa(String.fromCharCode(...body)));
  assertEquals(result.delivery, "SENT_WITH_RESULT");
  assertEquals(calls, 1);
});
Deno.test("B07 pre-transport body mismatch is PROVEN_NOT_SENT", async () => {
  let calls = 0;
  const send = gateway(config, () => {
    calls++;
    throw new Error("must not send");
  });
  assertEquals(
    (await send("{}", source("BANK_ADD"))).delivery,
    "PROVEN_NOT_SENT",
  );
  assertEquals(calls, 0);
});
Deno.test("B07 fetch failure is always MAYBE_SENT", async () => {
  const send = gateway(config, () => Promise.reject(new Error("PRIVATE")));
  const s = source("MANDATE");
  assertEquals((await send(serializeRequest(s), s)).delivery, "MAYBE_SENT");
});
