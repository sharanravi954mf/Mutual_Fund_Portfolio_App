import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import type { NseUccSource } from "../_shared/nse/nse_ucc.ts";
import { createNseUccWorkerHandler } from "./handler.ts";
import type {
  ClaimedUccEvent,
  GatewayFailure,
  GatewayResponse,
  UccPersistence,
} from "./types.ts";
import { UccSourcePersistenceError } from "./types.ts";

const TOKEN = "synthetic-worker-token";
const EVENT_ID = "10000000-0000-4000-8000-000000000001";
const OPERATION_ID = "10000000-0000-4000-8000-000000000002";
const CLAIM_TOKEN = "10000000-0000-4000-8000-000000000003";
const CALL_ID = "10000000-0000-4000-8000-000000000004";
const safeRequestHeaders = {
  content_type: "application/json",
  user_agent: "MoneyBowl-UAT-Test",
  accept: "application/json",
};
const safeResponseHeaders = {
  content_type: "application/json",
  x_request_id: "synthetic-request",
};

function syntheticUccSource(): NseUccSource {
  return {
    operation_id: OPERATION_ID,
    workspace_id: "10000000-0000-4000-8000-000000000005",
    integration_account_id: "10000000-0000-4000-8000-000000000006",
    correlation_id: "10000000-0000-4000-8000-000000000007",
    external_account_candidate: "MBUAT0001",
    registration_mode: "physical",
    investor_kind: "individual",
    legal_first_name: "MONEYBOWL",
    legal_middle_name: "",
    legal_last_name: "SYNTHETIC",
    date_of_birth: "01/01/1990",
    gender: "other",
    residency: "resident_individual",
    occupation: "other",
    holding_mode: "single",
    pan_exempt: false,
    pan: "ZZZPZ0000Z",
    kyc_method: "kra",
    kyc_verified: true,
    ckyc_number: "",
    communication_preference: "electronic",
    mobile_owner_relationship: "self",
    email_owner_relationship: "self",
    onboarding_mode: "paper",
    nomination_opted_in: false,
    email: "worker-fixture@moneybowl.invalid",
    mobile: "0000000000",
    address: {
      line_1: "SYNTHETIC UAT ADDRESS",
      line_2: "",
      line_3: "",
      city: "UATCITY",
      region: "KARNATAKA",
      postal_code: "000000",
      country: "INDIA",
    },
    bank: {
      account_type: "savings",
      account_number: "TESTACCOUNT01",
      ifsc_code: "TEST0000000",
      micr_code: "",
      account_holder_name: "MONEYBOWL SYNTHETIC",
    },
    nse_codes: {
      tax_status: "01",
      occupation_code: "08",
      state: "KA",
      country: "INDIA",
      mobile_declaration_flag: "SE",
      email_declaration_flag: "SE",
      div_pay_mode: "04",
    },
  };
}
function event(attempt = 1): ClaimedUccEvent {
  return {
    event_outbox_id: EVENT_ID,
    integration_operation_id: OPERATION_ID,
    payload: { integration_operation_id: OPERATION_ID },
    correlation_id: "10000000-0000-4000-8000-000000000007",
    attempt,
    claim_state: attempt === 1 ? "newly_claimed" : "safe_retry_claimed",
    claim_token: CLAIM_TOKEN,
    claim_expires_at: "2026-09-01T12:02:00.000Z",
  };
}
function response(
  status: number,
  clientCode = "MBUAT0001",
  businessStatus = "REG_SUCCESS",
): GatewayResponse {
  return {
    kind: "response",
    status,
    contentType: "application/json",
    safeHeaderMetadata: safeResponseHeaders,
    rawBody: JSON.stringify({
      reg_details: [{
        client_code: clientCode,
        reg_id: "SYNTHETIC-REG",
        reg_status: businessStatus,
        reg_remark: businessStatus === "REG_SUCCESS" ? "" : "synthetic failure",
      }],
    }),
  };
}
type Start = Parameters<UccPersistence["startSubmission"]>[0];
type Finish = Parameters<UccPersistence["finishSubmission"]>[0];
function setup(
  options: {
    attempt?: number;
    result?: GatewayResponse | GatewayFailure;
    failStartOnce?: boolean;
    failFinishOnce?: boolean;
    sourceMutation?: (source: ReturnType<typeof syntheticUccSource>) => void;
    sourceFailure?: Error;
  } = {},
) {
  const starts: Start[] = [];
  const finishes: Finish[] = [];
  const sequence: string[] = [];
  let startFailures = options.failStartOnce ? 1 : 0;
  let finishFailures = options.failFinishOnce ? 1 : 0;
  const source = syntheticUccSource();
  options.sourceMutation?.(source);
  const persistence: UccPersistence = {
    recoverExpired: () => {
      sequence.push("recover");
      return Promise.resolve();
    },
    claimEvent: () => {
      sequence.push("claim");
      return Promise.resolve(event(options.attempt ?? 1));
    },
    loadSource: () =>
      options.sourceFailure
        ? Promise.reject(options.sourceFailure)
        : Promise.resolve(source),
    startSubmission: (input) => {
      sequence.push("request_evidence");
      starts.push(input);
      if (startFailures-- > 0) return Promise.reject(new Error("transient"));
      return Promise.resolve({});
    },
    finishSubmission: (input) => {
      sequence.push("result_evidence");
      finishes.push(input);
      if (finishFailures-- > 0) return Promise.reject(new Error("transient"));
      return Promise.resolve({});
    },
    failPreparation: () => {
      sequence.push("validation_failure");
      return Promise.resolve();
    },
  };
  let gatewayCalls = 0;
  const gateway = {
    requestHeaderMetadata: () => safeRequestHeaders,
    submit: (serializedRequest: string) => {
      gatewayCalls++;
      sequence.push("gateway");
      if (starts.at(-1)?.requestPayload !== serializedRequest) {
        return Promise.reject(
          new Error("audited_and_transmitted_body_mismatch"),
        );
      }
      return Promise.resolve(options.result ?? response(200));
    },
  };
  let time = 0;
  const times = [
    new Date("2026-09-01T12:00:00Z"),
    new Date("2026-09-01T12:00:00.125Z"),
  ];
  const handler = createNseUccWorkerHandler({
    internalToken: TOKEN,
    persistence,
    gateway,
    maxAttempts: 2,
    now: () => times[time++] ?? times[1],
    uuid: () => CALL_ID,
  });
  return {
    handler,
    starts,
    finishes,
    sequence,
    gatewayCalls: () => gatewayCalls,
  };
}
function request(): Request {
  return new Request("http://localhost/worker", {
    method: "POST",
    headers: {
      authorization: "Bearer " + TOKEN,
      "content-type": "application/json",
    },
    body: JSON.stringify({ event_outbox_id: EVENT_ID }),
  });
}

