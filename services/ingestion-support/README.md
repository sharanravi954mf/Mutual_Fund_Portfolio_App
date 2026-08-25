# Money Bowl ingestion-support

`ingestion-support` is the provider-host-agnostic external service stack used by
the existing `cams-kfintech-ingestion` Edge Function. It keeps the Edge worker,
database, Storage, and Auth contracts unchanged while providing three logically
separate capabilities from one small deployment:

- Gmail OAuth mailbox connector (`/oauth/authorization-url`, `/oauth/exchange`,
  `/oauth/revoke`, `/oauth/refresh`, `/poll`, and `/attachments/fetch`);
- PDF extraction infrastructure plus a deterministic synthetic/characterization
  contract (`/pdf/extract`);
- in-memory ClamAV `INSTREAM` scanning (`/malware/scan`).

Python/FastAPI is used because its mature PDF and streaming HTTP libraries keep
the adapter code small and testable. ClamAV is a separate container so virus
signatures can be refreshed independently of application builds. The service
does not use IMAP passwords, OCR, external AI, third-party document scanning,
or persistent statement files.

## Runtime architecture

```text
Supabase Edge Function over HTTPS
  |-- mailbox bearer --> FastAPI --> fixed Gmail OAuth/Gmail API origins
  |                                  `-> validated CAMS mailback HTTPS origin
  |-- PDF bearer -----> FastAPI --> bounded pypdf memory extraction
  `-- malware bearer -> FastAPI --> private Docker network --> clamd INSTREAM
```

The API runs as a non-root, read-only container with no Linux capabilities.
`clamd` is reachable only on the private Compose network; port 3310 is never
published. The API port is bound to `127.0.0.1` for local development. The
hosted override removes that port mapping and adds a pinned Caddy reverse proxy
that is the only public ingress on ports 80/443. See `HOSTED_DEV_RUNBOOK.md`.

## Edge-owned endpoint contract

| Edge setting | Value shape | Support endpoint |
| :--- | :--- | :--- |
| `MAILBOX_CONNECTOR_URL` | Base URL, for example `https://ingestion.example.test` | Worker appends OAuth provisioning/refresh plus mailbox poll/fetch paths |
| `PDF_TEXT_EXTRACTOR_URL` | Full URL | `https://ingestion.example.test/pdf/extract` |
| `MALWARE_SCANNER_URL` | Full URL | `https://ingestion.example.test/malware/scan` |

All POST routes require their own exact `Authorization: Bearer ...` token. The
mailbox poll also requires `X-Mailbox-OAuth-Token`; PDF extraction requires
`X-Registrar`, `X-Statement-Format`, and `X-File-Name`; malware scanning
requires `X-Content-SHA256` and `X-File-Name`. `/health` and `/ready` are
unauthenticated and return status only. Readiness fails while `clamd` or its
signature database is unavailable.

Application diagnostics are explicit INFO-level JSON lines written to stdout
for `docker logs`; raw Uvicorn access logging remains disabled. Request events
contain only event, random request ID, method, allowlisted route, status, and
duration. A successful mailbox poll also emits message and attachment counts,
including zero counts for a successful empty poll. `ServiceError` events contain
only request ID, sanitized internal code, HTTP status, and, for three bounded
Gmail poll failures, an optional strict allowlisted diagnostic reason. The
reason distinguishes oversized Gmail list responses, oversized individual
message-detail responses, and per-message attachment-count overflow; it is
never returned by the public API. Bodies, headers, provider identities,
filenames, senders, subjects, URLs/query strings, document content, and
credentials are never included. Logger configuration is idempotent and does not propagate, so
repeated app construction does not add handlers or duplicate lines.

The response versions and snake-case fields intentionally match the current
TypeScript classes in
`supabase/functions/cams-kfintech-ingestion/adapters.ts`:

- PDF: `moneybowl.pdf-extraction.v1`;
- malware: `moneybowl.malware-scan.v1`;
- mailbox: `access_token`, optional `refresh_token`/`expires_at`, and the
  existing `messages`/attachment metadata fields.

## Local Docker Compose

1. Copy `.env.example` to the ignored `.env` file.
2. Generate three distinct random service tokens of at least 32 characters.
3. Add a Google OAuth client ID/secret and the exact Edge callback URI for a
   development-only Gmail account.
4. Set the CAMS mailback ZIP password as provider extraction configuration.
   The checked-in example value is Dev-only; never reuse an investor/MFD
   credential or commit a hosted secret.
