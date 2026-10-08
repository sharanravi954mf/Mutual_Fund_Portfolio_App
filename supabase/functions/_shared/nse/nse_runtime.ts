/** Backend runtime policy. Branch names and Flutter defines are not authority. */
export type MoneyBowlEnvironment = "DEV" | "QA" | "PROD";
export type NseEnvironmentReader = (name: string) => string | undefined;

// NSE NNF handbook v1.9.7, p6 (June 2026). Security policy, not deployment data.
export const NSE_ORIGINS = Object.freeze({
  DEV: "https://nseinvestuat.nseindia.com",
  QA: "https://www.nseinvest.com",
  PROD: "https://www.nseinvest.com",
});

// Deliberately finite initial certification surface. POST does not imply a write.
export const NSE_CERTIFICATION_READS = Object.freeze({
  MASTER_DOWNLOAD: "/nsemfdesk/api/v2/reports/MASTER_DOWNLOAD",
  ORDER_STATUS: "/nsemfdesk/api/v2/reports/ORDER_STATUS",
  CLIENT_KYC_REPORT: "/nsemfdesk/api/v2/reports/CLIENT_KYC_REPORT",
  CLIENT_MASTER_REPORT: "/nsemfdesk/api/v2/reports/client_master_report",
});
export type NseReadApi = keyof typeof NSE_CERTIFICATION_READS;
export type NseRuntimePolicy = Readonly<{
  environment: MoneyBowlEnvironment;
  allowedReadApis: readonly NseReadApi[];
}>;

export class NseConfigError extends Error {
  readonly code = "nse_configuration_invalid";
  readonly missingVariables: readonly string[];
  constructor(missingVariables: readonly string[] = []) {
    super("NSE runtime configuration unavailable");
    this.name = "NseConfigError";
    this.missingVariables = Object.freeze([...missingVariables]);
  }
}

export function requiredSetting(
  read: NseEnvironmentReader,
  name: string,
): string {
  const value = read(name)?.trim();
  if (!value) throw new NseConfigError([name]);
  return value;
}

/** Reject parser-normalized tricks too: explicit :443, empty ?/#, dot paths, etc. */
export function httpsOrigin(value: string): string {
  if (!/^https:\/\/[a-z0-9]+(?:[.-][a-z0-9]+)*\/?$/.test(value)) {
    throw new NseConfigError();
  }
  try {
    const url = new URL(value);
    if (url.origin !== value.replace(/\/$/, "")) throw new NseConfigError();
    return url.origin;
  } catch {
    throw new NseConfigError();
  }
}

export function assertNseOrigin(
  environment: MoneyBowlEnvironment,
  baseUrl: string,
): void {
  if (
    !Object.hasOwn(NSE_ORIGINS, environment) ||
    httpsOrigin(baseUrl) !== NSE_ORIGINS[environment]
  ) throw new NseConfigError();
}

export function resolveNseRuntime(
  read: NseEnvironmentReader,
): NseRuntimePolicy {
  const environment = requiredSetting(read, "MONEYBOWL_ENV");
  if (environment !== "DEV" && environment !== "QA" && environment !== "PROD") {
    throw new NseConfigError();
  }
  // Independently provisioned expected project URL must match the injected runtime.
  const expected = httpsOrigin(requiredSetting(read, "MONEYBOWL_SUPABASE_URL"));
  if (expected !== httpsOrigin(requiredSetting(read, "SUPABASE_URL"))) {
    throw new NseConfigError();
  }
  const raw = read("NSE_ALLOWED_READ_APIS");
  let apis: unknown = [];
  if (raw !== undefined) {
    try {
      apis = JSON.parse(raw);
    } catch {
      throw new NseConfigError();
    }
  } else if (environment !== "DEV") {
    throw new NseConfigError(["NSE_ALLOWED_READ_APIS"]);
  }
  if (
    !Array.isArray(apis) ||
    apis.some((api) =>
      typeof api !== "string" || !Object.hasOwn(NSE_CERTIFICATION_READS, api)
    ) || new Set(apis).size !== apis.length
  ) throw new NseConfigError();
  return Object.freeze({
    environment,
    allowedReadApis: Object.freeze(apis as NseReadApi[]),
  });
}

/** Persisted workflow schemas currently bind all evidence and operations to UAT. */
export function assertNseUatWorkflow(policy: NseRuntimePolicy): void {
  if (policy.environment !== "DEV") throw new NseConfigError();
}

export function permitsNseRequest(
  policy: NseRuntimePolicy,
  method: string,
  path: string,
): boolean {
  // No absolute URLs, URL normalization, query strings, fragments or redirects.
  if (!/^\/[A-Za-z0-9_/-]+$/.test(path) || path.includes("//")) return false;
  if (policy.environment === "DEV") return true;
  if (policy.environment !== "QA" && policy.environment !== "PROD") {
    return false;
  }
  return method === "POST" &&
    policy.allowedReadApis.some((api) =>
      Object.hasOwn(NSE_CERTIFICATION_READS, api) &&
      NSE_CERTIFICATION_READS[api] === path
    );
}
