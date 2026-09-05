# Hosted Dev ingestion-support runbook

This runbook deploys the provider-agnostic `ingestion-support` stack to an
already-approved Hosted Dev Docker server. It does not authorize purchasing a
host, creating a Production deployment, or copying Production data.

Issue #113 prepared these artifacts without an available host, DNS name, or
host credentials. The deployment and Hosted Dev smoke sections below therefore
remain unexecuted. Initial Gmail consent and encrypted credential provisioning
are implemented in software but remain unreviewed/unmerged and untested against
Hosted Dev; do not bypass the flow with a plaintext token, query-string token,
app password, or direct database write.

## Required external resources

- An approved Linux VPS/container server with Docker Engine and Docker Compose
  2.24.4 or newer, at least 4 GB RAM, and persistent volume storage.
- A Dev-only DNS A/AAAA record controlled by Money Bowl. TCP 80 and 443 must
  reach the server so Caddy can obtain and renew a public certificate. Restrict
  administrative access at the firewall; do not expose port 8080 or ClamAV
  port 3310.
- Monitoring for container health, certificate renewal, disk/volume capacity,
  ClamAV signature freshness, and repeated authorization failures.
- A Google OAuth web client and consent-screen test user for a synthetic/test
  Gmail mailbox. Request only
  `https://www.googleapis.com/auth/gmail.readonly`. Google classifies this as a
  restricted scope, so verification and security-assessment requirements must
  be resolved before broader use.
- Secure access to the Supabase Hosted Dev project only. Do not open or change
  the Production project while following this runbook.

Google's web-server OAuth guidance requires an exact registered HTTPS redirect
URI, a securely generated and verified `state`, server-side authorization-code
exchange, and `access_type=offline` when a refresh token is required. The
implemented flow enforces those controls and requests only Gmail read-only.

## Secret boundaries

Store the following only on the ingestion-support host, using the hosting
provider secret mechanism or a root-owned mode `0600` `.env` file:

- `MAILBOX_CONNECTOR_SERVICE_TOKEN`
- `PDF_TEXT_EXTRACTOR_SERVICE_TOKEN`
- `MALWARE_SCANNER_SERVICE_TOKEN`
- `GMAIL_OAUTH_CLIENT_ID`
- `GMAIL_OAUTH_CLIENT_SECRET`
- `GMAIL_OAUTH_REDIRECT_URI` (not secret, but exact and environment-specific)
- `CAMS_MAILBACK_ZIP_PASSWORD` (provider extraction configuration, not an MFD
  or investor credential)
- `CAMS_MAILBACK_CANDIDATE_SENDERS` (confirmed CAMS sender plus the Dev-only
  synthetic sender; not secret, but environment-specific)

Generate the three service bearer tokens independently with at least 32 random
characters. Never print them, place them on a command line, or reuse one token
for another capability. Start from `.env.hosted.example`; never commit the
resulting `.env`.

Store the following separately as Supabase **Hosted Dev Edge Function secrets**:

- `MAILBOX_CONNECTOR_URL` (`https://<approved-dev-host>`)
- `MAILBOX_CONNECTOR_SERVICE_TOKEN`
- `PDF_TEXT_EXTRACTOR_URL` (`https://<approved-dev-host>/pdf/extract`)
- `PDF_TEXT_EXTRACTOR_SERVICE_TOKEN`
- `MALWARE_SCANNER_URL` (`https://<approved-dev-host>/malware/scan`)
- `MALWARE_SCANNER_SERVICE_TOKEN`
- `GMAIL_OAUTH_REDIRECT_URI` (the exact same callback registered with Google)

The matching token at the host and in Hosted Dev must be the same for each
capability. Do not read, rotate, remove, or replace existing values such as
`MONEYBOWL_INTERNAL_INGESTION_TOKEN`,
`MAILBOX_OAUTH_AES256_GCM_KEY_B64`, or
`ORDER_AUTO_APPROVAL_WORKER_TOKEN`. Do not migrate Supabase legacy API keys as
part of Issue #113.

## Deploy the host stack

1. Resolve the approved hostname and verify its DNS points only to the Dev host.
2. Check out the reviewed commit under a root-owned service directory. Create
   `.env` from `.env.hosted.example`, substitute secrets through the approved
   secret mechanism, set `ALLOWED_HOSTS` to the exact Dev hostname plus
   `localhost,127.0.0.1` for internal health and readiness requests (never
   `*`), and restrict the file to the service administrator.
   Keep `MAX_PROVIDER_RESPONSE_BYTES=1048576` for small OAuth/list provider
   responses and
   `MAX_GMAIL_MESSAGE_DETAIL_RESPONSE_BYTES=4194304` for partial Gmail message
   details. The detail ceiling is independent from attachment-byte limits and,
   with the fixed default concurrency of five, caps simultaneous raw detail
   buffers at 20 MiB. Do not raise either value during the smoke test. Retain
   the reviewed CAMS mailback ZIP, DBF, entry-count, and decompression-ratio
   bounds. Do not put the ZIP password in an Edge Function secret: extraction
   occurs only on this host.
