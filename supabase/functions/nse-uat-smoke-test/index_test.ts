import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { NseClientError } from "../_shared/nse/nse_client.ts";
import { createNseUatSmokeTestHandler } from "./handler.ts";

const token = "test-server-token";

function request(smokeTestToken?: string): Request {
  const headers = new Headers();
  if (smokeTestToken != null) {
    headers.set("X-NSE-Smoke-Token", smokeTestToken);
  }
  return new Request("http://localhost/nse-uat-smoke-test", {
    method: "POST",
    headers,
  });
}

Deno.test("NSE UAT smoke test requires the dedicated smoke token", async () => {
  let called = false;
  const handler = createNseUatSmokeTestHandler({
    smokeTestToken: token,
    execute: () => {
      called = true;
      return Promise.reject(new Error("must not run"));
    },
  });

  const response = await handler(request());
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: { code: "not_authorized" } });
  assertFalse(called);
});

Deno.test("NSE UAT smoke test rejects an incorrect smoke token", async () => {
  let called = false;
  const handler = createNseUatSmokeTestHandler({
    smokeTestToken: token,
    execute: () => {
      called = true;
      return Promise.reject(new Error("must not run"));
    },
  });

  const response = await handler(request(`${token}-incorrect`));
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: { code: "not_authorized" } });
  assertFalse(called);
});

Deno.test("NSE UAT smoke test fails closed without a configured token", async () => {
  let called = false;
  const handler = createNseUatSmokeTestHandler({
    smokeTestToken: "",
    execute: () => {
      called = true;
      return Promise.reject(new Error("must not run"));
    },
  });

  const response = await handler(request(""));
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: { code: "not_authorized" } });
  assertFalse(called);
});

Deno.test("NSE UAT smoke test returns bounded sanitized diagnostics", async () => {
  const handler = createNseUatSmokeTestHandler({
    smokeTestToken: token,
    execute: () =>
      Promise.resolve({
        status: 200,
        headers: new Headers({ "Content-Type": "text/plain" }),
        body: new TextEncoder().encode(`NAV\u0000${"x".repeat(300)}`),
      }),
  });

  const response = await handler(request(token));
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.success, true);
  assertEquals(body.nseStatus, 200);
  assertEquals(body.responseBytes, 304);
  assertEquals(body.contentType, "text/plain");
  assertEquals(body.preview.length, 200);
  assertFalse(body.preview.includes("\u0000"));
});

Deno.test("NSE UAT smoke test maps NSE failures without provider details", async () => {
  const handler = createNseUatSmokeTestHandler({
    smokeTestToken: token,
    execute: () => Promise.reject(new NseClientError("nse_http_error", 401)),
  });

  const response = await handler(request(token));
  assertEquals(response.status, 502);
  assertEquals(await response.json(), {
    success: false,
    nseStatus: 401,
    error: { code: "nse_http_error" },
  });
});
