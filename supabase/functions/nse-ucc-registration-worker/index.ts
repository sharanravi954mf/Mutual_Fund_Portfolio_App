import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import { NseClient } from "../_shared/nse/nse_client.ts";
import { loadNseConfig } from "../_shared/nse/nse_config.ts";
import { createNseUccGateway, createUccPersistence } from "./adapters.ts";
import { createNseUccWorkerHandler } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const internalToken = Deno.env.get("NSE_UCC_WORKER_TOKEN") ?? "";

const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const nseClient = new NseClient(loadNseConfig());

serve(createNseUccWorkerHandler({
  internalToken,
  maxAttempts: 2,
  leaseSeconds: 120,
  persistence: createUccPersistence(serviceClient),
  gateway: createNseUccGateway(nseClient),
  log: (entry) => console.log(JSON.stringify(entry)),
}));
