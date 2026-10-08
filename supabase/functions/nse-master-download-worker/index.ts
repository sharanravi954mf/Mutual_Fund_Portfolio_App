import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { loadNseUatWorkflowConfig } from "../_shared/nse/nse_config.ts";
import { createMasterPersistence } from "./adapters.ts";
import { createNseMasterDownloadHandler } from "./handler.ts";

const client = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);
Deno.serve(createNseMasterDownloadHandler({
  internalToken: Deno.env.get("NSE_WORKER_TOKEN") ?? "",
  config: await loadNseUatWorkflowConfig(),
  persistence: createMasterPersistence(client),
}));
