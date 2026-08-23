# Project Control Center (PROJECT_STATE)
Target Repository Path: docs/PROJECT_STATE.md

## Project Overview
- **Project Name**: Money Bowl
- **Repository Name**: Mutual_Fund_Portfolio_App
- **Current Mission**: Provide a premium, responsive Mutual Fund Portfolio Tracker supporting relationship-isolated portfolios, advisor qualifications, AMFI factsheets, dual subscriptions, Family Access, referrals, educational AI, and immutable auditing across Web and Mobile platforms.
- **Current Vision**: Securely track investor mutual fund portfolios, compile transaction histories, analyze annualized returns (XIRR), manage advisor ingestion/qualification reviews, and coordinate family delegation and subscriber billing workflows under strict compliance constraints.
- **Current Phase**: Phase 3 (Documentation Platform and Operational Systems).
- **Architecture Status**: Canonical v2.1.0 baseline approved
- **Documentation Status**: Aligned and certified
- **Application Status**: Pre-alpha implementation in progress
- **Application Implementation**: In Progress
- **Current Release Target**: v1.2.0-alpha
- **Current released application version**: v1.1.0-alpha
- **Last Updated**: 2026-08-22

---

## Canonical Project Documents Notice
The following five documents are the current and authoritative records for this project:
- [PROJECT_STATE](PROJECT_STATE.md)
- [CHANGELOG](CHANGELOG.md)
- [BRD](business/BRD.md)
- [System Architecture](architecture/SYSTEM_ARCHITECTURE.md)
- [Sprint 6.1](sprints/Sprint-6.1.md)

All other Markdown files are stale and must not be used for project status or architecture decisions.

---

## Current Status
- **Current Epic**: Core Platform Implementation
- **Current Milestone**: User Management & Workspace Foundation Implemented
- **Current Sprint**: Sprint 6.1 — Order Execution Engine, Subscriptions & Schema Extensions
- **Active Baselines**: BRD v1.3.0 | SYSTEM_ARCHITECTURE v2.1.0
- **Sprint 6.1 Status**: Ready to Start
- **Architecture Completion**: Complete
- **Release Readiness**: Not Ready
- **Documentation Certification Status**: Complete
- **Current Development Focus**: Execute Sprint 6.1 issues sequentially (including audit-schema hardening, Family Access lifecycle RPCs, Platform Admin support overrides with step-up verification, outbox event claiming and uniqueness validations, investor/distributor subscriptions, and pgTAP integration verification).

---

## Active Branch Strategy
- **`main`**: Production stable track. Direct commits are forbidden. Merges occur via pull requests from `release/*` or `hotfix/*` branches.
- **`develop`**: Integration branch for pre-release testing.
- **`release/*`**: Pre-release verification tracks. Squash-merged to `main` and `develop` after Go/No-Go sign-off.
- **`feature/*`**: Standalone feature branches (e.g. `feature/analytics`). Merged to `develop` via PRs after CI verification.
- **`bugfix/*`**: Non-critical bug remediation.
- **`hotfix/*`**: Emergency production fixes. Direct merges to `main` and `develop` after architect approvals.

---

## Hosted Supabase Dev Backend Contract (Issue #107)

The hosted Supabase Dev project is deployed from `develop` through the
GitHub integration. Feature branches validate against local Supabase only;
they must not be linked to or manually deploy to hosted Dev or Production.

### Edge Function deployment and authorization

| Function | Deploy to Dev | `verify_jwt` | Application and authorization evidence |
| :--- | :---: | :---: | :--- |
| `cams-kfintech-ingestion` | Yes | `false` | Current ingestion architecture and admin workflow. The gateway `Authorization` bearer is `MONEYBOWL_INTERNAL_INGESTION_TOKEN`; the initiating user JWT is independently validated from `x-user-authorization` before active advisor/admin workspace membership is checked. |
| `daily-nav-updater` | Yes | `false` | Invoked from the current admin dashboard. Shared authorization validates the caller JWT with Supabase Auth and requires the application profile role `admin`. Uses service-role database access and the external `api.mfapi.in` feed. |
| `order-auto-approval-worker` | Yes | `false` | Current event-outbox worker. It requires `ORDER_AUTO_APPROVAL_WORKER_TOKEN` and then uses service-role RPCs to claim events and apply or record decisions. |
| `platform-admin-override` | Yes | `false` | Current Sprint 6.1 audited override endpoint. It validates the caller JWT, executes the attempt RPC as that user, and restricts privileged action/finalization RPCs to the service-role client. |
| `sign-stamp-invoice` | Yes | `false` | Invoked by the current invoice and fund-search workflows. Proxy requests require a JWT validated through Supabase Auth; signing/decryption also requires the `is_admin` RPC authorization check. |
| `update-excel-metadata` | No | N/A | Obsolete deployment artifact. Commit `5aa14f8` replaced its Edge invocation with `lib/utils/excel_updater.dart` client-side processing to avoid serverless resource limits, and current application code has no invocation. If restored, its handler must retain its `requireAdvisor` application-code authorization. |

