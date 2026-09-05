import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { createVerificationPersistence } from "./adapters.ts";
import { createNseUccReconciliationHandler } from "./handler.ts";
import type { VerificationPersistence } from "./types.ts";

const TOKEN = "synthetic-token";
const EVENT = "10000000-0000-4000-8000-000000000001";
const OPERATION = "10000000-0000-4000-8000-000000000002";
const TARGET = "10000000-0000-4000-8000-000000000003";
const CLAIM = "10000000-0000-4000-8000-000000000004";
const CALL = "10000000-0000-4000-8000-000000000005";
function persistenceWithClaimResponse(data: unknown) {
  return createVerificationPersistence({
    rpc(name: string) {
      assertEquals(name, "claim_nse_ucc_verification_event");
      return Promise.resolve({ data, error: null });
    },
  } as never);
}
function invocation(body = JSON.stringify({ event_outbox_id: EVENT })) {
  return new Request("http://localhost", {
    method: "POST",
    headers: {
      authorization: "Bearer " + TOKEN,
      "content-type": "application/json",
    },
    body,
  });
}
function setup(
  options: {
    match?: boolean;
    failure?: boolean;
    httpStatus?: number;
    attempt?: number;
    maxAttempts?: number;
    noEvent?: boolean;
    purpose?:
      | "POST_REGISTRATION_VERIFICATION"
      | "AMBIGUOUS_WRITE_RECONCILIATION";
  } = {},
) {
  const sequence: string[] = [];
  const finishes: Array<Parameters<VerificationPersistence["finish"]>[0]> = [];
  let audited = "";
  let transmitted = "";
  let loadedOperationId = "";
  const attempt = options.attempt ?? 1;
  const persistence: VerificationPersistence = {
    recoverExpired: () => {
      sequence.push("recover");
      return Promise.resolve({});
    },
    claimEvent: () => {
      sequence.push("claim");
      if (options.noEvent) {
        return Promise.resolve({
          event_outbox_id: null,
          integration_operation_id: null,
          correlation_id: null,
          attempt: 0,
          claim_state: "no_event" as const,
          claim_token: null,
        });
      }
      return Promise.resolve({
        event_outbox_id: EVENT,
        integration_operation_id: OPERATION,
        correlation_id: CALL,
        attempt,
        claim_state: attempt === 1
          ? "newly_claimed" as const
          : "safe_retry_claimed" as const,
        claim_token: CLAIM,
      });
    },
    loadSource: (operationId) => {
      loadedOperationId = operationId;
      return Promise.resolve({
        operation_id: OPERATION,
        target_operation_id: TARGET,
        workspace_id: CALL,
        integration_account_id: CALL,
        correlation_id: CALL,
        verification_purpose: options.purpose ??
          "POST_REGISTRATION_VERIFICATION",
        intended_client_code: "MBUAT0001",
        pan: "AAAAA0000A",
      });
    },
    start: (input) => {
      sequence.push("request");
      audited = input.requestPayload;
      return Promise.resolve({});
    },
    finish: (input) => {
      sequence.push("result");
      finishes.push(input);
      return Promise.resolve({});
    },
    distribute: () => {
      sequence.push("distribute");
      return Promise.resolve({});
    },
  };
  const handler = createNseUccReconciliationHandler({
    internalToken: TOKEN,
    persistence,
    gateway: {
      requestHeaderMetadata: () => ({
        content_type: "application/json",
        user_agent: "MoneyBowl-Test",
        accept: "application/json",
      }),
      submit: (body) => {
        transmitted = body;
        sequence.push("transport");
        if (options.failure) {
          return Promise.resolve({
            kind: "failure" as const,
            errorCategory: "nse_request_timeout",
            timeout: true,
            networkFailure: false,
          });
        }
        return Promise.resolve({
          kind: "response" as const,
          status: options.httpStatus ?? 200,
          contentType: "application/json",
          safeHeaderMetadata: { content_type: "application/json" },
          rawBody: JSON.stringify({
            response_status: "S",
            report_data: [{
              client_code: options.match === false ? "OTHER0001" : "MBUAT0001",
              primary_holder_pan: "AAAAA0000A",
            }],
          }),
        });
      },
    },
    maxAttempts: options.maxAttempts ?? 3,
    now: (() => {
      const values = [
        new Date("2026-09-02T00:00:00Z"),
        new Date("2026-09-02T00:00:00.010Z"),
      ];
      let i = 0;
      return () => values[i++] ?? values[1];
    })(),
    uuid: () => CALL,
  });
  return {
    handler,
    sequence,
    finishes,
    audited: () => audited,
    transmitted: () => transmitted,
    loadedOperationId: () => loadedOperationId,
  };
}
Deno.test("verification requires explicit event and recovers before claim", async () => {
  const c = setup();
  assertEquals((await c.handler(invocation("{}"))).status, 400);
  assertEquals(c.sequence, []);
  assertEquals((await c.handler(invocation())).status, 200);
  assertEquals(c.sequence.slice(0, 2), ["recover", "claim"]);
});
Deno.test("verification sends exact audited body without PAN", async () => {
  const c = setup();
  assertEquals((await c.handler(invocation())).status, 200);
  assertEquals(c.audited(), c.transmitted());
  assertFalse(c.transmitted().includes("AAAAA0000A"));
  assertEquals(JSON.parse(c.transmitted()), {
    client_code: "MBUAT0001",
    PAN: "",
    from_date: "",
    to_date: "",
  });
  assertEquals(c.sequence, [
    "recover",
    "claim",
    "request",
    "transport",
    "result",
    "distribute",
  ]);
  assertEquals(c.loadedOperationId(), OPERATION);
});
Deno.test("valid claimed event does not become requested_event_not_found", async () => {
  const c = setup();
  const response = await c.handler(invocation());
  assertEquals(response.status, 200);
  assertEquals((await response.json()).data.outcome, "identity_confirmed");
  assertEquals(c.loadedOperationId(), OPERATION);
});
Deno.test("true no_event does not load source or call the NSE gateway", async () => {
  const c = setup({ noEvent: true });
  assertEquals((await c.handler(invocation())).status, 404);
  assertEquals(c.sequence, ["recover", "claim"]);
  assertEquals(c.loadedOperationId(), "");
  assertEquals(c.transmitted(), "");
});
Deno.test("verification claim unwraps a table RPC row", async () => {
  const persistence = persistenceWithClaimResponse([{
    event_outbox_id: EVENT,
    integration_operation_id: OPERATION,
    correlation_id: CALL,
    attempt: 1,
    claim_state: "newly_claimed",
    claim_token: CLAIM,
  }]);
  assertEquals(
    await persistence.claimEvent({
      eventOutboxId: EVENT,
      maxAttempts: 3,
      leaseSeconds: 120,
    }),
    {
      event_outbox_id: EVENT,
      integration_operation_id: OPERATION,
      correlation_id: CALL,
      attempt: 1,
      claim_state: "newly_claimed",
      claim_token: CLAIM,
    },
  );
});
Deno.test("verification claim maps empty table results to no_event", async () => {
  for (const data of [[], null]) {
    const persistence = persistenceWithClaimResponse(data);
    assertEquals(
      await persistence.claimEvent({
        eventOutboxId: EVENT,
        maxAttempts: 3,
        leaseSeconds: 120,
      }),
      {
        event_outbox_id: null,
        integration_operation_id: null,
        correlation_id: null,
        attempt: 0,
        claim_state: "no_event",
        claim_token: null,
      },
    );
  }
});
Deno.test("no match is distributed without resolving in worker", async () => {
  const c = setup({ match: false, purpose: "AMBIGUOUS_WRITE_RECONCILIATION" });
  assertEquals((await c.handler(invocation())).status, 202);
  assertEquals(c.finishes[0].normalizedOutcome, "BUSINESS_FAILURE");
  assertEquals(c.sequence.at(-1), "distribute");
});
Deno.test("read gateway failure is truthful retryable transport failure", async () => {
  const c = setup({ failure: true });
  assertEquals((await c.handler(invocation())).status, 202);
  assertEquals(c.finishes[0].normalizedOutcome, "TRANSPORT_FAILURE");
  assertEquals(c.finishes[0].timeoutOccurred, true);
  assertEquals(c.sequence, [
    "recover",
    "claim",
    "request",
    "transport",
    "result",
  ]);
});

