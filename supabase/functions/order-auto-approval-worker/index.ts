import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import { createSupabasePersistence } from "./adapters.ts";
import { createOrderAutoApprovalWorkerHandler } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const internalToken = Deno.env.get("ORDER_AUTO_APPROVAL_WORKER_TOKEN") ?? "";

const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

serve(createOrderAutoApprovalWorkerHandler({
  internalToken,
  persistence: createSupabasePersistence(serviceClient),
  log: (entry) => console.log(JSON.stringify(entry)),
}));
