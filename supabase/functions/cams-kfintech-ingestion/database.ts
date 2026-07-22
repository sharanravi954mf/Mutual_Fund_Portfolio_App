import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import { ParsedTransaction } from "./parser.ts";

export class DatabaseSyncService {
  private client = createClient(
    Deno.env.get("SUPABASE_URL") || "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
  );

  /**
   * Invokes process_cams_records batch stored procedure on Supabase to prevent N+1 CPU timeouts.
   */
  async processParsedRecordsBatch(records: ParsedTransaction[]): Promise<void> {
    if (records.length === 0) return;
    
    console.log(`Streaming batch of ${records.length} records to process_cams_records database function...`);
    
    // Format dates to string to avoid JSON serialization issues
    const formattedRecords = records.map(r => ({
      clientPan: r.clientPan,
      registrar: r.registrar,
      investorName: r.investorName,
      schemeCode: r.schemeCode,
      schemeName: r.schemeName,
      fundHouse: r.fundHouse,
      category: r.category,
      transactionType: r.transactionType,
      units: r.units,
      nav: r.nav,
      amount: r.amount,
      foliochk: r.foliochk,
      inv_name: r.inv_name,
      address1: r.address1,
      address2: r.address2,
      address3: r.address3,
      city: r.city,
      pincode: r.pincode,
      product: r.product,
      sch_name: r.sch_name,
      clos_bal: r.clos_bal,
      rupee_bal: r.rupee_bal,
      email: r.email,
      mobile_no: r.mobile_no,
      bank_name: r.bank_name,
      branch: r.branch,
      ac_type: r.ac_type,
      ac_no: r.ac_no,
      ifsc_code: r.ifsc_code,
      nom_name: r.nom_name,
      relation: r.relation,
      nom_percen: r.nom_percen,
      rep_date: r.rep_date.toISOString().split("T")[0],
      date: r.date.toISOString().split("T")[0]
    }));

    const { error } = await this.client.rpc("process_cams_records", {
      records: formattedRecords
    });

    if (error) {
      console.error("Failed to run batch ingestion in database:", error);
      throw error;
    }
  }
}
