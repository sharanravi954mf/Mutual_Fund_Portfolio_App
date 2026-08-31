import {
  assertEquals,
  assertFalse,
  assertNotEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { NseClient, NseClientError } from "./nse_client.ts";
import type { NseConfig } from "./nse_types.ts";

const config: NseConfig = {
  baseUrl: "https://nse-uat.example.test",
  loginUserId: "test-login-user",
  apiKeyMember: "test-api-key-member",
  apiSecretUser: "test-api-secret-user",
  memberCode: "test-member-code",
  userAgent: "MoneyBowl-NSE-UAT/1.0",
};

Deno.test("NSE client applies fresh authentication and standard JSON headers", async () => {
  const requests: Request[] = [];
  const client = new NseClient(config, (input, init) => {
    requests.push(new Request(input, init));
    return Promise.resolve(
      new Response("NAV data", {
        status: 200,
        headers: { "Content-Type": "text/plain" },
      }),
    );
  });

  for (let call = 0; call < 2; call += 1) {
    const response = await client.request({
      method: "POST",
      path: "/nsemfdesk/api/v2/reports/MASTER_DOWNLOAD",
      jsonBody: { file_type: "NAV" },
    });
    assertEquals(new TextDecoder().decode(response.body), "NAV data");
  }

  assertEquals(
    requests[0].url,
    "https://nse-uat.example.test/nsemfdesk/api/v2/reports/MASTER_DOWNLOAD",
  );
  assertEquals(requests[0].headers.get("accept-language"), "en-US");
  assertEquals(
    requests.map((request) => request.headers.get("user-agent")),
    [config.userAgent, config.userAgent],
  );
  assertEquals(requests[0].headers.get("referer"), "www.google.com");
  assertEquals(requests[0].headers.get("memberid"), "test-member-code");
  assertEquals(requests[0].headers.get("content-type"), "application/json");
  assertEquals(await requests[0].json(), { file_type: "NAV" });
  assertFalse(
    requests[0].headers.get("authorization")?.includes(
      "test-api-secret-user",
    ) ?? true,
  );
  assertNotEquals(
    requests[0].headers.get("authorization"),
    requests[1].headers.get("authorization"),
  );
});

Deno.test("NSE client maps provider errors without exposing response content", async () => {
  const client = new NseClient(
    config,
    () =>
      Promise.resolve(new Response("provider-secret-detail", { status: 401 })),
  );

  const error = await assertRejects(
    () =>
      client.request({
        method: "POST",
        path: "/nsemfdesk/api/v2/reports/MASTER_DOWNLOAD",
        jsonBody: { file_type: "NAV" },
      }),
    NseClientError,
  );
  assertEquals(error.code, "nse_http_error");
  assertEquals(error.nseStatus, 401);
  assertFalse(error.message.includes("provider-secret-detail"));
});

Deno.test("NSE client maps request timeouts safely", async () => {
  const client = new NseClient(
    config,
    (_input, init) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener(
          "abort",
          () => reject(init.signal?.reason),
          { once: true },
        );
      }),
  );

  const error = await assertRejects(
    () =>
      client.request({
        method: "POST",
        path: "/nsemfdesk/api/v2/reports/MASTER_DOWNLOAD",
        jsonBody: { file_type: "NAV" },
        timeoutMs: 5,
      }),
    NseClientError,
  );
  assertEquals(error.code, "nse_request_timeout");
  assertEquals(error.nseStatus, null);
});
