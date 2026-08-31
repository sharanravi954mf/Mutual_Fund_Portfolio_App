import {
  assertEquals,
  assertFalse,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { loadNseConfig, NseConfigError } from "./nse_config.ts";

const completeEnvironment: Record<string, string> = {
  NSE_URL: "https://nse-uat.example.test/",
  NSE_LOGIN_USER_ID: "test-login-user",
  NSE_API_KEY_MEMBER: "test-api-key-member",
  NSE_API_SECRET_USER: "test-api-secret-user",
  NSE_MEMBER_CODE: "test-member-code",
};

function environment(values: Record<string, string | undefined>) {
  return (name: string): string | undefined => values[name];
}

Deno.test("NSE configuration loads required server-side values", () => {
  const config = loadNseConfig(environment(completeEnvironment));

  assertEquals(config.baseUrl, "https://nse-uat.example.test");
  assertEquals(config.loginUserId, "test-login-user");
  assertEquals(config.memberCode, "test-member-code");
  assertEquals(
    config.userAgent,
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:108.0) Gecko/20100101 Firefox/108.0",
  );
});

Deno.test("NSE configuration allows the User-Agent to be overridden", () => {
  const config = loadNseConfig(environment({
    ...completeEnvironment,
    NSE_USER_AGENT: "MoneyBowl-NSE-UAT/1.0",
  }));

  assertEquals(config.userAgent, "MoneyBowl-NSE-UAT/1.0");
});

Deno.test("NSE configuration reports missing variable names without secret values", () => {
  const values = {
    ...completeEnvironment,
    NSE_API_KEY_MEMBER: undefined,
    NSE_API_SECRET_USER: "must-not-appear-in-errors",
  };

  const error = assertThrows(
    () => loadNseConfig(environment(values)),
    NseConfigError,
  );
  assertEquals(error.missingVariables, ["NSE_API_KEY_MEMBER"]);
  assertFalse(error.message.includes("must-not-appear-in-errors"));
  assertFalse(error.message.includes(completeEnvironment.NSE_LOGIN_USER_ID));
});

Deno.test("NSE configuration rejects malformed or non-HTTPS URLs safely", () => {
  const secretInUrl = "secret-host-material";
  const error = assertThrows(
    () =>
      loadNseConfig(environment({
        ...completeEnvironment,
        NSE_URL: `http://${secretInUrl}.example.test`,
      })),
    NseConfigError,
  );

  assertEquals(error.code, "nse_configuration_invalid");
  assertFalse(error.message.includes(secretInUrl));
});