3. Validate the merged Compose model before starting anything:

   ```sh
   docker compose --env-file .env \
     -f compose.yaml -f compose.hosted.yaml config --quiet
   ```

4. Pull pinned images, rebuild the non-root API image, and start the stack:

   ```sh
   docker compose --env-file .env \
     -f compose.yaml -f compose.hosted.yaml pull
   docker compose --env-file .env \
     -f compose.yaml -f compose.hosted.yaml build --pull api
   docker compose --env-file .env \
     -f compose.yaml -f compose.hosted.yaml up -d
   ```

The hosted override removes the API's loopback development port. Caddy is the
only published service, on TCP 80/443. It obtains HTTPS automatically and has
no request-access-log directive. `clamd` remains private and its signature
database persists in `clamav_db`. Caddy certificate/config state persists in
`caddy_data` and `caddy_config`.

## Host verification

Before configuring Supabase, verify all of the following from a trusted
administrator workstation:

1. `docker compose ... ps` shows exactly one `api`, one `caddy`, and one
   `clamav` container. The API Dockerfile fixes Uvicorn at `--workers 1`; the
   hosted Compose model fixes the API at `scale: 1` and `deploy.replicas: 1`.
2. Only 80/443 are publicly reachable. Ports 8080 and 3310 must fail from an
   external network.
3. The HTTPS certificate is valid for the exact hostname; redirects remain on
   that origin and no TLS verification bypass is used.
4. `GET /health` returns `{"status":"ok"}` and `GET /ready` returns
   `{"status":"ready"}`. Readiness proves the API can ping the private ClamAV
   daemon after its signatures load.
5. Recent API logs contain only the sanitized event, request ID, method, known
   route, status, and duration fields. Caddy logs contain operational/TLS events
   only. Do not paste logs into tickets until checked for secrets and PII.

Run the checked-in integration smoke test with secrets injected as environment
variables by the approved secret manager:

```sh
INGESTION_SUPPORT_BASE_URL=https://<approved-dev-host> \
python -m pytest -m integration
```

Do not set `ALLOW_INSECURE_LOCAL_SMOKE_URL` for a hosted target. The test refuses
non-HTTPS non-loopback URLs, follows no redirects, verifies the default CA
chain, checks `/health` and `/ready`, rejects invalid bearers for all three
capabilities, proves the correct mailbox bearer reaches the OAuth boundary,
extracts a deterministic synthetic CAMS PDF, and verifies clean plus EICAR
ClamAV verdicts. EICAR is test data, not malware.

## Configure Hosted Dev and run E2E

Only after the host verification succeeds, add the support URL/token names and
exact Gmail callback listed above to the Hosted Dev Edge Function settings. The repository's
GitHub-integrated deployment remains authoritative; do not manually deploy the
Edge Function, relink Supabase, run `supabase db push`, or use the retired
`deploy_ingestion.sh`.

Do not start the end-to-end test until this OAuth implementation is reviewed and
merged. Provision only a development/test mailbox and test workspace through
the authorized `/oauth/start` flow; never inject credentials manually.

Keep these validation layers distinct:

1. **Local automated CAMS contract tests** use synthetic CAMS HTML, a validated
   CAMS-style URL, mocked HTTPS networking, a password-protected synthetic ZIP,
   and a synthetic DBF. They deterministically prove WBR2/WBR9, No Data, WBR49,
   URL, password, extraction, and archive-security behavior without contacting
   CAMS or using investor data.
2. **Hosted Dev synthetic infrastructure smoke** uses the preserved generic
   Gmail attachment path with the existing synthetic DBF fixture. It proves the
   deployed Gmail, Oracle ingestion-support, integrity, ClamAV, Storage, parser,
   and Dev-persistence infrastructure. It does not exercise or prove a live
   CAMS `DownloadURL` network leg.
3. **Real CAMS mailback characterization** remains pending. It must separately
   verify a genuine WBR2/WBR9 email, real
   `mailback<number>.camsonline.com` URL, CAMS-encrypted ZIP, and DBF extraction
   only when an explicitly authorized, appropriately sanitized sample is
   available. Never automate this with real investor data.

Passing the first two layers does not mean that the third has passed. Do not
fabricate a CAMS-domain endpoint, add a synthetic hostname to the runtime
allowlist, or weaken URL, TLS, redirect, ZIP, integrity, or malware controls to
make the Hosted Dev smoke resemble the live-provider boundary.

For the controlled test:

1. Record the Dev workspace, mailbox connection, synthetic message ID, and a
   unique `SYNTHETIC-ISSUE-113-<timestamp>` marker without recording any token.
2. From the sender configured only in Hosted Dev through
   `CAMS_MAILBACK_CANDIDATE_SENDERS`, send a synthetic Gmail message with the
   existing synthetic DBF fixture as an ordinary attachment. Use only synthetic
   values and never a real investor identifier or document. Do not include a
   CAMS `DownloadURL`, impersonate the production sender, or configure the Dev
   sender in Production.
