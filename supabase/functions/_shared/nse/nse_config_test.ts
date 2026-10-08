import {
  assertEquals,
  assertFalse,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  loadNseConfig,
  loadNseUatWorkflowConfig,
  NseConfigError,
} from "./nse_config.ts";
import { type MoneyBowlEnvironment, NSE_ORIGINS } from "./nse_runtime.ts";
import type { NseCredentialProvider } from "./nse_credentials.ts";

function fixture(
  environment: MoneyBowlEnvironment = "DEV",
): Record<string, string | undefined> {
  return {
    MONEYBOWL_ENV: environment,
    MONEYBOWL_SUPABASE_URL:
      `https://${environment.toLowerCase()}-synthetic.supabase.co`,
    SUPABASE_URL: `https://${environment.toLowerCase()}-synthetic.supabase.co`,
    NSE_CREDENTIAL_PROVIDER: "edge-secrets",
    NSE_URL: NSE_ORIGINS[environment],
    NSE_ALLOWED_READ_APIS: '["MASTER_DOWNLOAD","ORDER_STATUS"]',
    NSE_LOGIN_USER_ID: "synthetic-login",
    NSE_API_KEY_MEMBER: "synthetic-member-key",
    NSE_API_SECRET_USER: "synthetic-secret",
    NSE_MEMBER_CODE: "synthetic-member",
  };
}
const reader = (values: Record<string, string | undefined>) => (name: string) =>
  values[name];

for (const env of ["DEV", "QA", "PROD"] as const) {
  Deno.test(`${env}: resolves only its own synthetic project and NSE target`, async () => {
    const config = await loadNseConfig(reader(fixture(env)));
    assertEquals(config.environment, env);
    assertEquals(config.baseUrl, NSE_ORIGINS[env]);
    assertEquals(config.loginUserId, "synthetic-login");
    assertEquals(config.apiSecretUser, "synthetic-secret");
    assertEquals(Object.isFrozen(config), true);
    assertEquals(Object.isFrozen(config.allowedReadApis), true);
    assertEquals(
      config.userAgent,
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:108.0) Gecko/20100101 Firefox/108.0",
    );
    const serialized = JSON.stringify(config) + Deno.inspect(config);
    for (
      const secret of [
        "synthetic-login",
        "synthetic-member-key",
        "synthetic-secret",
        "synthetic-member",
      ]
    ) {
      assertFalse(serialized.includes(secret));
    }
  });
  for (const target of Object.values(NSE_ORIGINS)) {
    if (target === NSE_ORIGINS[env]) continue;
    Deno.test(`${env}: rejects cross-environment origin ${target}`, async () => {
      await assertRejects(
        () => loadNseConfig(reader({ ...fixture(env), NSE_URL: target })),
        NseConfigError,
      );
    });
  }
}

for (const variable of Object.keys(fixture())) {
  if (variable === "NSE_ALLOWED_READ_APIS") continue; // optional only in DEV
  for (const value of [undefined, "", " \t "]) {
    Deno.test(`configuration rejects missing/empty ${variable}: ${String(value)}`, async () => {
      const error = await assertRejects(
        () => loadNseConfig(reader({ ...fixture(), [variable]: value })),
        NseConfigError,
      );
      const diagnostic = error.message + error.stack + JSON.stringify(error);
      assertFalse(diagnostic.includes("synthetic-secret"));
      assertFalse(diagnostic.includes("synthetic-member-key"));
    });
  }
}

