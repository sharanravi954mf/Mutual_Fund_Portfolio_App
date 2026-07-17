import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import { ParsedTransaction } from "./parser.ts";

export class DatabaseSyncService {
  private client = createClient(
    Deno.env.get("SUPABASE_URL") || "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
  );

  async processParsedRecord(record: ParsedTransaction): Promise<void> {
    // 1. Look up profile ID by PAN
    const { data: profile } = await this.client
      .from("profiles")
      .select("id")
      .eq("pan", record.clientPan)
      .maybeSingle();

    if (!profile) {
      // Skipping if profile doesn't exist yet
      return;
    }

    // 2. Upsert Mutual Fund record
    const { data: fund } = await this.client
      .from("mutual_funds")
      .upsert({
        scheme_code: record.schemeCode,
        scheme_name: record.schemeName,
        fund_house: record.fundHouse,
        category: record.category,
        current_nav: record.nav,
        nav_date: record.date.toISOString().split("T")[0]
      }, { onConflict: "scheme_code" })
      .select("id")
      .single();

    if (!fund) return;

    // 3. Get or Create Portfolio for client
    let { data: portfolio } = await this.client
      .from("portfolios")
      .select("id")
      .eq("client_id", profile.id)
      .maybeSingle();

    if (!portfolio) {
      const { data: newPortfolio } = await this.client
        .from("portfolios")
        .insert({
          client_id: profile.id,
          total_invested_value: 0.00,
          current_market_value: 0.00
        })
        .select("id")
        .single();
      portfolio = newPortfolio;
    }

    if (!portfolio) return;

    // 4. Insert Transaction
    await this.client.from("transactions").insert({
      portfolio_id: portfolio.id,
      mutual_fund_id: fund.id,
      transaction_type: record.transactionType,
      units: record.units,
      nav_at_transaction: record.nav,
      amount: record.amount,
      execution_date: record.date.toISOString().split("T")[0]
    });

    // 5. Call Stored Procedure to recalculate Portfolio values
    await this.client.rpc("recalculate_portfolio_value", {
      portfolio_uuid: portfolio.id
    });
  }
}
