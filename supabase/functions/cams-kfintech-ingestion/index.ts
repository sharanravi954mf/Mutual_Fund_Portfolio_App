import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { ImapClient } from "./imap_client.ts";
import { RtaFileParser } from "./parser.ts";
import { DatabaseSyncService } from "./database.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") || "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
  );

  // 1. Log beginning of the ingestion job
  const { data: logEntry } = await supabase
    .from("ingestion_logs")
    .insert({ status: "RUNNING" })
    .select("id")
    .single();

  const logId = logEntry?.id;
  let recordsProcessed = 0;

  try {
    const imap = new ImapClient();
    const parser = new RtaFileParser();
    const db = new DatabaseSyncService();

    // 2. Fetch attachments
    const attachments = await imap.fetchNewReportAttachments();

    // 3. Process each attachment
    for (const attachment of attachments) {
      const parsedStream = parser.parseFileStream(attachment.filename, attachment.data);
      for await (const record of parsedStream) {
        await db.processParsedRecord(record);
        recordsProcessed++;
      }
    }

    // 4. Update log success status
    if (logId) {
      await supabase
        .from("ingestion_logs")
        .update({
          status: "SUCCESS",
          completed_at: new Date().toISOString(),
          records_processed: recordsProcessed
        })
        .eq("id", logId);
    }

    return new Response(JSON.stringify({ success: true, processed: recordsProcessed }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    // 5. Update log failure status
    if (logId) {
      await supabase
        .from("ingestion_logs")
        .update({
          status: "FAILED",
          completed_at: new Date().toISOString(),
          error_message: err instanceof Error ? err.message : String(err)
        })
        .eq("id", logId);
    }

    return new Response(JSON.stringify({ success: false, error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
