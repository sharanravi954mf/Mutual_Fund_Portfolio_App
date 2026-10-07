import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requirePlatformMutation } from "../_shared/authorization.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const authorization = await requirePlatformMutation(
    req,
    "platform.catalog.manage",
  );
  if ("failure" in authorization) {
    return new Response(
      JSON.stringify({ error: authorization.failure.message }),
      {
        status: authorization.failure.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // The legacy third-party NAV source is intentionally decommissioned.
  // NSE NAV exists under MASTER_DOWNLOAD, but publication remains blocked
  // until its source/crosswalk authority is separately commissioned.
  return new Response(
    JSON.stringify({
      success: false,
      code: "official_nav_source_not_commissioned",
      message:
        "Daily NAV refresh is unavailable until the official NSE NAV source is commissioned.",
    }),
    {
      status: 409,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
});
