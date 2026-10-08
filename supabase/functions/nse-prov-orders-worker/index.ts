import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { loadNseUatWorkflowConfig } from "../_shared/nse/nse_config.ts";
import {
  createProvOrdersGateway,
  createProvOrdersPersistence,
} from "./adapters.ts";
import { createNseProvOrdersHandler } from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);
const handler = createNseProvOrdersHandler({
  internalToken: Deno.env.get("NSE_WORKER_TOKEN") ?? "",
  persistence: createProvOrdersPersistence(supabase),
  gateway: createProvOrdersGateway(await loadNseUatWorkflowConfig()),
});
Deno.serve(handler);