5. Start the stack:

   ```sh
   docker compose up --build -d
   docker compose ps
   curl --fail http://127.0.0.1:8080/health
   curl --fail http://127.0.0.1:8080/ready
   ```

6. Stop it without deleting the ClamAV signature volume:

   ```sh
   docker compose down
   ```

ClamAV loads a large signature database. Allocate at least 4 GB RAM to Docker
for reliable startup. Initial startup can take several minutes while signatures
download and load. The Compose file pins the API runtime/dependencies and
ClamAV 1.5.4; signature updates remain in the `clamav_db` volume.

## Gmail OAuth setup

The initial provider is Gmail behind the `MailboxProvider` interface. Hosted
setup remains deferred until after review and merge:

1. Create a Google Cloud project for the Dev integration and enable Gmail API.
2. Configure an OAuth consent screen and a server-side OAuth client.
3. Register `GMAIL_OAUTH_REDIRECT_URI` exactly in Google and set the identical
   value in the support service and Edge Function environment.
4. An authorized advisor/admin calls `/oauth/start`; the Edge Function creates
   a 256-bit random, single-use, ten-minute state and stores only its SHA-256
   digest. Google consent requests only Gmail read-only scope, offline access,
   and explicit consent.
5. Google returns to `/oauth/callback`. The Edge Function validates the exact
   redirect and atomically consumes the state before the support service
   exchanges the code server-side. A missing first-time refresh token fails
   closed.
6. The Edge Function writes access/refresh/expiry only as the existing
   AES-256-GCM envelope with workspace/mailbox/key-version AAD. Reauthorization
   uses the same fenced upsert. `/oauth/revoke` revokes server-side, deletes the
   envelope through an authorized RPC, and marks the mailbox
   `reauthorization_required`.
6. Use connector reference `gmail:me` (or `gmail:<mailbox-address>`). Provider
   origins are fixed configuration, never request-controlled URLs.

No `IMAP_USER`, `IMAP_PASSWORD`, Google app password, Supabase service-role key,
or `RTA_DECRYPTION_PASSWORD` belongs in this service. The separate
`CAMS_MAILBACK_ZIP_PASSWORD` is provider extraction configuration and is never
treated as an MFD credential. OAuth tokens, codes, and the ZIP password are
never logged, placed in client storage, or persisted by the support service;
automated provider tests use mocks only.

For KFintech and generic attachment flows, mailbox polling keeps the Gmail query
`has:attachment {filename:pdf filename:dbf}`. CAMS discovery instead uses the
configured registrar candidate senders and matches either WBR mailback messages
or PDF/DBF attachments; it does not require `has:attachment` for URL mailbacks.
The production candidate currently configured by default is
`donotreply@camsonline.com`; the Dev synthetic sender is opt-in only through
`CAMS_MAILBACK_CANDIDATE_SENDERS`. Gmail filtering is candidate reduction, not
the trust boundary: the Edge worker validates the sender from the fetched
message before any attachment or mailback bytes are retrieved. Each poll
inspects at most
`MAX_MAILBOX_PAGES_PER_POLL` pages (default `4`) and
`MAX_MAILBOX_CANDIDATES_PER_POLL` message candidates (default `100`). Gmail
page tokens must be non-empty, bounded printable ASCII and must not repeat.
Page listing remains sequential. Within each page, a fixed worker pool fetches
message details with `GMAIL_DETAIL_FETCH_CONCURRENCY` concurrent requests
(default `5`, allowed range `1..10`). Results are restored to Gmail listing
order before attachment filtering, and any failed detail request cancels and
awaits its sibling workers before the poll fails closed. Detail requests keep
Gmail `format=full` because attachment discovery and small inline attachments
require the parsed MIME body, but use a partial-response `fields` selector for
only `id`, `internalDate`, the root headers, and the MIME fields consumed by the
connector. Gmail field masks cannot conditionally include `body.data` only for
filename-bearing parts while also expressing an arbitrary recursive `parts`
tree, so the selector deliberately retains the complete recursive `parts`
subtree and omits unrelated top-level message fields such as snippet, labels,
thread/history metadata, size estimates, and classification labels.

