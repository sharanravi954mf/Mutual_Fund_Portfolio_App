import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  type Claim,
  createOnboardingKycHandler,
  type Dependencies,
} from "./handler.ts";
import { createOnboardingTransport } from "./adapters.ts";
const claim: Claim = {
  operation_id: "operation",
  claim_token: "claim",
  call_id: "call",
  api: "EKYCREG",
  request: JSON.stringify({
    amcCode: "TEST",
    panNo: "ZZZPZ0001Z",
    invEmail: "fixture@example.test",
    mobileNo: "9000000000",
  }),
};
const event = "10000000-0000-4000-8000-000000000001";
const request = (body: unknown = { event_outbox_id: event }, token = "local") =>
  new Request("https://worker.invalid", {
    method: "POST",
    headers: { authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
function fixture() {
  const calls: string[] = [];
  const deps: Dependencies = {
    token: "local",
    claim: async () => {
      calls.push("claim");
      return claim;
    },
    start: async () => {
      calls.push("start");
    },
    submit: async () => {
      calls.push("send");
      return {
        bytes: new Uint8Array([123, 125]),
        status: 200,
        transmission: "SENT_WITH_RESULT",
      };
    },
    finish: async (_, r) => {
      calls.push(r.transmission);
    },
  };
  return { calls, deps };
}
Deno.test("onboarding worker rejects transport fields and unrelated callers", async () => {
  const { deps, calls } = fixture();
  const handler = createOnboardingKycHandler(deps);
  assertEquals((await handler(request({}, "wrong"))).status, 403);
  assertEquals(
    (await handler(request({ event_outbox_id: event, panNo: "ZZZPZ0002Z" })))
      .status,
    400,
  );
  assertEquals(calls, []);
});
Deno.test("onboarding worker persists before exactly one send; lost finish retries evidence only", async () => {
  const { deps, calls } = fixture();
  let finishes = 0;
  deps.finish = async () => {
    calls.push("finish");
    if (++finishes === 1) throw new Error("lost database acknowledgement");
  };
  const response = await createOnboardingKycHandler(deps)(request());
  assertEquals(response.status, 200);
  assertEquals(calls, ["claim", "start", "send", "finish", "finish"]);
  assertEquals(await response.json(), { code: "evidence_recorded" });
});
Deno.test("failed request evidence never sends; errors never expose secrets", async () => {
  const { deps, calls } = fixture();
  deps.start = async () => {
    throw new Error(claim.request);
  };
  const response = await createOnboardingKycHandler(deps)(request());
  assertEquals(response.status, 503);
  assertEquals(calls, ["claim"]);
  assertEquals(await response.json(), {
    code: "onboarding_worker_unavailable",
  });
});
Deno.test("unexpected transport exception becomes MAYBE_SENT without a second call", async () => {
  const { deps, calls } = fixture();
  deps.submit = async () => {
    calls.push("send");
    throw new Error("lost response");
  };
  await createOnboardingKycHandler(deps)(request());
  assertEquals(calls, ["claim", "start", "send", "MAYBE_SENT"]);
});
Deno.test("claim recovery owns replay; terminal claim does not submit", async () => {
  const { deps, calls } = fixture();
  deps.claim = async () => null;
  assertEquals((await createOnboardingKycHandler(deps)(request())).status, 200);
  assertEquals(calls, []);
});
const config = {
  environment: "DEV" as const,
  allowedReadApis: [],
  baseUrl: "https://nseinvestuat.nseindia.com",
  loginUserId: "synthetic",
  apiKeyMember: "synthetic",
  apiSecretUser: "synthetic",
  memberCode: "synthetic",
  userAgent: "synthetic",
};
Deno.test("pre-UCC transport exact body and endpoint; no redirect, raw bytes retained", async () => {
  const transport = createOnboardingTransport(
    config,
    ((_url, init) => {
      assertEquals(
        String(_url),
        config.baseUrl + "/nsemfdesk/api/v1/EKYC/EKYCREG",
      );
      assertEquals(init?.body, claim.request);
      assertEquals(init?.redirect, "error");
      return Promise.resolve(
        new Response(new Uint8Array([0xff, 0xfe]), { status: 200 }),
      );
    }) as typeof fetch,
  );
  const result = await transport(claim);
  assertEquals(result.transmission, "SENT_WITH_RESULT");
  assertEquals(result.bytes, new Uint8Array([0xff, 0xfe]));
});
Deno.test("network loss after invocation is MAYBE_SENT; no automatic retry", async () => {
  let count = 0;
  const transport = createOnboardingTransport(
    config,
    (() => {
      count++;
      throw new Error("network failure");
    }) as typeof fetch,
  );
  assertEquals((await transport(claim)).transmission, "MAYBE_SENT");
  assertEquals(count, 1);
});
Deno.test("transport refuses Production and browser URL overrides", async () => {
  for (
    const baseUrl of [
      "https://nseinvest.nseindia.com",
      "https://evil.example",
      "https://nseinvestuat.nseindia.com/other",
    ]
  ) {
    await assertRejects(async () => {
      createOnboardingTransport({ ...config, baseUrl });
    });
  }
  assert(
    (await createOnboardingTransport(config)({
      ...claim,
      api: "invalid" as Claim["api"],
    })).transmission === "PROVEN_NOT_SENT",
  );
});
