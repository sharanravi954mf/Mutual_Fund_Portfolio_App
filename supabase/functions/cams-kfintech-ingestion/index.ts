import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { ImapClient } from "./imap_client.ts";
import { RtaFileParser } from "./parser.ts";
import { DatabaseSyncService } from "./database.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import { requireAdvisor } from "../_shared/authorization.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const authorization = await requireAdvisor(req);
  if ("failure" in authorization) {
    return new Response(
      JSON.stringify({ error: authorization.failure.message }),
      {
        status: authorization.failure.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

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
  let parser: RtaFileParser | null = null;

  try {
    const imap = new ImapClient();
    parser = new RtaFileParser();
    const db = new DatabaseSyncService();

    // 2. Fetch attachments
    const attachments = await imap.fetchNewReportAttachments();

    // 3. Process each attachment in a single batch
    for (const attachment of attachments) {
      const parsedStream = parser.parseFileStream(attachment.filename, attachment.data);
      const batch = [];
      for await (const record of parsedStream) {
        batch.push(record);
      }
      if (batch.length > 0) {
        console.log(`Ingesting batch of ${batch.length} parsed records...`);
        await db.processParsedRecordsBatch(batch);
        recordsProcessed += batch.length;
      }
    }

    // 4. Update log success status
    if (logId) {
      await supabase
        .from("ingestion_logs")
        .update({
          status: "SUCCESS",
          completed_at: new Date().toISOString(),
          records_processed: recordsProcessed,
          log_details: {
            totalLinesProcessed: parser.totalLinesProcessed,
            totalRecordsParsed: parser.totalRecordsParsed,
            totalErrors: parser.totalErrors,
            errors: parser.errors
          }
        })
        .eq("id", logId);
    }

    return new Response(JSON.stringify({ 
      success: true, 
      processed: recordsProcessed,
      totalLines: parser.totalLinesProcessed,
      totalErrors: parser.totalErrors
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    // 5. Update log failure status
    if (logId) {
      await supabase
        .from("ingestion_logs")
        .update({
          status: "FAILED",
          completed_at: new Date().toISOString(),
          error_message: err instanceof Error ? err.message : String(err),
          log_details: {
            totalLinesProcessed: parser?.totalLinesProcessed || 0,
            totalRecordsParsed: parser?.totalRecordsParsed || 0,
            totalErrors: parser?.totalErrors || 0,
            errors: parser?.errors || []
          }
        })
        .eq("id", logId);
    }

    return new Response(JSON.stringify({ success: false, error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
