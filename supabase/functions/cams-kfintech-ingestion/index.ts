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
  SupabaseWorkspaceAuthorizer,
} from "./adapters.ts";
import { createCamsKfintechIngestionHandler } from "./handler.ts";
import { CamsParser, KfintechParser, ParserRegistry } from "./parser.ts";

const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const client = supabaseClient(serviceRoleKey);
const pdfExtractor = new RemotePdfTextExtractor(
  Deno.env.get("PDF_TEXT_EXTRACTOR_URL") || "",
  Deno.env.get("PDF_TEXT_EXTRACTOR_SERVICE_TOKEN") || "",
  Number(Deno.env.get("PDF_TEXT_EXTRACTOR_TIMEOUT_MS") || "5000"),
  Number(Deno.env.get("PDF_TEXT_EXTRACTOR_MAX_RESPONSE_BYTES") || "1048576"),
  Deno.env.get("ALLOW_INSECURE_PDF_TEXT_EXTRACTOR_URL") === "true",
);
const mailboxConnectorUrl = Deno.env.get("MAILBOX_CONNECTOR_URL") || "";
const mailboxConnectorToken = Deno.env.get("MAILBOX_CONNECTOR_SERVICE_TOKEN") ||
  "";
const allowInsecureConnector = Deno.env.get("ALLOW_INSECURE_CONNECTOR_URL") ===
  "true";
const mailboxConnectorTimeoutMs = Number(
  Deno.env.get("MAILBOX_CONNECTOR_TIMEOUT_MS") || "5000",
);
const mailboxConnectorMaxResponseBytes = Number(
  Deno.env.get("MAILBOX_CONNECTOR_MAX_RESPONSE_BYTES") || "1048576",
);
const mailboxAttachmentDownloadTimeoutMs = Number(
  Deno.env.get("MAILBOX_ATTACHMENT_DOWNLOAD_TIMEOUT_MS") || "10000",
);

serve(createCamsKfintechIngestionHandler({
  internalToken: Deno.env.get("MONEYBOWL_INTERNAL_INGESTION_TOKEN") || "",
  workspaceAuthorizer: new SupabaseWorkspaceAuthorizer(client),
  configRepository: new SupabaseConfigRepository(
    client,
    Deno.env.get("MAILBOX_OAUTH_AES256_GCM_KEY_B64") || "",
    new ConnectorCredentialRefresher(
      mailboxConnectorUrl,
      mailboxConnectorToken,
      allowInsecureConnector,
      mailboxConnectorTimeoutMs,
      mailboxConnectorMaxResponseBytes,
    ),
  ),
  mailboxClient: new ConnectorMailboxClient(
    mailboxConnectorUrl,
    mailboxConnectorToken,
    allowInsecureConnector,
    mailboxConnectorTimeoutMs,
    mailboxConnectorMaxResponseBytes,
    mailboxAttachmentDownloadTimeoutMs,
  ),
  malwareScanner: new HttpMalwareScanner(
    Deno.env.get("MALWARE_SCANNER_URL") || "",
    Deno.env.get("MALWARE_SCANNER_SERVICE_TOKEN") || "",
    Number(Deno.env.get("MALWARE_SCANNER_TIMEOUT_MS") || "5000"),
    Number(Deno.env.get("MALWARE_SCANNER_MAX_RESPONSE_BYTES") || "4096"),
    Deno.env.get("ALLOW_INSECURE_MALWARE_SCANNER_URL") === "true",
  ),
  storage: new SupabaseEncryptedStorage(client, "ingested-documents"),
  parserRegistry: new ParserRegistry([
    new CamsParser(pdfExtractor),
    new KfintechParser(pdfExtractor),
  ]),
  persistence: new SupabasePersistence(client),
}));
