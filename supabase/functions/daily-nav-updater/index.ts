import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

serve(async (req) => {
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
        headers: { "Content-Type": "application/json" },
      });
    }

    // Map active scheme codes for fast lookup
    const activeSchemes = new Map<string, string>(); // scheme_code -> fund_id
    dbFunds.forEach(f => activeSchemes.set(f.scheme_code.trim(), f.id));

    // 2. Fetch the AMFI Daily NAV file
    const amfiUrl = "https://www.amfiindia.com/spages/NAVAll.txt";
    const amfiResponse = await fetch(amfiUrl);
    if (!amfiResponse.ok) {
      throw new Error(`Failed to fetch AMFI NAV file: ${amfiResponse.statusText}`);
    }

    const textData = await amfiResponse.text();
    const lines = textData.split(/\r?\n/);
    
    let updatedCount = 0;
    const updates = [];

    // 3. Parse lines and filter for matches
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;

      const parts = trimmed.split(";");
      if (parts.length >= 6) {
        const rawSchemeCode = parts[0].trim();
        if (activeSchemes.has(rawSchemeCode)) {
          const fundId = activeSchemes.get(rawSchemeCode)!;
          const navStr = parts[4].trim();
          const dateStr = parts[5].trim();

          const navValue = parseFloat(navStr);
          if (!isNaN(navValue)) {
            // Convert date format (e.g. "17-Jul-2026" or "17-07-2026" to "2026-07-17")
            // Parse day, month, year
            let formattedDate = "";
            try {
              const dateParts = dateStr.split("-");
              if (dateParts.length === 3) {
                const day = dateParts[0].padStart(2, "0");
                const monthRaw = dateParts[1];
                const year = dateParts[2];
                
                let month = "01";
                const months: { [key: string]: string } = {
                  jan: "01", feb: "02", mar: "03", apr: "04", may: "05", jun: "06",
                  jul: "07", aug: "08", sep: "09", oct: "10", nov: "11", dec: "12"
                };

                if (isNaN(parseInt(monthRaw))) {
                  month = months[monthRaw.toLowerCase().substring(0, 3)] || "01";
                } else {
                  month = monthRaw.padStart(2, "0");
                }
                
                formattedDate = `${year}-${month}-${day}`;
              } else {
                formattedDate = new Date(dateStr).toISOString().split("T")[0];
              }
            } catch {
              formattedDate = new Date().toISOString().split("T")[0];
            }

            updates.push({
              id: fundId,
              current_nav: navValue,
              nav_date: formattedDate
            });
          }
        }
      }
    }

    // 4. Perform updates in database
    for (const item of updates) {
      const { error: updateError } = await supabase
        .from("mutual_funds")
        .update({
          current_nav: item.current_nav,
          nav_date: item.nav_date
        })
        .eq("id", item.id);
        
      if (!updateError) {
        updatedCount++;
      }
    }

    // Recalculate portfolio values for all active portfolios to update current market valuations
    const { data: portfolios } = await supabase.from("portfolios").select("id");
    if (portfolios) {
      for (const p of portfolios) {
        await supabase.rpc("recalculate_portfolio_value", { portfolio_uuid: p.id });
      }
    }

    return new Response(JSON.stringify({ 
      success: true, 
      matched: updates.length,
      updated: updatedCount 
    }), {
      headers: { "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({ 
      success: false, 
      error: err instanceof Error ? err.message : String(err) 
    }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