Deno.test("worker records immutable request before the single gateway call and result after", async () => {
  const c = setup();
  assertEquals((await c.handler(request())).status, 200);
  assertEquals(c.sequence, [
    "recover",
    "claim",
    "request_evidence",
    "gateway",
    "result_evidence",
  ]);
  assertEquals(c.gatewayCalls(), 1);
  assertEquals(c.starts[0].requestHeaderMetadata, safeRequestHeaders);
  assertEquals(c.finishes[0].responseHeaderMetadata, safeResponseHeaders);
  assertEquals(c.finishes[0].normalizedOutcome, "SUCCESS");
});
Deno.test("idempotent persistence retry never repeats NSE transport", async () => {
  const c = setup({ failStartOnce: true, failFinishOnce: true });
  assertEquals((await c.handler(request())).status, 200);
  assertEquals(c.gatewayCalls(), 1);
  assertEquals(c.starts.length, 2);
  assertEquals(c.starts[0], c.starts[1]);
  assertEquals(c.finishes.length, 2);
  assertEquals(c.finishes[0], c.finishes[1]);
});
Deno.test("HTTP 200 business failure stays distinct", async () => {
  const c = setup({ result: response(200, "MBUAT0001", "REG_FAILED") });
  assertEquals((await c.handler(request())).status, 422);
  assertEquals(c.finishes[0].normalizedOutcome, "BUSINESS_FAILURE");
});
for (const status of [400, 403]) {
  Deno.test(`HTTP ${status} is definitive`, async () => {
    const c = setup({ result: response(status) });
    assertEquals((await c.handler(request())).status, 502);
    assertEquals(c.finishes[0].normalizedOutcome, "HTTP_FAILURE");
  });
}
for (const status of [500, 503]) {
  Deno.test(`HTTP ${status} is ambiguous`, async () => {
    const c = setup({ result: response(status) });
    assertEquals((await c.handler(request())).status, 202);
    assertEquals(c.finishes[0].normalizedOutcome, "AMBIGUOUS");
  });
}
Deno.test("two proven NOT_SENT failures exhaust retry state", async () => {
  const failure: GatewayFailure = {
    kind: "failure",
    delivery: "NOT_SENT",
    errorCategory: "synthetic_not_sent",
    timeout: false,
    networkFailure: true,
  };
  const first = setup({ attempt: 1, result: failure });
  let body = await (await first.handler(request())).json();
  assertEquals(body.data.outcome, "safe_retry_available");
  const final = setup({ attempt: 2, result: failure });
  body = await (await final.handler(request())).json();
  assertEquals(body.data.outcome, "submission_failed");
});
Deno.test("MAYBE_SENT transport failure requires reconciliation", async () => {
  const c = setup({
    result: {
      kind: "failure",
      delivery: "MAYBE_SENT",
      errorCategory: "timeout",
      timeout: true,
      networkFailure: true,
    },
  });
  assertEquals((await c.handler(request())).status, 202);
  assertEquals(c.finishes[0].normalizedOutcome, "AMBIGUOUS");
});
Deno.test("REG_SUCCESS client code mismatch requires reconciliation", async () => {
  const c = setup({ result: response(200, "DIFFERENT1") });
  assertEquals((await c.handler(request())).status, 202);
  assertEquals(c.finishes[0].normalizedOutcome, "AMBIGUOUS");
  assertEquals(c.finishes[0].errorCategory, "nse_client_code_mismatch");
});
Deno.test("unsupported source fails locally before request evidence", async () => {
  const c = setup({
    sourceMutation: (source) => source.investor_kind = "non_individual",
  });
  assertEquals((await c.handler(request())).status, 422);
  assertEquals(c.gatewayCalls(), 0);
  assertEquals(c.starts.length, 0);
  assertEquals(c.sequence.includes("validation_failure"), true);
});

Deno.test("malformed or missing event input never claims an arbitrary event", async () => {
  const c = setup();
  const malformed = new Request("http://localhost/worker", {
    method: "POST",
    headers: { authorization: "Bearer " + TOKEN },
    body: "{",
  });
  assertEquals((await c.handler(malformed)).status, 400);
  const missing = new Request("http://localhost/worker", {
    method: "POST",
    headers: {
      authorization: "Bearer " + TOKEN,
      "content-type": "application/json",
    },
    body: "{}",
  });
  assertEquals((await c.handler(missing)).status, 400);
  assertEquals(c.sequence, []);
});

Deno.test("source infrastructure failure remains recoverable and is not validation failure", async () => {
  const c = setup({ sourceFailure: new UccSourcePersistenceError() });
  assertEquals((await c.handler(request())).status, 503);
  assertEquals(c.gatewayCalls(), 0);
  assertEquals(c.starts.length, 0);
  assertEquals(c.sequence, ["recover", "claim"]);
  assertEquals(c.sequence.includes("validation_failure"), false);
});
