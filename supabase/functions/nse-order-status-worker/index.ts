import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { loadNseUatWorkflowConfig } from "../_shared/nse/nse_config.ts";
import {
  createOrderStatusGateway,
  createOrderStatusPersistence,
} from "./adapters.ts";
import { createNseOrderStatusHandler } from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);
const handler = createNseOrderStatusHandler({
  internalToken: Deno.env.get("NSE_WORKER_TOKEN") ??
    Deno.env.get("NSE_ORDER_STATUS_WORKER_TOKEN") ?? "",
  persistence: createOrderStatusPersistence(supabase),
  gateway: createOrderStatusGateway(await loadNseUatWorkflowConfig()),
});
Deno.serve(handler);
