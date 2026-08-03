import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import { createSupabasePersistence } from "./adapters.ts";
import { createOrderAutoApprovalWorkerHandler } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const internalToken = Deno.env.get("ORDER_AUTO_APPROVAL_WORKER_TOKEN") ?? "";

function boundedIntEnv(
  name: string,
  fallback: number,
  min: number,
  max: number,
): number {
  const raw = Deno.env.get(name);
  if (raw == null || raw.trim() === "") return fallback;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${name.toLowerCase()}_invalid`);
  }
  return parsed;
}

const maxAttempts = boundedIntEnv("ORDER_AUTO_APPROVAL_MAX_ATTEMPTS", 3, 1, 10);
const leaseSeconds = boundedIntEnv(
  "ORDER_AUTO_APPROVAL_LEASE_SECONDS",
  120,
  15,
  3600,
);

const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

serve(createOrderAutoApprovalWorkerHandler({
  internalToken,
  maxAttempts,
  leaseSeconds,
  persistence: createSupabasePersistence(serviceClient),
  log: (entry) => console.log(JSON.stringify(entry)),
}));
