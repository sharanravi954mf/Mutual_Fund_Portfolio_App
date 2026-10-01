import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { loadNseConfig } from "../_shared/nse/nse_config.ts";
import {
  createClientReadinessGateway,
  createClientReadinessPersistence,
} from "./adapters.ts";
import { createNseClientReadinessHandler } from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);
const handler = createNseClientReadinessHandler({
  internalToken: Deno.env.get("NSE_WORKER_TOKEN") ?? "",
  persistence: createClientReadinessPersistence(supabase),
  gateway: createClientReadinessGateway(loadNseConfig()),
});
Deno.serve(handler);
