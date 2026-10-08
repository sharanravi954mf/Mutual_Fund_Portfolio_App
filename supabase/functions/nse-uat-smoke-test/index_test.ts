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
        safeHeaderMetadata: { content_type: "text/plain" },
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

Deno.test("QA certification probe needs its own token and explicit approval; caller cannot select writes", async () => {
  const { loadNseConfig } = await import("../_shared/nse/nse_config.ts");
  const { createConfiguredNseSmokeTestHandler } = await import("./handler.ts");
  for (const allowedReadApis of ["[]", '["MASTER_DOWNLOAD"]']) {
    const values: Record<string, string> = {
      MONEYBOWL_ENV: "QA",
      MONEYBOWL_SUPABASE_URL: "https://qa-synthetic.supabase.co",
      SUPABASE_URL: "https://qa-synthetic.supabase.co",
      NSE_URL: "https://www.nseinvest.com",
      NSE_CREDENTIAL_PROVIDER: "edge-secrets",
      NSE_ALLOWED_READ_APIS: allowedReadApis,
      NSE_LOGIN_USER_ID: "synthetic-login",
      NSE_API_KEY_MEMBER: "synthetic-key",
      NSE_API_SECRET_USER: "synthetic-secret",
      NSE_MEMBER_CODE: "synthetic-member",
    };
    const config = await loadNseConfig((key) => values[key]);
    let sends = 0;
    const handler = createConfiguredNseSmokeTestHandler(
      config,
      "synthetic-qa-token",
      (_url, init) => {
        sends++;
        assertEquals(
          String(_url),
          "https://www.nseinvest.com/nsemfdesk/api/v2/reports/MASTER_DOWNLOAD",
        );
        assertEquals(init?.method, "POST");
        assertEquals(init?.body, '{"file_type":"NAV"}');
        assertEquals(init?.redirect, "error");
        return Promise.resolve(
          new Response("synthetic-secret", {
            headers: { "content-type": "synthetic-secret" },
          }),
        );
      },
    );
    assertEquals((await handler(request("dev-token"))).status, 403);
    assertEquals(sends, 0);
    const response = await handler(
      new Request("http://localhost/nse-uat-smoke-test", {
        method: "POST",
        headers: { "X-NSE-Smoke-Token": "synthetic-qa-token" },
        body: JSON.stringify({
          path: "/nsemfdesk/api/v1/EKYC/EKYCREG",
          file_type: "SCH",
        }),
      }),
    );
    if (allowedReadApis === "[]") {
      assertEquals(response.status, 502);
      assertEquals(sends, 0);
    } else {
      assertEquals(response.status, 200);
      assertEquals(sends, 1);
    }
    assertFalse((await response.text()).includes("synthetic-secret"));
  }
});
