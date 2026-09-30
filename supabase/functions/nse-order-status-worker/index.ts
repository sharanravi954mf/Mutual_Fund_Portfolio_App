import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import { NseClient } from "../_shared/nse/nse_client.ts";
import { loadNseConfig } from "../_shared/nse/nse_config.ts";
import {
  createNseOrderStatusGateway,
  createOrderStatusPersistence,
} from "./adapters.ts";
import { createNseOrderStatusWorkerHandler } from "./handler.ts";
const client = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { autoRefreshToken: false, persistSession: false } },
);
serve(createNseOrderStatusWorkerHandler({
  internalToken: Deno.env.get("NSE_ORDER_STATUS_WORKER_TOKEN") ?? "",
  maxAttempts: 3,
  leaseSeconds: 120,
  persistence: createOrderStatusPersistence(client),
  gateway: createNseOrderStatusGateway(new NseClient(loadNseConfig())),
}));
