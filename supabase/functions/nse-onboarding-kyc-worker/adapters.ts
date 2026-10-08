import { assertNseUatWorkflow } from "../_shared/nse/nse_runtime.ts";
import { NseClient } from "../_shared/nse/nse_client.ts";
import type { NseConfig } from "../_shared/nse/nse_types.ts";
import type { Claim, Result } from "./handler.ts";
export function createOnboardingTransport(
  config: NseConfig,
  fetcher: typeof fetch = fetch,
) {
  // This slice cannot be pointed at Production, even by a mistaken runtime setting.
  assertNseUatWorkflow(config);
  const base = new URL(config.baseUrl);
  if (
    base.protocol !== "https:" ||
    base.hostname !== "nseinvestuat.nseindia.com" || base.port ||
    base.username || base.password || base.search || base.hash ||
    base.pathname !== "/"
  ) throw new Error("onboarding_uat_configuration_required");
  let invoked = false;
  const client = new NseClient(config, (input, init) => {
    invoked = true;
    return fetcher(input, { ...init, redirect: "error" });
  });
  return async (claim: Claim): Promise<Result> => {
    // Each handler processes one operation. No client-supplied endpoint or fields.
    invoked = false;
    const path = claim.api === "CLIENT_KYC_REPORT"
      ? "/nsemfdesk/api/v2/reports/CLIENT_KYC_REPORT"
      : claim.api === "EKYCREG"
      ? "/nsemfdesk/api/v1/EKYC/EKYCREG"
      : null;
    if (!path) {
      return {
        bytes: new Uint8Array(),
        status: null,
        transmission: "PROVEN_NOT_SENT",
      };
    }
    try {
      const response = await client.request({
        method: "POST",
        path,
        bodyText: claim.request,
        contentType: "application/json",
        accept: "application/json",
        timeoutMs: 30000,
        maxResponseBytes: 1024 * 1024,
        acceptHttpErrors: true,
      });
      return {
        bytes: response.body,
        status: response.status,
        transmission: "SENT_WITH_RESULT",
      };
    } catch {
      return {
        bytes: new Uint8Array(),
        status: null,
        transmission: invoked ? "MAYBE_SENT" : "PROVEN_NOT_SENT",
      };
    }
  };
}
export function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 32768) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 32768));
  }
  return btoa(binary);
}
