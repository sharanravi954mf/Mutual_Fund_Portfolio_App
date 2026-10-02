# NSE B06.1 — member reference foundation

B06.1 adds member-owned capture and immutable, unvalidated reference versions.
It does not implement any variant parser, business publication, deployed worker,
browser command or provider call. B06.2, B06.3 and B06.4 can branch independently
from this candidate and build on the interfaces below.

B06.2 now extends these interfaces with a [shared worker and staged SCH parser](NSE_MASTER_DOWNLOAD_SCH.md). The foundation contract and historical validation below remain unchanged.

## Authority and baseline

Fresh `git fetch origin develop` on 2026-10-02 resolved to
`75a42b4efd703c23cbb870199c8e79d4930d7678`. Canonical develop was clean and
remains untouched. Worktree: `/home/ubuntu/moneybowl-worktrees/nse-b06-1-master-foundation-local`;
branch: `feature/nse-b06-1-master-foundation-local`.

Authority, in order, under `/home/ubuntu/nse-uat-contract`:

- `docs/NSEMF_API_Details_V1.9.7.pdf`, pp191–192: POST
  `/nsemfdesk/api/v2/reports/MASTER_DOWNLOAD`, exactly `{"file_type":"SCH"}`
  with six allowed values, pipe-separated text on success, JSON on failure;
  NAV has no header. PDF SHA256:
  `5c3c819d788e40ba28f8d2eb3a6b2faabc3a39c5e9bc658fa034cf4c26cc576a`.
- `NSEInvest API Realease_21-05-2025.postman_collection 2.json`: recursive
  inspection confirms the SCH request and exact route; it supplies no six-variant
  parsing proof. SHA256:
  `9db36cfb4bfb67b4481c9d8b462b0c534286f417e98067cd769b04e6f224f6fd`.
- `analysis/NSE_COHERENT_IMPLEMENTATION_PLAN_V2_001.md` and `.json`: B06,
  F02/F03, C035 and T004–T007; historical SCH size 4,057,995 bytes.
  MD SHA256 `e61c22ce66ab42418486e81a02f89572eff175600792bc7c59ec112ac6423f16`;
  JSON SHA256 `06f5680a69054900c2f7f9c46ff5100172484e6e78d554638facd090e6d794b7`.
- Current MoneyBowl migrations, NSE workers, registrar parser/persistence and NAV
  updater. The existing NAV smoke function supplies no durable B06 evidence.

Before source edits, protected Deno fmt/check and all **620 tests** passed;
the existing disposable NSE SQL runner passed its complete migration reset,
UCC/dispatcher regressions, two passes of all report/facade suites and frontend
concurrency. Documentation and 22 script tests passed. The broader `run_all.sh`
stopped on `issue_114_service_role_protected_table_select:workspaces`.
The timestamped pre-edit receipt is `/tmp/b061-baseline-before-edits.json`;
its sole untracked entry is Python-generated `scripts/__pycache__`, removed later.

## Member cardinality and ownership

The private `nse_reference.connections` registry binds a workspace to a named NSE
member, environment, exact HTTPS base URL and non-secret `NSE_ENV_V1` slot.
The existing worker runtime contains one protected `NSE_*` credential bundle per
environment. Therefore the database permits **one binding per slot/environment**,
one member per workspace/environment, and one owner per member/environment.
It refuses shared ownership and competing members for the same runtime slot.
This is an explicit supported cardinality, not an inference from investor UCCs.
Future multiple-member operation requires separately commissioned secret slots
and a reviewed extension; no arbitrary slot names or automatic backfill exist.

Only database-owner commissioning can insert a connection or toggle `enabled`;
identity and ownership cannot change. The migration creates no connection rows.
Changes are audited transactionally. Every service RPC loads and locks the owned
connection, checks active workspace/enabled connection and cardinality again.
Begin compares the runtime member, environment and URL with that binding.
PRODUCTION is representable but capture is explicitly disabled in this slice.

Provider credentials remain in the existing protected environment consumed by
`loadNseConfig`/`createNseBasicAuthorization`. The database has no login, password,
API-key, secret or arbitrary metadata column. Authentication headers, cookies,
filenames, response diagnostics and provider error strings are never metadata.
The only request body is the exact generated `file_type` JSON.

This separate private model fits the current architecture better than making
`integration_operations.integration_account_id` nullable or changing the meaning
of `integration_accounts`: both retain their mandatory investor/UCC invariants.
There is no dummy investor, account or generic investor observation.

## Exact evidence and limits

`downloads` freezes request bytes/hash, route, method, contract, connection,
variant and call ID. A process-local capture token fences acknowledgement replay:
the same token can recover a begin acknowledgement; a new invocation using that
call ID cannot send again. A crash can leave an unsealed attempt, never a usable
snapshot; later orchestration must abandon/seal it as failed and use a new call
ID for another authorized read. No automatic HTTP retry exists here.