3. As an authorized advisor/admin, start Gmail consent through the Edge OAuth
   route and verify the safe connected response contains no token. Then invoke
   the smallest existing authenticated
   `cams-kfintech-ingestion` request path using a valid initiating Dev user and
   the existing internal gateway token. Do not weaken its user/workspace
   authorization and do not add scheduling.
4. Verify OAuth load/refresh, generic Gmail attachment discovery and fetch,
   post-read sender validation, SHA validation, clean ClamAV verdict, Storage,
   existing DBF parsing, and Dev persistence. Preserve the request/ingestion
   IDs as non-secret QA evidence. Keep WBR2/WBR9 mailback, no-data/NA, WBR49,
   URL, and encrypted-ZIP outcomes in the local mocked contract suite; this
   Hosted Dev smoke makes no claim about them crossing the live CAMS network
   boundary.
5. Inspect sanitized service and Edge logs for the marker and outcome. Confirm
   no bearer, OAuth token, sender, DownloadURL, request ID, ZIP password, email
   body, ZIP/DBF bytes, PAN, or folio was logged.

Issue #109 and #113 remain open unless the required Hosted Dev flow succeeds.
Even after that smoke passes, record real CAMS mailback characterization as a
separate pending production-readiness boundary until authorized sanitized
evidence exists.

## Rollback and cleanup

To disable the Dev integration, first remove only the support-service URL/token
and Gmail callback settings added to Hosted Dev, then stop the external stack:

```sh
docker compose --env-file .env \
  -f compose.yaml -f compose.hosted.yaml down
```

Do not delete `clamav_db` or Caddy volumes during a routine rollback. Preserve
database, Storage, ingestion, and audit history; no schema rollback is needed.
Do not touch any Production setting.

After QA evidence is captured, remove the synthetic message from the test
mailbox and revoke/disable the test mailbox connection through the approved
application flow if it is no longer needed. Synthetic database or Storage
records must be cleaned only through an approved application/data-retention
path that preserves immutable audit lineage—never by ad hoc destructive SQL.
Record any retained synthetic IDs in the issue so later cleanup is explicit.


---

## Generic outbox dispatcher

The Oracle-hosted generic dispatcher is intentionally separate from the public
ingestion API. It exposes no port and is not part of the default Compose
profile.

The initial routing table enables only the existing NSE UCC registration and
Client Master verification workers. Adding a future API requires a reviewed
route; the dispatcher itself must not contain NSE business rules.

### Host secrets

Add these values only to the existing root-owned mode `0600` Hosted Dev
`.env` file:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `NSE_UCC_WORKER_TOKEN`
- `NSE_UCC_RECONCILIATION_WORKER_TOKEN`

The two worker-token values must match their Hosted Dev Edge Function secrets.
Never print any of these values or place them on a command line.

Keep these safe defaults until live dispatch is explicitly approved:

- `OUTBOX_DISPATCH_DRY_RUN=true`
- `OUTBOX_POLL_INTERVAL_SECONDS=5`
- `OUTBOX_RETRY_DELAY_SECONDS=30`
- `OUTBOX_BATCH_SIZE=10`
- `OUTBOX_HTTP_TIMEOUT_SECONDS=45`

### Build and validate without dispatching NSE work

The service is behind the `outbox-dispatch` profile. Normal Hosted Dev stack
startup does not start it.

Build its runtime image:

```sh
docker compose --env-file .env \
  -f compose.yaml -f compose.hosted.yaml \
  --profile outbox-dispatch build --pull outbox-dispatcher
```

Validate configuration without starting the polling loop:

```sh
docker compose --env-file .env \
  -f compose.yaml -f compose.hosted.yaml \
  --profile outbox-dispatch run --rm outbox-dispatcher \
  python -c "from dispatcher import Settings,load_routes; s=Settings.from_env(); load_routes(s.routes_file); print('dispatcher-config-ok')"
```

Run the unit-test image independently of Hosted Dev credentials:

```sh
docker build --target test -t moneybowl-outbox-dispatcher-test ../outbox-dispatcher
docker run --rm moneybowl-outbox-dispatcher-test
```

After the database migration is present, the dispatcher may be started in
dry-run mode for read-only observation:

```sh
docker compose --env-file .env \
  -f compose.yaml -f compose.hosted.yaml \
  --profile outbox-dispatch up -d outbox-dispatcher
```

Confirm `dispatcher_started` reports `"dry_run":true`. Dry-run may read only
the narrow dispatch metadata feed; it does not invoke workers.

### Live activation

Setting `OUTBOX_DISPATCH_DRY_RUN=false` makes the dispatcher invoke workers.
For NSE routes, that can cause actual UAT NSE requests whenever an eligible
outbox event exists. Do not make this change merely to test Docker or
connectivity.

Live activation therefore requires explicit approval after the local SQL
regression, dispatcher unit tests, Compose validation, dry-run observation, and
a read-only review of queued Hosted Dev events.

The dispatcher never updates `event_outbox` itself. Worker claim/lease RPCs
remain the ownership fence. If the dispatcher is stopped, events stay durable
and can be resumed later.