OAuth, list, and other small provider JSON responses remain bounded by
`MAX_PROVIDER_RESPONSE_BYTES` (default 1 MiB). Message-detail poll and inline
fetch responses use the separate
`MAX_GMAIL_MESSAGE_DETAIL_RESPONSE_BYTES` ceiling (default and maximum 4 MiB,
minimum 1 MiB, and never below the generic provider limit). This does not reuse
or raise `MAX_ATTACHMENT_BYTES`. At the default detail concurrency of five,
at most 20 MiB of raw detail response buffers can be active; the allowed
concurrency maximum of ten caps that raw-buffer total at 40 MiB. Oversized or
malformed required MIME data still fails closed.
Messages with actual attachments are selected page-fairly across the inspected
pages, up to the existing `MAX_MAILBOX_MESSAGES` output limit (default `25`).
The Edge worker remains the authority for the configured sender allowlist.
Gmail attachment parts may carry either a provider `attachmentId` or small
base64url content in `body.data`. Poll responses expose metadata only. Inline
parts receive a bounded `inline:<sha256>` identity that is disjoint from Gmail
provider IDs; attachment bytes are decoded only for validation and are not
included in the poll response.

For CAMS messages without attachments, the connector reads only the sender,
internal date, subject, and filename-less `text/html` or `text/plain` MIME
parts needed for `DownloadURL`, `Request Status`, `Report No`, and `File Type`.
Only WBR2 and WBR9 with DBF output are supported. A data response requires the
confirmed `Request Status = Link` plus a validated CAMS ZIP `DownloadURL`;
unconfirmed values such as `Completed` fail closed. WBR49 and any other report
number produce the sanitized `unsupported_report` outcome and are never
downloaded or parsed as a supported report. `Request Status = No Data` together
with `DownloadURL = NA` is a completed zero-attempt `no_data` result, not a
provider failure. Mixed Link/NA or No Data/URL combinations fail closed.

Supported mailbacks expose only an opaque `mailback:<sha256>` attachment
identity. The original URL stays in a bounded process-local cache and must be
HTTPS on an exact `mailback<number>.camsonline.com` host, have no credentials,
port, query, or fragment, and use `/mailback_result/<opaque>.zip`. Redirects are
rejected. Download time and compressed bytes are bounded. The encrypted ZIP is
opened in memory with `CAMS_MAILBACK_ZIP_PASSWORD`; entry count, compressed and
uncompressed sizes, decompression ratio, duplicate names, traversal/absolute
paths, nested archives, encryption, and the exactly-one-DBF shape all fail
closed. The extracted DBF bytes use the existing Edge hash, MIME, malware,
Storage-integrity, and DBF-parser path; no second DBF parser or persistent local
statement file is introduced.

## PDF layouts and limitations

This PR establishes PDF extraction infrastructure and a deterministic
synthetic/characterization contract. It performs no OCR or heuristic field
guessing. The only enabled layouts are generated synthetic/normalized fixtures
that start with
`MONEYBOWL_CAMS_CAS_V1` or `MONEYBOWL_KFINTECH_CAS_V1`, followed by a
pipe-delimited header and rows whose field names are aliases already accepted
by the Edge parser. Encrypted, malformed, excessive-page, excessive-row,
unknown-layout, and oversized PDFs fail closed.

No sanitized representative CAMS/KFintech CAS statement PDF fixture exists in
the repository. The existing CAMS PDF under `test/fixtures/cams/` is an Invoice
Signer fixture, not a registrar statement parser fixture. Therefore this
service does not claim support for arbitrary or live registrar PDF layouts.
Each actual layout and version requires sanitized, non-production
characterization material plus deterministic parser tests before enablement.
DBF parsing remains implemented in the existing Edge parser.
Password-protected/encrypted PDFs, image-only/OCR documents, and layout drift
remain explicit failures. This does not limit the separately supported CAMS
password-protected mailback ZIP path described above. Follow-up Issue #111
tracks real PDF layout characterization and support.

The unchanged Edge contract sends the OAuth access token on `/poll` but not on
`/attachments/fetch`. To preserve that contract, the API keeps a bounded,
five-minute, process-local token cache scoped to connector reference, globally
unique mailbox connection ID, and registrar. The Compose API therefore runs
one worker and should remain a single replica. Horizontal scaling requires a
future Edge contract change that securely supplies a per-fetch OAuth context;
tokens must not be placed in URLs or a shared persistent cache. Follow-up Issue
#112 tracks that contract correction.

A process restart, TTL expiry, LRU eviction, or any other cache miss between
poll and fetch fails closed with `mailbox_oauth_context_required`; the Edge
worker must poll again before fetching. Concurrent mailbox connections use
independent cache keys. The same mailbox connection with different registrar
values also uses independent entries. Cache state is never persisted or shared.