All deployed functions intentionally disable the platform-level `verify_jwt`
check, but they are not unauthenticated or public. Authentication remains
fail-closed in application code: the ingestion and worker endpoints require
custom internal bearer tokens, while the three user-facing endpoints validate
the caller JWT through Supabase Auth and then enforce their application or
audited database authorization. This avoids coupling deployment to Supabase's
legacy JWT gateway verification model and remains compatible with a future move
to publishable and secret API keys.

Migrating `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` consumers to
`SUPABASE_PUBLISHABLE_KEYS` and `SUPABASE_SECRET_KEYS` is a separate future
follow-up. Issue #107 does not change the function clients or key model.

The historical `deploy_ingestion.sh` manual deployment helper is retired and
now exits without changing anything. It is not the canonical Dev deployment
path and must not be used to infer hosted configuration; the audited
per-function settings above are authoritative. Direct IMAP credentials and
manual function deployment are intentionally unsupported.

### External ingestion support service (Issue #109)

`services/ingestion-support/` implements the external runtime expected by the
unchanged `cams-kfintech-ingestion` Edge Function as one provider-host-agnostic
Docker Compose stack:

- `MAILBOX_CONNECTOR_URL` is a base URL. The worker appends authenticated
  `POST /oauth/refresh`, `POST /poll`, and `POST /attachments/fetch` routes.
  The initial provider uses Gmail OAuth/Gmail API behind an adapter; it does not
  accept direct IMAP usernames, passwords, or app passwords. Polling filters for
  PDF/DBF attachments without guessing sender addresses, follows bounded Gmail
  pagination (default 4 pages/100 inspected candidates), rejects malformed or
  repeated page tokens, and page-fairly returns at most 25 messages. The Edge
  worker continues to enforce the canonical sender allowlist.
- `PDF_TEXT_EXTRACTOR_URL` is the full authenticated
  `POST /pdf/extract` URL. It provides bounded, zero-disk PDF extraction
  infrastructure plus a deterministic synthetic/characterization contract,
  without OCR or an external AI/document service. No sanitized representative
  CAMS/KFintech CAS statement PDF exists in the repository, so no live registrar
  PDF layout is enabled. DBF parsing remains in the existing Edge parser. Issue
  #111 tracks sanitized live-layout characterization and support.
- `MALWARE_SCANNER_URL` is the full authenticated
  `POST /malware/scan` URL. It verifies `X-Content-SHA256` and streams the same
  raw bytes to a private ClamAV daemon using `INSTREAM`; clean, infected, and
  unavailable results remain distinct.

The three capabilities require separate service bearer tokens and do not log
tokens, attachment content, investor data, or provider responses. Health and
readiness return status only, and readiness fails when ClamAV/signatures are
unavailable. The API is bound to localhost in the local Compose configuration;
hosted Dev requires an HTTPS ingress, an explicit host allowlist, and secrets
stored outside Git.

The unchanged Edge poll request supplies its OAuth access token, whereas the
attachment-fetch request supplies only provider identities. The initial stack
therefore uses a bounded five-minute, process-local token bridge scoped to the
connector reference, globally unique mailbox connection ID, and registrar. It
runs one API worker/replica. Horizontal scaling requires a future reviewed Edge
contract change; OAuth tokens must not be placed in URLs or persisted by this
service. Process restart, TTL expiry, LRU eviction, or cache miss fails closed
with `mailbox_oauth_context_required` and requires another poll. Concurrent
mailboxes and different registrar values have isolated cache entries. Issue
#112 tracks removal of the process-local dependency.

Issue #109 performs local implementation and validation only. It does not
deploy the stack, configure hosted Dev/Production values, link Supabase, change
database migrations, or copy real mailbox/document data. Gmail authorization,
HTTPS host provisioning, Dev-only Edge secret configuration, and a synthetic
hosted smoke test remain post-merge operational steps. See
`services/ingestion-support/README.md` and `THREAT_REVIEW.md` for the exact
runtime, tests, limitations, and minimum 4 GB host guidance.

### Hosted Dev ingestion-support operations (Issue #113)

The repository now includes a provider-neutral Hosted Dev Compose override,
pinned Caddy TLS ingress, placeholder-only host environment template, HTTPS-safe
endpoint smoke test, and an operational deployment/rollback runbook. The
override removes the API port mapping, publishes only Caddy on 80/443, preserves
the private persistent ClamAV signature volume, and fixes the API at one Uvicorn
worker and one Compose replica until Issue #112 changes the Edge contract.

No approved Dev host, DNS name, host credentials, or host secrets are available
in the current implementation environment. Consequently the service is not
live, the six Hosted Dev support URL/token values have not been configured, and
no Hosted Dev E2E smoke test has been claimed. Production remains untouched.

The architecture can refresh and replace an existing encrypted Gmail OAuth
credential but cannot securely obtain and write the first refresh token: the
consent redirect, callback/state validation, authorization-code exchange, and
authorized encrypted first-write path are absent. Issue #114 tracks that
separate blocker. It must request only Gmail read-only offline access and must
not use plaintext tokens, passwords, app passwords, or manual database writes.
See `services/ingestion-support/HOSTED_DEV_RUNBOOK.md` for the exact prerequisite,
secret-boundary, verification, rollback, and synthetic cleanup procedure.