for (const status of [408, 429, 500, 502, 503, 504]) {
  Deno.test(`HTTP ${status} is a retryable read failure while attempts remain`, async () => {
    const c = setup({ httpStatus: status, attempt: 1, maxAttempts: 3 });
    const response = await c.handler(invocation());
    assertEquals(response.status, 202);
    assertEquals(
      (await response.json()).data.outcome,
      "safe_read_retry_available",
    );
    assertEquals(c.finishes[0].normalizedOutcome, "HTTP_FAILURE");
    assertEquals(c.sequence.at(-1), "result");
  });
}

for (const status of [400, 403]) {
  Deno.test(`HTTP ${status} remains a terminal verification HTTP failure`, async () => {
    const c = setup({ httpStatus: status, attempt: 1, maxAttempts: 3 });
    const response = await c.handler(invocation());
    assertEquals(response.status, 502);
    assertEquals(
      (await response.json()).data.outcome,
      "identity_not_confirmed",
    );
    assertEquals(c.finishes[0].normalizedOutcome, "HTTP_FAILURE");
    assertEquals(c.sequence.at(-1), "distribute");
  });
}

Deno.test("retryable HTTP failure at the attempt limit is exhausted without distribution", async () => {
  const c = setup({ httpStatus: 503, attempt: 3, maxAttempts: 3 });
  const response = await c.handler(invocation());
  assertEquals(response.status, 502);
  assertEquals(
    (await response.json()).data.outcome,
    "verification_http_attempts_exhausted",
  );
  assertEquals(c.finishes[0].normalizedOutcome, "HTTP_FAILURE");
  assertEquals(c.sequence.at(-1), "result");
});