Inline attachment identities use a second bounded process-local cache with the
same five-minute TTL. Its keys include connector, mailbox, registrar, message,
and attachment identity, and its values contain only the MIME-part ordinal.
Fetch re-reads the full Gmail message, verifies the issued identity and part,
and then returns the validated bytes. An expired, evicted, restarted, or forged
inline context fails closed and requires another poll. Inline bytes are not
stored in either cache, on disk, or in the database.

CAMS mailback identities use another bounded cache with the same scope and TTL.
It retains only the already-validated download URL. Expiry, eviction, restart,
or a forged identity fails closed; downloaded ZIP and extracted DBF bytes are
never cached or written to local disk.

## Tests

Run unit and mirrored contract tests in a disposable Python environment:

```sh
python -m pip install -r requirements-dev.txt
python -m pytest -m "not integration"
```

With Compose running and the same local tokens exported, run live tests. Plain
HTTP is accepted only for an explicitly opted-in loopback target:

```sh
ALLOW_INSECURE_LOCAL_SMOKE_URL=true \
INGESTION_SUPPORT_BASE_URL=http://127.0.0.1:8080 \
python -m pytest -m integration

deno test --allow-env --allow-net=127.0.0.1:8080 \
  tests/edge_contract_test.ts
```

The Python suite covers mailbox refresh/poll/fetch schemas, bounded Gmail
pagination, detail-fetch concurrency/cancellation, page-fair backlog selection,
identity-scoped OAuth cache
restart/expiry/eviction behavior, redirects, provider failures, timeouts,
malformed/oversized responses, both synthetic PDF layouts,
malformed/oversized PDFs, bearer boundaries,
digest mismatches, ClamAV protocol behavior, clean/infected/unavailable states,
Host-header validation, and non-sensitive readiness. CAMS fixtures additionally
cover WBR2/WBR9 HTML mailback parsing, explicit WBR49 rejection, no-data,
strict URLs, redirects/timeouts/size bounds, encrypted ZIP password failures,
corruption, traversal, duplicates, entry/expansion bounds, DBF extraction, and
the synthetic Gmail-to-URL-to-encrypted-ZIP-to-DBF chain. Provider HTTPS is
mocked for that deterministic contract chain; the synthetic URL is not hosted
at CAMS and is never used by a deployed service. The live Deno test uses the
actual `RemotePdfTextExtractor`, `HttpMalwareScanner`, `CamsParser`, and
`KfintechParser` classes. EICAR appears only in test code.

## Hosted Dev operation (Issue #113)

`compose.hosted.yaml`, `Caddyfile`, `.env.hosted.example`, and the integration
test provide the provider-agnostic Hosted Dev deployment and smoke-test
contract. `HOSTED_DEV_RUNBOOK.md` contains deployment, secret placement,
verification, rollback, and synthetic-data cleanup instructions.

Hosted Dev runs the support API at one worker/replica. Gmail consent and refresh
succeed, and the PR #126 service is deployed, but the current Edge poll still
returns `mailbox_poll_failed`; the service records a generic
`provider_response_too_large` while `/poll` fails closed. This change preserves
the existing generic public response and all byte/count limits while adding one
of three log-only reasons: `gmail_list_response_too_large`,
`gmail_message_detail_response_too_large`, or
`gmail_attachment_count_exceeded`. The next Hosted Dev run can identify which
bounded poll operation failed without logging provider content or metadata.
Production deployment and Production configuration require a separate reviewed
change.

This Issue #113 change also prepares the secure WBR2/WBR9 CAMS URL-mailback
path and Dev-only synthetic fixtures/configuration. It has not changed Hosted
Dev or Production. Validation is intentionally split into three layers:

- automated tests prove the complete synthetic CAMS HTML-to-validated-URL-to-
  encrypted-ZIP-to-DBF contract with mocked provider networking;
- the controlled Hosted Dev smoke uses the generic Gmail attachment path and
  existing synthetic DBF fixture to prove deployed Gmail/Oracle, attachment,
  integrity, ClamAV, Storage, parser, and Dev-persistence infrastructure; and
- a genuine CAMS WBR2/WBR9 `DownloadURL` plus encrypted ZIP remains pending as
  a separate live-provider characterization until an explicitly authorized,
  appropriately sanitized sample is available.

Passing the automated contract and Hosted Dev infrastructure smoke does not
claim that live CAMS characterization has passed. The Dev synthetic sender
remains configuration-only in Dev, and no synthetic host or environment bypass
is added to the CAMS runtime allowlist.
