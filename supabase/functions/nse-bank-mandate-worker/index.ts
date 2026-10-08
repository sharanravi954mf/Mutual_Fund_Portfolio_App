import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { loadNseUatWorkflowConfig } from "../_shared/nse/nse_config.ts";
import { createHandler } from "./handler.ts";
import { gateway, persistence } from "./adapters.ts";
const client = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);
Deno.serve(
  createHandler({
    token: Deno.env.get("NSE_WORKER_TOKEN") ?? "",
    persistence: persistence(client),
    submit: gateway(await loadNseUatWorkflowConfig()),
  }),
);
