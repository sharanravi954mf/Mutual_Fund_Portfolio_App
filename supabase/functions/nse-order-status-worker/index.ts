import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { loadNseConfig } from "../_shared/nse/nse_config.ts";
import {
  createOrderStatusGateway,
  createOrderStatusPersistence,
} from "./adapters.ts";
import { createNseOrderStatusHandler } from "./handler.ts";

const client = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);
Deno.serve(createNseOrderStatusHandler({
  internalToken: Deno.env.get("NSE_ORDER_STATUS_WORKER_TOKEN") ?? "",
  persistence: createOrderStatusPersistence(client),
  gateway: createOrderStatusGateway(loadNseConfig()),
}));
