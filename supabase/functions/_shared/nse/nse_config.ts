import type { NseConfig } from "./nse_types.ts";
import {
  edgeSecretsProvider,
  type NseCredentialProvider,
  resolveNseCredentials,
} from "./nse_credentials.ts";
import {
  assertNseOrigin,
  assertNseUatWorkflow,
  httpsOrigin,
  NseConfigError,
  type NseEnvironmentReader,
  requiredSetting,
  resolveNseRuntime,
} from "./nse_runtime.ts";
export { NseConfigError, type NseEnvironmentReader } from "./nse_runtime.ts";

const defaultNseUserAgent =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:108.0) Gecko/20100101 Firefox/108.0";

export async function loadNseConfig(
  read: NseEnvironmentReader = (name) => Deno.env.get(name),
  provider: NseCredentialProvider = edgeSecretsProvider(read),
): Promise<NseConfig> {
  const runtime = resolveNseRuntime(read);
  const baseUrl = httpsOrigin(requiredSetting(read, "NSE_URL"));
  assertNseOrigin(runtime.environment, baseUrl);
  // Exactly one active source. No absent/unknown-provider fallback, including Vault.
  if (
    requiredSetting(read, "NSE_CREDENTIAL_PROVIDER") !== "edge-secrets" ||
    provider.kind !== "edge-secrets"
  ) throw new NseConfigError();
  const userAgent = read("NSE_USER_AGENT")?.trim() || defaultNseUserAgent;
  if (!/^[\x20-\x7e]{1,256}$/.test(userAgent)) throw new NseConfigError();
  const credentials = await resolveNseCredentials(
    provider,
    runtime.environment,
  );
  const config = { ...runtime, baseUrl, userAgent } as NseConfig;
  // Auth still receives the original fields; ordinary JSON/console enumeration is safe.
  for (const [name, value] of Object.entries(credentials)) {
    Object.defineProperty(config, name, { value, enumerable: false });
  }
  return Object.freeze(config);
}

/** Prevent Production calls being recorded by the existing UAT-only DB contracts. */
export async function loadNseUatWorkflowConfig(
  read: NseEnvironmentReader = (name) => Deno.env.get(name),
): Promise<NseConfig> {
  const config = await loadNseConfig(read);
  assertNseUatWorkflow(config);
  return config;
}
