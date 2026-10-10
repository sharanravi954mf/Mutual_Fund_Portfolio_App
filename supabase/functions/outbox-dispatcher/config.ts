import {
  assertNseOrigin,
  httpsOrigin,
  type NseEnvironmentReader,
  resolveNseRuntime,
} from "../_shared/nse/nse_runtime.ts";

export type Mode = "disabled" | "observe" | "active";
export type Config = ReturnType<typeof resolveConfig>;
export function resolveConfig(read: NseEnvironmentReader) {
  try {
    const runtime = resolveNseRuntime(read);
    assertNseOrigin(runtime.environment, read("NSE_URL") ?? "");
    const origin = httpsOrigin(read("SUPABASE_URL") ?? "");
    // Hosted Supabase project destinations only. No custom URLs or proxy endpoints.
    if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(origin)) throw Error();
    const mode = read("OUTBOX_DISPATCH_MODE") ?? "disabled";
    if (!["disabled", "observe", "active"].includes(mode)) throw Error();
    // Persisted NSE workflows are UAT-bound. Configuration cannot bypass M1.
    if (mode === "active" && runtime.environment !== "DEV") throw Error();
    const secret = (name: string) => {
      const value = read(name) ?? "";
      if (!/^[\x21-\x7e]{32,4096}$/.test(value)) throw Error();
      return value;
    };
    const keys = {
      signingKey: secret("OUTBOX_NOTIFICATION_KEY"),
      databaseKey: secret("SUPABASE_SERVICE_ROLE_KEY"),
      workerToken: secret("NSE_WORKER_TOKEN"),
    };
    if (new Set(Object.values(keys)).size !== 3) throw Error();
    // Optional during rollout; never reuse dispatch, database or worker authority.
    const readinessKey = read("OUTBOX_READINESS_KEY") === undefined
      ? undefined
      : secret("OUTBOX_READINESS_KEY");
    if (
      readinessKey !== undefined && Object.values(keys).includes(readinessKey)
    ) {
      throw Error();
    }
    // Avoid incidental credential disclosure through JSON/log inspection.
    return Object.freeze(Object.defineProperties(
      {
        environment: runtime.environment,
        origin,
        mode: mode as Mode,
      },
      Object.fromEntries(
        Object.entries({ ...keys, readinessKey }).map((
          [key, value],
        ) => [key, { value, enumerable: false }]),
      ),
    ) as {
      readonly environment: typeof runtime.environment;
      readonly origin: string;
      readonly mode: Mode;
      readonly signingKey: string;
      readonly databaseKey: string;
      readonly workerToken: string;
      readonly readinessKey: string | undefined;
    });
  } catch {
    throw new Error("outbox_configuration_invalid");
  }
}
