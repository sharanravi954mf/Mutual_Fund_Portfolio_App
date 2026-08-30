import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  ConnectorCredentialRefresher,
  ConnectorGmailOAuthClient,
  ConnectorMailboxClient,
  CredentialEnvelopeCrypto,
  HttpMalwareScanner,
  RemotePdfTextExtractor,
  supabaseClient,
  SupabaseConfigRepository,
  SupabaseEncryptedStorage,
  SupabaseOAuthStateRepository,
  SupabasePersistence,
  SupabaseWorkspaceAuthorizer,
} from "./adapters.ts";
import { createCamsKfintechIngestionHandler } from "./handler.ts";
import { createHostedDevCamsDbfDiagnosticHandler } from "./hosted_dev_diagnostic.ts";
import { createGmailOAuthHandler } from "./oauth.ts";
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
const credentialKey = Deno.env.get("MAILBOX_OAUTH_AES256_GCM_KEY_B64") || "";
const workspaceAuthorizer = new SupabaseWorkspaceAuthorizer(client);
const configRepository = new SupabaseConfigRepository(
  client,
  credentialKey,
  new ConnectorCredentialRefresher(
    mailboxConnectorUrl,
    mailboxConnectorToken,
    allowInsecureConnector,
    mailboxConnectorTimeoutMs,
    mailboxConnectorMaxResponseBytes,
  ),
);

const ingestionHandler = createCamsKfintechIngestionHandler({
  internalToken: Deno.env.get("MONEYBOWL_INTERNAL_INGESTION_TOKEN") || "",
  workspaceAuthorizer,
  configRepository,
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
});

const oauthHandler = createGmailOAuthHandler({
  redirectUri: Deno.env.get("GMAIL_OAUTH_REDIRECT_URI") || "",
  workspaceAuthorizer,
  stateRepository: new SupabaseOAuthStateRepository(client),
  credentials: {
    encrypt: (bundle, workspaceId, mailboxConnectionId) =>
      new CredentialEnvelopeCrypto(credentialKey).encrypt(
        bundle,
        workspaceId,
        mailboxConnectionId,
      ),
    loadForRevocation: (workspaceId, mailboxConnectionId) =>
      configRepository.loadForRevocation(workspaceId, mailboxConnectionId),
  },
  connector: new ConnectorGmailOAuthClient(
    mailboxConnectorUrl,
    mailboxConnectorToken,
    allowInsecureConnector,
    mailboxConnectorTimeoutMs,
    mailboxConnectorMaxResponseBytes,
  ),
});

const hostedDevDiagnosticHandler = createHostedDevCamsDbfDiagnosticHandler({
  internalToken: Deno.env.get("MONEYBOWL_INTERNAL_INGESTION_TOKEN") || "",
  projectUrl: Deno.env.get("SUPABASE_URL") || "",
  readOriginal: (object) =>
    new SupabaseEncryptedStorage(client, object.bucket).readOriginal(object),
});

serve((req: Request) => {
  const path = new URL(req.url).pathname;
  if (
    path.endsWith("/oauth/start") || path.endsWith("/oauth/callback") ||
    path.endsWith("/oauth/revoke")
  ) return oauthHandler(req);
  if (path.endsWith("/diagnostics/cams-dbf")) {
    return hostedDevDiagnosticHandler(req);
  }
  return ingestionHandler(req);
});
