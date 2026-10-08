import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { loadNseUatWorkflowConfig } from "../_shared/nse/nse_config.ts";
import {
  createStpSwpReportsGateway,
  createStpSwpReportsPersistence,
} from "./adapters.ts";
import { createNseStpSwpReportsHandler } from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);
const handler = createNseStpSwpReportsHandler({
  internalToken: Deno.env.get("NSE_WORKER_TOKEN") ?? "",
  persistence: createStpSwpReportsPersistence(supabase),
  gateway: createStpSwpReportsGateway(await loadNseUatWorkflowConfig()),
});
Deno.serve(handler);