`evidence_chunks` stores contiguous, independently SHA256-checked chunks encrypted
with AES256 through `pgp_sym_encrypt_bytea` and the existing Vault-backed
`integration_payload_encryption_key_v1`. The exact HTTP entity bytes survive
UTF-8 multibyte boundaries, BOM, CRLF and final-newline differences. Encryption
uses bytea rather than decoding/re-encoding text. This is entity-body evidence,
not TLS/wire framing or complete HTTP-header evidence.

The separate MASTER_DOWNLOAD cap is **16 MiB**, with at most **64 chunks of
256 KiB**. Each base64 RPC argument is at most 349,528 characters. This exceeds
the measured SCH size without changing the shared client or any B01–B05 limit.
The reader bounds bytes as they arrive, cancels oversize streams, and applies a
120-second transport deadline. It requests identity encoding and rejects redirects.
Peak application body storage and database finalization remain bounded; WebCrypto
requires an additional whole-body buffer for the digest. This is deliberately a
bounded multi-megabyte design, not unlimited streaming or an invented vendor limit.

Complete capture requires valid Content-Length, identity encoding, EOF, exact
length equality and a matching independently recomputed whole-body SHA256 in SQL.
Missing/malformed length or compressed responses are `UNVERIFIABLE` and cannot
stage. This conservative local policy may reject legitimate chunked vendor
responses; actual transport characterization is required before relaxing it.
Known short/long streams are `TRUNCATED`; oversize/transport failures are separate.
Already acknowledged prefixes may be retained with their own captured-byte hash;
only `COMPLETE` has a full response hash. No prefix masquerades as a full file.
A permanent persistence failure leaves an unsealed, unstageable attempt.

Postgres locks serialize append/seal operations. Retried identical chunks and
results are idempotent; changed bytes, gaps, invalid hashes and post-seal additions
reject. Decryption verifies each chunk again. Encrypted chunks and their manifest
share the existing database transaction/security boundary, avoiding a new object
store, cross-system finalization and blob-retention machinery for these sizes.

## Staging and future atomic publication

`results.COMPLETE` means complete transport evidence, not provider/business success.
Staging requires complete evidence, HTTP 200, text/plain or octet-stream, valid
UTF-8 and a pipe-bearing file candidate. Empty bodies, JSON/HTML error bodies,
non-UTF-8 bytes and unsuccessful HTTP responses cannot stage. This minimal file
screen does not establish a valid row, schema, record count or semantic completeness.
A vendor file cleanly truncated before transmission cannot be proved complete by
Content-Length; variant validation and commissioning remain publication gates.

`snapshots` is append-only: workspace, connection, typed variant, evidence download,
monotonic version and same-scope predecessor. Connection locking serializes version
allocation; staging the same evidence twice returns the same version. A new download
can create a new version even when its content hash repeats. Every version remains
`STAGED_UNVALIDATED`. There is no current/publication pointer or publication RPC.

| Variant | Owning batch | Independent future parser/publication |
| --- | --- | --- |
| SCH | B06.2 | Scheme catalogue and explicit code crosswalk |
| SIP | B06.3 | SIP eligibility/rules |
| STP | B06.3 | STP eligibility/rules |
| SWP | B06.3 | SWP eligibility/rules |
| NAV | B06.4 | Headerless NAV observations with valuation-date provenance |
| SET | B06.4 | Settlement calendar; layout still uncharacterized |

Each child implementation should add its own immutable typed rows and validation
receipt keyed by `(snapshot_id, parser_version)`, including row counts, rejects,
schema/version identity and source digest. Publication must atomically insert a
validated receipt and change only that variant's current pointer in the same
transaction, with an expected-prior-version check. Readers must resolve that
pointer once per operation. Generic success flags or raw staged versions are not
eligibility, NAV or calendar authorities. No shared generic business-row parser
or publisher has been introduced.

Service-only RPCs are `begin_nse_master_download`, `append_nse_master_chunk`,
`finish_nse_master_download`, `read_nse_master_chunk`, `stage_nse_reference_snapshot`
and `get_nse_reference_snapshot`. The latter returns the durable parser manifest
including evidence ID, byte count, full digest and chunk count. The shared
`captureNseMasterDownload` and `createNseMasterEvidenceStore` implement the transport
and persistence seam; they are not deployed or called by an existing endpoint.
Later workers should use the commissioned outbox dispatcher and its existing
reconciliation mechanism, adding ordinary routes only when those workers exist.

All five private tables have RLS and zero browser/service table grants or policies.
All private helpers deny PUBLIC/anon/authenticated/service_role execution; public
RPCs grant only service_role and use empty definer search paths. Composite foreign
keys enforce ownership through download, chunk, result, snapshot and predecessor.
All evidence/version changes and deletes reject. Browser personas, including
Platform Admin and operations membership, have no reference access in B06.1.

