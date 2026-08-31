import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { NseClient } from "../_shared/nse/nse_client.ts";
import { loadNseConfig } from "../_shared/nse/nse_config.ts";
import { createNseUatSmokeTestHandler } from "./handler.ts";

const smokeTestToken = Deno.env.get("NSE_SMOKE_TEST_TOKEN") ?? "";

serve(createNseUatSmokeTestHandler({
  smokeTestToken,
  execute: async () => {
    const client = new NseClient(loadNseConfig());
    return await client.request({
      method: "POST",
      path: "/nsemfdesk/api/v2/reports/MASTER_DOWNLOAD",
      jsonBody: { file_type: "NAV" },
    });
  },
}));