### Edge Function environment inventory

Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY` to hosted Edge Functions. They are platform values,
not custom application secrets, and the service-role key must never be exposed
to a client.

`cams-kfintech-ingestion` custom values:

- Required: `MONEYBOWL_INTERNAL_INGESTION_TOKEN`,
  `MAILBOX_OAUTH_AES256_GCM_KEY_B64`, `MAILBOX_CONNECTOR_URL`,
  `MAILBOX_CONNECTOR_SERVICE_TOKEN`, `PDF_TEXT_EXTRACTOR_URL`,
  `PDF_TEXT_EXTRACTOR_SERVICE_TOKEN`, `MALWARE_SCANNER_URL`, and
  `MALWARE_SCANNER_SERVICE_TOKEN`.
- Optional/defaulted: `MAILBOX_CONNECTOR_TIMEOUT_MS`,
  `MAILBOX_CONNECTOR_MAX_RESPONSE_BYTES`,
  `MAILBOX_ATTACHMENT_DOWNLOAD_TIMEOUT_MS`, `PDF_TEXT_EXTRACTOR_TIMEOUT_MS`,
  `PDF_TEXT_EXTRACTOR_MAX_RESPONSE_BYTES`, `MALWARE_SCANNER_TIMEOUT_MS`, and
  `MALWARE_SCANNER_MAX_RESPONSE_BYTES`.
- Optional, defaulting to secure behavior: `ALLOW_INSECURE_CONNECTOR_URL`,
  `ALLOW_INSECURE_PDF_TEXT_EXTRACTOR_URL`, and
  `ALLOW_INSECURE_MALWARE_SCANNER_URL`. These must remain unset or `false` in
  hosted Dev; `true` is accepted only for explicit localhost testing.

`order-auto-approval-worker` custom values:

- Required: `ORDER_AUTO_APPROVAL_WORKER_TOKEN`.
- Optional/defaulted: `ORDER_AUTO_APPROVAL_MAX_ATTEMPTS` and
  `ORDER_AUTO_APPROVAL_LEASE_SECONDS`.

`sign-stamp-invoice` custom values:

- Operationally required for a secure Dev deployment, but defaulted by the
  implementation: `RTA_DECRYPTION_PASSWORD`. When it is absent, the current
  handler uses an insecure hard-coded fallback; this issue records but does not
  redesign that unrelated behavior.

`daily-nav-updater` and `platform-admin-override` use no custom environment
variables beyond Supabase-provided project values. The intentionally omitted
`update-excel-metadata` function also declares no custom environment variable,
but contains a separate hard-coded archive-password fallback that remains
outside Issue #107.

Only secret names belong in source control. Dev values must be configured in
the hosted project's Edge Function secret store after review; Production values
must not be copied.

### Storage provisioning

`ingested-documents` remains migration-managed by
`20260802000001_issue_32_cams_kfintech_ingestion.sql`. That migration
idempotently enforces a private bucket, a 20 MiB-minus-one-byte object limit,
and the approved PDF/DBF MIME allowlist. The Issue #32 database tests also
assert the private bucket contract and absence of browser-facing object
policies. Declaring the same bucket in `config.toml` would create a competing
provisioning path, so Issue #107 intentionally leaves Storage configuration
unchanged. No hosted documents or Production data are copied.

### Hosted Dev Auth configuration

The repository `config.toml` captures local Auth defaults only. The GitHub
integration deploys migrations, declared Edge Functions, and declared Storage
buckets; hosted API and Auth settings are not applied by default. Before Dev
application testing, separately review and configure:

- the Dev site URL and exact redirect allowlist;
- email/password signup, confirmation, recovery, template, rate-limit, and SMTP
  behavior;
- phone/password signup and an SMS provider if phone authentication is enabled;
- OAuth providers and callback URLs (none are enabled by current repository
  configuration or used by current application code);
- CAPTCHA/bot protection (not declared in the repository); and
- JWT/session policy consistency with the application.

The current Flutter client signs in with a password using either email or phone.
No hosted Auth credential belongs in Git.

### Scheduling and background triggers

- No migration enables `pg_cron`, and the only `cron.schedule`/`net.http_post`
  example is commented out in the historical ingestion migration.
- No GitHub Actions workflow has a `schedule` trigger, and no database webhook
  or active Edge Function scheduler is defined.
- `daily-nav-updater` is currently invoked manually from the admin dashboard;
  automated daily scheduling remains unimplemented.
- `cams-kfintech-ingestion` has a manual admin-dashboard invocation, but that
  call does not supply the hardened internal-token, user-token, workspace,
  mailbox, registrar, and correlation contract. It is not a functional
  production scheduler and remains a follow-up outside this parity change.
- Order creation writes `order.created` rows to `event_outbox`, but no repository
  dispatcher currently invokes `order-auto-approval-worker`; the worker polls
  and claims an event only when invoked.
