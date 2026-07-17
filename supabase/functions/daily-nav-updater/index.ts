import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight request
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") || "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
  );

  try {
    // 1. Fetch active mutual funds from our database
    const { data: dbFunds, error: dbError } = await supabase
      .from("mutual_funds")
      .select("id, scheme_code, scheme_name");

    if (dbError) {
      throw new Error(`Failed to query mutual_funds: ${dbError.message}`);
    }

    if (!dbFunds || dbFunds.length === 0) {
      return new Response(JSON.stringify({ 
        success: true, 
        message: "No mutual funds registered in database. Daily NAV update skipped." 
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let updatedCount = 0;

    // 2. Fetch daily NAV from api.mfapi.in for each active scheme code
    for (const fund of dbFunds) {
      const schemeCode = fund.scheme_code.trim();
      const apiUrl = `https://api.mfapi.in/mf/${schemeCode}`;
      
      try {
        const response = await fetch(apiUrl);
        if (!response.ok) {
          console.warn(`Failed to fetch NAV for ${schemeCode} from mfapi.in: ${response.statusText}`);
          continue;
        }

        const json = await response.json();
        if (json && json.data && json.data.length > 0) {
          const latest = json.data[0];
          const latestNav = parseFloat(latest.nav);
          const rawDate = latest.date; // Format: "dd-MM-yyyy"

          if (!isNaN(latestNav)) {
            // Convert "dd-MM-yyyy" to "yyyy-MM-dd"
            let formattedDate = "";
            const dateParts = rawDate.split("-");
            if (dateParts.length === 3) {
              formattedDate = `${dateParts[2]}-${dateParts[1]}-${dateParts[0]}`;
            } else {
              formattedDate = new Date().toISOString().split("T")[0];
            }

            // Update fund NAV and date
            const { error: updateError } = await supabase
              .from("mutual_funds")
              .update({
                current_nav: latestNav,
                nav_date: formattedDate
              })
              .eq("id", fund.id);

            if (!updateError) {
              updatedCount++;
            } else {
              console.error(`Failed to update ${schemeCode} in database:`, updateError.message);
            }
          }
        }
      } catch (err) {
        console.error(`Error processing NAV update for scheme ${schemeCode}:`, err);
      }
    }

    // 3. Recalculate portfolio values for all active portfolios to update current market valuations
    const { data: portfolios } = await supabase.from("portfolios").select("id");
    if (portfolios) {
      for (const p of portfolios) {
        await supabase.rpc("recalculate_portfolio_value", { portfolio_uuid: p.id });
      }
    }

    return new Response(JSON.stringify({ 
      success: true, 
      processed: dbFunds.length,
      updated: updatedCount 
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({ 
      success: false, 
      error: err instanceof Error ? err.message : String(err) 
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
