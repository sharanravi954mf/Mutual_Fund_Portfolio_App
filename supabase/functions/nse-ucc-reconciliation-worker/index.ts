import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { loadNseConfig } from "../_shared/nse/nse_config.ts";
import {
  createVerificationGateway,
  createVerificationPersistence,
} from "./adapters.ts";
import { createNseUccReconciliationHandler } from "./handler.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);
const handler = createNseUccReconciliationHandler({
  internalToken: Deno.env.get("NSE_UCC_RECONCILIATION_WORKER_TOKEN") ?? "",
  persistence: createVerificationPersistence(supabase),
  gateway: createVerificationGateway(loadNseConfig()),
});
Deno.serve(handler);
