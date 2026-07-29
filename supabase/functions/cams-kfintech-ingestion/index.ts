import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  ConnectorCredentialRefresher,
  ConnectorMailboxClient,
  HttpMalwareScanner,
  RemotePdfTextExtractor,
  supabaseClient,
  SupabaseConfigRepository,
  SupabaseEncryptedStorage,
  SupabasePersistence,
} from "./adapters.ts";
import { createCamsKfintechIngestionHandler } from "./handler.ts";
import { CamsParser, KfintechParser, ParserRegistry } from "./parser.ts";

const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const client = supabaseClient(serviceRoleKey);
const pdfExtractor = new RemotePdfTextExtractor(
  Deno.env.get("PDF_TEXT_EXTRACTOR_URL") || "",
);
const mailboxConnectorUrl = Deno.env.get("MAILBOX_CONNECTOR_URL") || "";
const mailboxConnectorToken = Deno.env.get("MAILBOX_CONNECTOR_SERVICE_TOKEN") ||
  "";
const allowInsecureConnector = Deno.env.get("ALLOW_INSECURE_CONNECTOR_URL") ===
  "true";

serve(createCamsKfintechIngestionHandler({
  internalToken: Deno.env.get("MONEYBOWL_INTERNAL_INGESTION_TOKEN") || "",
  configRepository: new SupabaseConfigRepository(
    client,
    Deno.env.get("MAILBOX_OAUTH_AES256_GCM_KEY_B64") || "",
    new ConnectorCredentialRefresher(
      mailboxConnectorUrl,
      mailboxConnectorToken,
      allowInsecureConnector,
    ),
  ),
  mailboxClient: new ConnectorMailboxClient(
    mailboxConnectorUrl,
    mailboxConnectorToken,
    allowInsecureConnector,
  ),
  malwareScanner: new HttpMalwareScanner(
    Deno.env.get("MALWARE_SCANNER_URL") || "",
    Number(Deno.env.get("MALWARE_SCANNER_TIMEOUT_MS") || "5000"),
  ),
  storage: new SupabaseEncryptedStorage(client, "ingested-documents"),
  parserRegistry: new ParserRegistry([
    new CamsParser(pdfExtractor),
    new KfintechParser(pdfExtractor),
  ]),
  persistence: new SupabasePersistence(client),
}));
