import type { NseConfig } from "./nse_types.ts";

export type NseEnvironmentReader = (name: string) => string | undefined;

const requiredVariables = [
  "NSE_URL",
  "NSE_LOGIN_USER_ID",
  "NSE_API_KEY_MEMBER",
  "NSE_API_SECRET_USER",
  "NSE_MEMBER_CODE",
] as const;

const defaultNseUserAgent =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:108.0) Gecko/20100101 Firefox/108.0";

export class NseConfigError extends Error {
  readonly code = "nse_configuration_invalid";
  readonly missingVariables: readonly string[];

  constructor(missingVariables: readonly string[] = []) {
    super(
      missingVariables.length > 0
        ? `Missing required NSE configuration: ${missingVariables.join(", ")}`
        : "NSE_URL must be a valid HTTPS base URL",
    );
    this.name = "NseConfigError";
    this.missingVariables = [...missingVariables];
  }
}

function requiredValue(
  values: ReadonlyMap<string, string>,
  name: typeof requiredVariables[number],
): string {
  return values.get(name) as string;
}

export function loadNseConfig(
  readEnvironment: NseEnvironmentReader = (name) => Deno.env.get(name),
): NseConfig {
  const values = new Map<string, string>();
  const missingVariables: string[] = [];

  for (const name of requiredVariables) {
    const value = readEnvironment(name)?.trim();
    if (value == null || value.length === 0) {
      missingVariables.push(name);
    } else {
      values.set(name, value);
    }
  }

  if (missingVariables.length > 0) {
    throw new NseConfigError(missingVariables);
  }

  const rawBaseUrl = requiredValue(values, "NSE_URL");
  let url: URL;
  try {
    url = new URL(rawBaseUrl);
  } catch (_error) {
    throw new NseConfigError();
  }

  if (
    url.protocol !== "https:" || url.username !== "" || url.password !== "" ||
    url.search !== "" || url.hash !== ""
  ) {
    throw new NseConfigError();
  }

  return Object.freeze({
    baseUrl: url.toString().replace(/\/+$/, ""),
    loginUserId: requiredValue(values, "NSE_LOGIN_USER_ID"),
    apiKeyMember: requiredValue(values, "NSE_API_KEY_MEMBER"),
    apiSecretUser: requiredValue(values, "NSE_API_SECRET_USER"),
    memberCode: requiredValue(values, "NSE_MEMBER_CODE"),
    userAgent: readEnvironment("NSE_USER_AGENT")?.trim() || defaultNseUserAgent,
  });
}
