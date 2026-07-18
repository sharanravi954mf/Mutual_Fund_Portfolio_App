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
      ...r,
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