for (
  const value of [
    "dev",
    "STAGING",
    "production",
    "__proto__",
    "constructor",
    "QA\nPROD",
  ]
) {
  Deno.test(`rejects noncanonical environment ${JSON.stringify(value)}`, async () => {
    await assertRejects(
      () => loadNseConfig(reader({ ...fixture(), MONEYBOWL_ENV: value })),
      NseConfigError,
    );
  });
}
for (
  const value of [
    "http://nseinvestuat.nseindia.com",
    "not-a-url",
    "https://synthetic-secret@nseinvestuat.nseindia.com",
    "https://user:synthetic-secret@nseinvestuat.nseindia.com",
    "https://nseinvestuat.nseindia.com:443",
    "https://nseinvestuat.nseindia.com:8443",
    "https://nseinvestuat.nseindia.com/other",
    "https://nseinvestuat.nseindia.com/../",
    "https://nseinvestuat.nseindia.com?",
    "https://nseinvestuat.nseindia.com?q=synthetic-secret",
    "https://nseinvestuat.nseindia.com#",
    "https://nseinvestuat.nseindia.com#synthetic-secret",
    "https://nseinvestuat.nseindia.com.evil.test",
    "https://nseinvestuat.nseindia.com.",
    "https://nseinvestuat.nseindia.com\\other",
    "https://nseinvestuat.nseindia.com\n/",
  ]
) {
  Deno.test(`strict origin validation rejects ${JSON.stringify(value)}`, async () => {
    const error = await assertRejects(
      () => loadNseConfig(reader({ ...fixture(), NSE_URL: value })),
      NseConfigError,
    );
    assertFalse(
      (error.message + error.stack + JSON.stringify(error)).includes(
        "synthetic-secret",
      ),
    );
  });
}

Deno.test("DEV compatibility preserves trailing slash and configured user agent", async () => {
  const config = await loadNseUatWorkflowConfig(
    reader({
      ...fixture(),
      NSE_URL: NSE_ORIGINS.DEV + "/",
      NSE_USER_AGENT: "MoneyBowl-NSE-UAT/1.0",
      NSE_ALLOWED_READ_APIS: undefined,
    }),
  );
  assertEquals(config.baseUrl, NSE_ORIGINS.DEV);
  assertEquals(config.userAgent, "MoneyBowl-NSE-UAT/1.0");
});
Deno.test("worker gate prevents QA/PROD calls using UAT-only database evidence", async () => {
  for (const env of ["QA", "PROD"] as const) {
    await assertRejects(
      () => loadNseUatWorkflowConfig(reader(fixture(env))),
      NseConfigError,
    );
  }
});
Deno.test("project mismatch and malformed project URL fail closed", async () => {
  for (
    const url of [
      "https://another-synthetic.supabase.co",
      "http://qa-synthetic.supabase.co",
      "https://qa-synthetic.supabase.co:443",
      "https://qa-synthetic.supabase.co/path",
    ]
  ) {
    await assertRejects(
      () => loadNseConfig(reader({ ...fixture("QA"), SUPABASE_URL: url })),
      NseConfigError,
    );
  }
});
Deno.test("QA/PROD require explicit read permissions, reject write identifiers and wildcard", async () => {
  for (const env of ["QA", "PROD"] as const) {
    for (
      const value of [
        undefined,
        "",
        "*",
        '["*"]',
        '["EKYCREG"]',
        '["CLIENTCOMMON183"]',
        '["constructor"]',
        '["ORDER_STATUS","ORDER_STATUS"]',
        "{}",
        "null",
      ]
    ) {
      await assertRejects(
        () =>
          loadNseConfig(
            reader({ ...fixture(env), NSE_ALLOWED_READ_APIS: value }),
          ),
        NseConfigError,
      );
    }
    const config = await loadNseConfig(
      reader({ ...fixture(env), NSE_ALLOWED_READ_APIS: "[]" }),
    );
    assertEquals(config.allowedReadApis, []);
  }
});
Deno.test("unknown/Vault provider never falls back to existing Edge secrets", async () => {
  for (const kind of ["vault", "unknown", "EDGE-SECRETS"]) {
    await assertRejects(
      () =>
        loadNseConfig(reader({ ...fixture(), NSE_CREDENTIAL_PROVIDER: kind })),
      NseConfigError,
    );
  }
});
Deno.test("provider abstraction binds environment, sanitizes failures, rejects absent credentials", async () => {
  for (
    const resolve of [
      async () => {
        throw new Error("synthetic-secret");
      },
      async () => ({
        loginUserId: "",
        apiKeyMember: "",
        apiSecretUser: "",
        memberCode: "",
      }),
    ]
  ) {
    const provider: NseCredentialProvider = { kind: "edge-secrets", resolve };
    const error = await assertRejects(
      () => loadNseConfig(reader(fixture()), provider),
      NseConfigError,
    );
    assertFalse(
      (error.message + error.stack + JSON.stringify(error)).includes(
        "synthetic-secret",
      ),
    );
  }
  let selected: string | undefined;
  await loadNseConfig(reader(fixture("QA")), {
    kind: "edge-secrets",
    resolve: async (environment) => {
      selected = environment;
      return {
        loginUserId: "dummy",
        apiKeyMember: "dummy",
        apiSecretUser: "dummy",
        memberCode: "dummy",
      };
    },
  });
  assertEquals(selected, "QA");
});
Deno.test("invalid User-Agent cannot become an exception containing configuration", async () => {
  await assertRejects(
    () =>
      loadNseConfig(
        reader({ ...fixture(), NSE_USER_AGENT: "synthetic-secret\r\nheader" }),
      ),
    NseConfigError,
  );
});