## Existing source and crosswalk boundaries

The actual `mutual_funds` model has a globally unique `scheme_code`, names/AMC,
`current_nav` and `nav_date`. CAMS parser aliases include `SCHEME_CD`, `PRODCODE`,
`PRODUCT`; KFin includes `FUNDCODE`, `SCHEME`, `SCH_CODE`. Registrar persistence
maps those values to `mutual_funds.scheme_code`, enforces AMC consistency and links
transactions/folios/holdings. These identifiers are not established NSE codes.

The current `daily-nav-updater` fetches `api.mfapi.in/mf/<scheme_code>` and directly
updates current NAV/date before portfolio recalculation. General architecture prose
mentions AMFI/historical NAV models, but that does not establish such a provenance
model in the current implementation. B06.1 writes none of these tables.

B06.2 must introduce an explicit source-namespace crosswalk from immutable NSE
scheme identity to MoneyBowl fund ID, preserving AMC, ISIN/plan/option evidence,
provenance, effective version and ambiguity/review outcome. Name/code equality
alone is insufficient. B06.3 must retain product-master eligibility separately
from SCH and from investor registration observations. B06.4 must stage dated NAV
observations by source and define precedence, freshness and approved crosswalks
before valuations can consume them; SET needs its own characterized calendar
schema. None of these future source decisions is silently made by this foundation.

## Validation and remaining limits

All tests used synthetic fixtures and disposable PostgreSQL 17.6.1.155 containers
with `--network none`. The full migration chain was applied from scratch; no
shared Supabase reset, hosted database or live Docker/systemd service was changed.
The generic issue-33 HTTP gateway script requires a running local Supabase API
and was not invoked against shared infrastructure. SQL/security validation uses
actual roles and `plpgsql_check`, including every new function, in the disposable
container. No new lint error or warning was found.

| Check | Base | Candidate |
| --- | --- | --- |
| Protected NSE manifest fmt/check/test | 620 tests pass | 645 tests pass (25 new) |
| Existing NSE SQL suites | Pass | Pass, plus 177 B06.1 assertions twice and version concurrency |
| All persistent database SQL files, each on a fresh restored schema | 20 pass / 15 fail | 21 pass / same 15 fail |
| Existing order-claim/payment concurrency | Both pass | Both pass |
| Existing CAMS/referral concurrency | Both fail | Same failures |
| Manifest/policy/Compose script tests | 22 pass | 22 pass |
| Dispatcher pytest | Unchanged source | 54 pass |
| Documentation, migration-history, shell syntax, diff whitespace | Pass where run | Pass |

The broad database suite is **not green**. Its pre-existing failures are:

- `issue_114_workspace_authorization_rpc_test.sql`: protected workspaces SELECT ACL.
- `issue_28_cancel_order_contract_test.sql`: owner cancellation assertion.
- `issue_29_order_request_audit_contract_test.sql`, `issue_30_order_requests_rls_test.sql`,
  `issue_89_sell_switch_order_intent_test.sql`, `sprint_6_1_hardening_test.sql`:
  timestamp interpreted as integer in existing fixtures/functions.
- `issue_32_cams_kfintech_ingestion_test.sql`, `issue_32_integration_hardening_test.sql`,
  `pan_verification_expired_token.sql`, CAMS concurrency: PAN key unavailable.
- `issue_39_investor_subscription_lifecycle_test.sql`: entitlement visibility.
- The four `issue_40_referral_*` SQL tests and referral concurrency:
  `referral_profile_not_resolved`.
- `sprint_6_1_final_hardening_test.sql`: profile resolution mapping assertion.

No existing pass becomes a failure. These are baseline failures in this local
setup, not waived B06.1 failures; no unrelated fixture, ACL or financial logic
was changed to conceal them. The pre-edit `run_all.sh` stops at the first failure;
`/tmp/b061-baseline-fresh-db.sh` and `/tmp/b061-final-fresh-db.sh` instead restore
an identical pristine post-migration dump before each SQL test and record all
outcomes. Their corresponding `.log` files preserve the exact errors. Additional
logs are `/tmp/b061-{sql,deno,fmt,check,python,dispatcher,docs,migrations}.log`.

Reproduce the maintained NSE check with the protected
`/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1`
commands `fmt`, `check`, `test`, followed by
`bash scripts/test_nse_order_status_sql.sh`. The new suite covers member/workspace
cardinality and ownership, all six types, cross-workspace composite foreign keys,
credential exclusion, oversize/truncation/corruption, immutable evidence/versions,
acknowledgement replay, API-role ACLs and concurrent version allocation.

There is no unresolved B06.1 implementation blocker. Later commissioning still
requires an explicitly owned enabled member binding, observed transport framing,
separate variant layout/semantic fixtures, independent parser validation and
source/publication decisions. SET remains uncharacterized. No UAT call was needed
or made, and no push, PR, merge or deployment occurred.
