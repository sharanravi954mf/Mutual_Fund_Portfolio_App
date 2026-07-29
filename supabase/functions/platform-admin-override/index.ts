import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import { createPlatformAdminOverrideHandler } from "./handler.ts";

function supabaseClient(key: string, authorization?: string) {
  return createClient(
    Deno.env.get("SUPABASE_URL") || "",
    key,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
      global: authorization == null
        ? undefined
        : { headers: { authorization } },
    },
  );
}

const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
const authenticateClient = supabaseClient(serviceRoleKey);
const serviceClient = supabaseClient(serviceRoleKey);

serve(createPlatformAdminOverrideHandler({
  authenticateClient,
  serviceClient,
  userClientForToken: (token: string) =>
    supabaseClient(anonKey, `Bearer ${token}`),
}));
