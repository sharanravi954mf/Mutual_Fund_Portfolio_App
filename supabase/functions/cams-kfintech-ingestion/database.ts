import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import { ParsedTransaction } from "./parser.ts";

export class DatabaseSyncService {
  private client = createClient(
    Deno.env.get("SUPABASE_URL") || "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
  );

  async processParsedRecord(record: ParsedTransaction): Promise<void> {
    // 1. Check if raw record already exists in cams_statements table to avoid duplicates on repeat syncs
    const { data: existingSt } = await this.client
      .from("cams_statements")
      .select("id")
      .eq("foliochk", record.foliochk)
      .eq("product", record.product)
      .eq("rep_date", record.rep_date.toISOString().split("T")[0])
      .eq("clos_bal", record.clos_bal)
      .eq("rupee_bal", record.rupee_bal)
      .maybeSingle();

    if (!existingSt) {
      const { error: insertErr } = await this.client.from("cams_statements").insert({
        foliochk: record.foliochk,
        inv_name: record.inv_name,
        address1: record.address1,
        address2: record.address2,
        address3: record.address3,
        city: record.city,
        pincode: record.pincode,
        product: record.product,
        sch_name: record.sch_name,
        rep_date: record.rep_date.toISOString().split("T")[0],
        clos_bal: record.clos_bal,
        rupee_bal: record.rupee_bal,
        pan_no: record.pan_no,
        joint1_pan: record.joint1_pan,
        joint2_pan: record.joint2_pan,
        guard_pan: record.guard_pan,
        email: record.email,
        mobile_no: record.mobile_no,
        bank_name: record.bank_name,
        branch: record.branch,
        ac_type: record.ac_type,
        ac_no: record.ac_no,
        ifsc_code: record.ifsc_code,
        nom_name: record.nom_name,
        relation: record.relation,
        nom_percen: record.nom_percen
      });

      if (insertErr) {
        console.error(`Failed to ingest record into cams_statements staging table:`, insertErr);
      }
    }

    // 2. Look up profile ID by PAN to update dynamic portfolio holdings
    const { data: profile } = await this.client
      .from("profiles")
      .select("id")
      .eq("pan", record.clientPan)
      .maybeSingle();

    let profileId: string;

    if (!profile) {
      console.log(`Creating profile for unregistered client: ${record.investorName} (PAN: ${record.clientPan})`);
      const { data: newProfile, error: profileErr } = await this.client
        .from("profiles")
        .insert({
          full_name: record.investorName,
          role: "client",
          pan: record.clientPan
        })
        .select("id")
        .single();
        
      if (profileErr || !newProfile) {
        console.error("Failed to create profile for unregistered client:", profileErr);
        return;
      }
      profileId = newProfile.id;
    } else {
      profileId = profile.id;
    }

    // 3. Upsert Mutual Fund record
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

    // 4. Get or Create Portfolio for client
    let { data: portfolio } = await this.client
      .from("portfolios")
      .select("id")
      .eq("client_id", profileId)
      .maybeSingle();

    if (!portfolio) {
      const { data: newPortfolio } = await this.client
        .from("portfolios")
        .insert({
          client_id: profileId,
          total_invested_value: 0.00,
          current_market_value: 0.00
        })
        .select("id")
        .single();
      portfolio = newPortfolio;
    }

    if (!portfolio) return;

    // 5. Check if transaction already exists to avoid duplicates on repeat syncs
    const { data: existingTx } = await this.client
      .from("transactions")
      .select("id")
      .eq("portfolio_id", portfolio.id)
      .eq("mutual_fund_id", fund.id)
      .eq("transaction_type", record.transactionType)
      .eq("units", record.units)
      .eq("amount", record.amount)
      .eq("execution_date", record.date.toISOString().split("T")[0])
      .maybeSingle();

    if (!existingTx) {
      // Insert Transaction
      await this.client.from("transactions").insert({
        portfolio_id: portfolio.id,
        mutual_fund_id: fund.id,
        transaction_type: record.transactionType,
        units: record.units,
        nav_at_transaction: record.nav,
        amount: record.amount,
        execution_date: record.date.toISOString().split("T")[0]
      });

      // Recalculate Portfolio values
      await this.client.rpc("recalculate_portfolio_value", {
        portfolio_uuid: portfolio.id
      });
    }
  }
}
