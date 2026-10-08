import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { loadNseConfig } from "../_shared/nse/nse_config.ts";
import { createConfiguredNseSmokeTestHandler } from "./handler.ts";

serve(createConfiguredNseSmokeTestHandler(
  await loadNseConfig(),
  Deno.env.get("NSE_SMOKE_TEST_TOKEN") ?? "",
));
