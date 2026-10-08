import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { loadNseUatWorkflowConfig } from "../_shared/nse/nse_config.ts";
import { base64, createOnboardingTransport } from "./adapters.ts";
import { type Claim, createOnboardingKycHandler } from "./handler.ts";
const nseConfig = await loadNseUatWorkflowConfig();
const client = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);
async function rpc(name: string, params: Record<string, unknown>) {
  const { data, error } = await client.rpc(name, params);
  if (error) throw new Error("onboarding_persistence_unavailable");
  return data;
}
const ids = (c: Claim) => ({
  p_operation_id: c.operation_id,
  p_claim_token: c.claim_token,
  p_call_id: c.call_id,
});
Deno.serve(createOnboardingKycHandler({
  token: Deno.env.get("NSE_WORKER_TOKEN") ?? "",
  claim: (id) => rpc("claim_onboarding_kyc", { p_event_id: id }),
  start: (c) => rpc("start_onboarding_kyc_call", ids(c)),
  finish: (c, result) =>
    rpc("finish_onboarding_kyc_call", {
      ...ids(c),
      p_response_base64: base64(result.bytes),
      p_http_status: result.status,
      p_transmission: result.transmission,
    }),
  // A new transport per operation keeps the send fence independent across concurrent requests.
  submit: (c) => createOnboardingTransport(nseConfig)(c),
}));
