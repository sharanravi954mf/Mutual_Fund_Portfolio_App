import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { loadNseConfig } from "../_shared/nse/nse_config.ts";
import {
  createSettlementRedemptionGateway,
  createSettlementRedemptionPersistence,
} from "./adapters.ts";
import { createNseSettlementRedemptionHandler } from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);
const handler = createNseSettlementRedemptionHandler({
  internalToken: Deno.env.get("NSE_WORKER_TOKEN") ?? "",
  persistence: createSettlementRedemptionPersistence(supabase),
  gateway: createSettlementRedemptionGateway(loadNseConfig()),
});
Deno.serve(handler);
