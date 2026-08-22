# Money Bowl ingestion-support

`ingestion-support` is the provider-host-agnostic external service stack used by
the existing `cams-kfintech-ingestion` Edge Function. It keeps the Edge worker,
database, Storage, and Auth contracts unchanged while providing three logically
separate capabilities from one small deployment:

- Gmail OAuth mailbox connector (`/oauth/refresh`, `/poll`, and
  `/attachments/fetch`);
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
  |-- PDF bearer -----> FastAPI --> bounded pypdf memory extraction
  `-- malware bearer -> FastAPI --> private Docker network --> clamd INSTREAM
```

The API runs as a non-root, read-only container with no Linux capabilities.
`clamd` is reachable only on the private Compose network; port 3310 is never
published. The API port is bound to `127.0.0.1` for local development. A future
host must terminate HTTPS in front of it and must not expose plain HTTP.

## Edge-owned endpoint contract

| Edge setting | Value shape | Support endpoint |
| :--- | :--- | :--- |
| `MAILBOX_CONNECTOR_URL` | Base URL, for example `https://ingestion.example.test` | Worker appends `/oauth/refresh`, `/poll`, `/attachments/fetch` |
| `PDF_TEXT_EXTRACTOR_URL` | Full URL | `https://ingestion.example.test/pdf/extract` |
| `MALWARE_SCANNER_URL` | Full URL | `https://ingestion.example.test/malware/scan` |

All POST routes require their own exact `Authorization: Bearer ...` token. The
mailbox poll also requires `X-Mailbox-OAuth-Token`; PDF extraction requires
`X-Registrar`, `X-Statement-Format`, and `X-File-Name`; malware scanning
requires `X-Content-SHA256` and `X-File-Name`. `/health` and `/ready` are
unauthenticated and return status only. Readiness fails while `clamd` or its
signature database is unavailable.

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
3. Add a Google OAuth client ID and secret for a development-only Gmail account.
4. Start the stack:

   ```sh
   docker compose up --build -d
   docker compose ps
   curl --fail http://127.0.0.1:8080/health
   curl --fail http://127.0.0.1:8080/ready
   ```

5. Stop it without deleting the ClamAV signature volume:

   ```sh
   docker compose down
   ```

ClamAV loads a large signature database. Allocate at least 4 GB RAM to Docker
for reliable startup. Initial startup can take several minutes while signatures
download and load. The Compose file pins the API runtime/dependencies and
ClamAV 1.5.4; signature updates remain in the `clamav_db` volume.

## Gmail OAuth setup

The initial provider is Gmail behind the `MailboxProvider` interface. Manual
hosted setup is deliberately deferred until after review and merge:

1. Create a Google Cloud project for the Dev integration and enable Gmail API.
2. Configure an OAuth consent screen and a server-side OAuth client.
3. Request only the Gmail read-only scope required by the connector.
4. Obtain offline consent for a synthetic/non-production mailbox so Money Bowl
   receives a refresh token.
5. Store the Google client secret only in the support-service host and store the
   mailbox OAuth credential only through the existing encrypted Money Bowl
   mailbox-credential flow.
6. Use connector reference `gmail:me` (or `gmail:<mailbox-address>`). Provider
   origins are fixed configuration, never request-controlled URLs.

No `IMAP_USER`, `IMAP_PASSWORD`, Google app password, Supabase service-role key,
or `RTA_DECRYPTION_PASSWORD` belongs in this service. The first authorization
grant is a manual administrative step; automated tests use mocks only.

Mailbox polling uses the Gmail query
`has:attachment {filename:pdf filename:dbf}` to reduce unrelated attachment
traffic without guessing registrar sender addresses. Each poll inspects at most
`MAX_MAILBOX_PAGES_PER_POLL` pages (default `4`) and
`MAX_MAILBOX_CANDIDATES_PER_POLL` message candidates (default `100`). Gmail
page tokens must be non-empty, bounded printable ASCII and must not repeat.
Messages with actual attachments are selected page-fairly across the inspected
pages, up to the existing `MAX_MAILBOX_MESSAGES` output limit (default `25`).
The Edge worker remains the authority for the configured sender allowlist.

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
Password-protected/encrypted statements, image-only/OCR documents, and layout
drift remain explicit failures. Follow-up Issue #111 tracks real layout
characterization and support.

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

## Tests

Run unit and mirrored contract tests in a disposable Python environment:

```sh
python -m pip install -r requirements-dev.txt
python -m pytest -m "not integration"
```

With Compose running and the same local tokens exported, run live tests:

```sh
INGESTION_SUPPORT_BASE_URL=http://127.0.0.1:8080 \
python -m pytest -m integration

deno test --allow-env --allow-net=127.0.0.1:8080 \
  tests/edge_contract_test.ts
```

The Python suite covers mailbox refresh/poll/fetch schemas, bounded Gmail
pagination and page-fair backlog selection, identity-scoped OAuth cache
restart/expiry/eviction behavior, redirects, provider failures, timeouts,
malformed/oversized responses, both synthetic PDF layouts,
malformed/oversized PDFs, bearer boundaries,
digest mismatches, ClamAV protocol behavior, clean/infected/unavailable states,
Host-header validation, and non-sensitive readiness. The live Deno test uses
the actual `RemotePdfTextExtractor`, `HttpMalwareScanner`, `CamsParser`, and
`KfintechParser` classes. EICAR appears only in test code.

## Hosted Dev follow-up (not performed by Issue #109)

After merge, provision a small HTTPS-capable VPS/container host with Docker,
4 GB or more RAM, persistent space for signature databases, restricted inbound
firewall rules, monitoring, backups for configuration only, and TLS renewal.
Create host-only values for the three support-service bearer tokens and Gmail
OAuth client credentials. Then configure the corresponding Dev-only Edge
Function URL/token values outside Git and perform a controlled smoke test with
synthetic data. Do not copy Production mail, documents, OAuth credentials, or
secrets. Production deployment and Production configuration require a separate
reviewed change.
