import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { loadNseUatWorkflowConfig } from "../_shared/nse/nse_config.ts";
import {
  createSipXsipReportsGateway,
  createSipXsipReportsPersistence,
} from "./adapters.ts";
import { createNseSipXsipReportsHandler } from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);
const handler = createNseSipXsipReportsHandler({
  internalToken: Deno.env.get("NSE_WORKER_TOKEN") ?? "",
  persistence: createSipXsipReportsPersistence(supabase),
  gateway: createSipXsipReportsGateway(await loadNseUatWorkflowConfig()),
});
Deno.serve(handler);