Deno.test("resolved credentials preserve the existing NSE authentication vector", async () => {
  const { createNseEncryptedPassword } = await import("./nse_auth.ts");
  const config = await loadNseConfig(
    reader({
      ...fixture(),
      NSE_API_KEY_MEMBER: "test-api-key-member",
      NSE_API_SECRET_USER: "test-api-secret-user",
    }),
  );
  assertEquals(
    await createNseEncryptedPassword(
      config.apiKeyMember,
      config.apiSecretUser,
      {
        randomNumber: 1_234_567_890,
        ivHex: "000102030405060708090a0b0c0d0e0f",
        saltHex: "101112131415161718191a1b1c1d1e1f",
      },
    ),
    "MDAwMTAyMDMwNDA1MDYwNzA4MDkwYTBiMGMwZDBlMGY6OjEwMTExMjEzMTQxNTE2MTcxODE5MWExYjFjMWQxZTFmOjpONUcycHFLNkxDQ0RUV1pMbE4rMFp4ZHdPNjdIdlpoWE5vc3NFaDlEZ1VZPQ==",
  );
});
Deno.test("configuration resolution and provider failures never log credentials", async () => {
  const entries: unknown[][] = [];
  const original = {
    log: console.log,
    error: console.error,
    warn: console.warn,
  };
  try {
    console.log = console.error = console.warn = (...args: unknown[]) => {
      entries.push(args);
    };
    await loadNseConfig(reader(fixture()));
    await assertRejects(
      () =>
        loadNseConfig(reader(fixture()), {
          kind: "edge-secrets",
          resolve: async () => {
            throw new Error("synthetic-secret");
          },
        }),
      NseConfigError,
    );
    assertEquals(entries, []);
  } finally {
    Object.assign(console, original);
  }
});

Deno.test("credential control characters and provider diagnostic fields are sanitized", async () => {
  for (
    const name of [
      "NSE_LOGIN_USER_ID",
      "NSE_API_KEY_MEMBER",
      "NSE_API_SECRET_USER",
      "NSE_MEMBER_CODE",
    ]
  ) {
    const error = await assertRejects(
      () =>
        loadNseConfig(
          reader({ ...fixture(), [name]: "synthetic-secret\r\nvalue" }),
        ),
      NseConfigError,
    );
    assertFalse(
      (error.message + JSON.stringify(error)).includes("synthetic-secret"),
    );
  }
  const error = await assertRejects(() =>
    loadNseConfig(reader(fixture()), {
      kind: "edge-secrets",
      resolve: async () => {
        throw new NseConfigError(["synthetic-secret"]);
      },
    }), NseConfigError);
  assertEquals(error.missingVariables, []);
});
