# NSE B06.3 — SIP, STP and SWP product references

B06.3 adds three explicit document-profile parsers, immutable typed reference rows,
and atomic reference publication on the B06.1 foundation and merged B06.2 runtime
(`d029c80`). All three variants use the existing MASTER_DOWNLOAD worker, event and
dispatcher route. They add no investor registration or schedule mutation.
The implementation is local; provider compatibility and eligibility interpretation
remain uncommissioned.

## Evidence and supported profiles

Sources are retained under `/home/ubuntu/nse-uat-contract`:

| Source | What it establishes |
| --- | --- |
| `docs/NSEMF_API_Details_V1.9.7.pdf`, pp191–192 | Exact MASTER_DOWNLOAD route, SIP/STP/SWP selectors, pipe text success and JSON failure; no column definitions |
| `NSEInvest API Realease_21-05-2025.postman_collection 2.json` | SCH request only, no saved responses or product layouts |
| `analysis/NSE_COHERENT_IMPLEMENTATION_PLAN_V2_001.md`, B06/F02/F03/C035 | Member ownership, separate variant parsing, immutable publication; explicitly references the supporting file-structure PDF |
| `docs/NSE_MF_WebfileStructure.pdf`, pp79–83 | Three separately enumerated product-master layouts |
| `analysis/live_uat/live_uat_results.json`, ordinal 58 | Historical SCH schema only; does not characterize SIP/STP/SWP |

The supporting PDF SHA256 is
`67ee2e34c7cf776a2731e950837bd3aa6f2e6f7e5f521cbdbbce5cc60aae307d`.
The handbook, Postman and coherent-plan fingerprints are recorded in the
[B06.1 foundation](NSE_MASTER_DOWNLOAD_FOUNDATION.md). No UAT call or retained
investor-response import was needed. These profiles use exact documented labels
and ordering; this does **not** claim that current API downloads have been observed
to match the supporting web-export layouts. Any differing header fails closed.

| Profile | Columns | Distinct rules represented |
| --- | --- | --- |
| `NSE_WEB_SIP_V1` | 27 | One-character mode, amount/gap/installment fields, ISIN later in the row; pause flag `N`, three blank pause fields, five blank fillers |
| `NSE_WEB_STP_V1` | 26 | `NSE SCHEME CODE`, `ASTP` fields, separate in/out amounts and registration codes; two-place units |
| `NSE_WEB_SWP_V1` | 21 | Withdrawal amount and unit fields; three-place units |

`nse_systematic_masters.ts` exposes `parseNseSipMaster`, `parseNseStpMaster` and
`parseNseSwpMaster` with distinct immutable types. Shared code handles framing,
lengths, integer syntax and fixed-scale decimal strings only. No SCH schema is
reused. Database parsing independently derives rows from B06.1 evidence, rather
than trusting caller-provided rows, counts, hashes or a validation flag.

Parser version is `nse-systematic-web-v1`. UTF-8, an optional leading BOM, LF or
CRLF, and one optional final newline are supported. Changed/reordered headers,
extra/missing cells, interior blank rows, invalid UTF-8, controls, exact duplicate
rows, invalid numeric syntax and nonblank reserved fields reject the whole file.
Local conservative bounds are 16 MiB, 100,000 rows and 4,096 characters per row.
Text fields must be nonempty within documented lengths without surrounding ASCII
spaces; numeric fields must be unsigned with the documented precision/scale.
These are acceptance restrictions, not claims that the vendor mandates every cell.
Unsupported blanks or pause values need new evidence and a reviewed profile.

## Meaning and lineage

The PDFs do not establish status/mode/registration-code enums, frequency/date-list
syntax, gap units, zero/unlimited conventions, or all pause behavior. These values
retain their source representation. The parser validates their documented types
and sizes without inferring booleans, calendars, min/max business relationships or
eligibility. Unknown code meanings therefore remain **UNINTERPRETED**, while
unknown layouts reject. A failing variant does not change another variant.

`nse_reference.systematic_validations` freezes snapshot, parser/layout, source and
header digests, exact byte count, accepted row count and zero rejected rows.
`sip_products`, `stp_products` and `swp_products` each have their own typed columns
and a composite foreign key through the receipt to the owned B06.1 snapshot.
Every row retains its physical source line (header is line 1) and SHA256 of the
exact line excluding its line ending. B06.1 retains encrypted original bytes,
including BOM/line endings, download identity and member/workspace ownership.

There is no assumed unique vendor business-row key. Multiple rows for one scheme
are retained as candidates; only byte-identical row duplicates reject. NSE scheme
codes remain in the `NSE` namespace. No equality join to `mutual_funds.scheme_code`,
registrar identifiers, SCH rows or investor state is implied. An approved scheme crosswalk (still blocked in B06.2) and separately characterized product semantics are
required before any consumer may authorize an order or systematic registration.

## Publication and reading

The four public RPCs grant execution only to `service_role`; all underlying tables
have RLS, zero policies and no PUBLIC/browser/service table privileges. Private
helpers are not executable by these roles. Definer functions use an empty search
path and resolve/recheck the B06.1 owned, enabled connection and active workspace.
Production remains disabled by the foundation.

1. `validate_nse_systematic_snapshot(workspace, snapshot)` atomically creates the
   immutable receipt and complete typed row set. It is idempotent and does not
   publish. Invalid evidence leaves the staged evidence intact and no receipt.
2. `publish_nse_systematic_snapshot(workspace, snapshot, expected_current_snapshot)`
   locks the member connection, compares the expected current snapshot, validates
   if needed, and appends publication plus audit in one transaction. Audit or
   validation failure preserves the prior publication. Snapshot version and local
   capture time cannot regress. Repeating the same frozen publication request
   returns its receipt; replaying an older publication reports `is_current=false`
   without moving current backward.
3. `get_nse_systematic_current(workspace, connection, variant)` resolves the latest
   publication once. An append-only `systematic_publications` ledger, ordered by
   snapshot version within connection/variant, holds the current-pointer history.
4. `get_nse_systematic_products(workspace, snapshot, scheme_code, after_line, limit)`
   requires a published, explicitly pinned snapshot. Pages stay on that snapshot
   when current changes. It returns typed rows, decimal strings, lineage,
   `authority=REFERENCE_ONLY`, `eligibility=UNINTERPRETED`, and the reason
   `PRODUCT_SEMANTICS_UNCOMMISSIONED`. Empty candidates do not mean investor
   ineligibility. Pagination is by source line with a maximum of 500 rows.

Publication is of structurally validated **reference data**, not of actionable
eligibility. Capture timestamps are local provenance, not vendor effective dates;
no freshness SLA, complete vendor universe, or current provider compatibility is
claimed. Transport completeness still relies on B06.1's conservative framing.
A parseable file shortened before transmission cannot be identified from the
undocumented layout alone.

## Shared B06.2 runtime integration

`createNseSystematicMasterService(client)` accepts an RPC client and a frozen
`{workspaceId, connectionId, snapshotId, fileType}` scope. `validate` loads the
B06.1 manifest and chunks, checks scope/bounds/chunk and body digests, assembles
bytes before decoding, parses, and verifies the database validation receipt.
`publish(scope, expectedCurrentSnapshotId)` uses that validation then invokes the
atomic publisher. It never fetches NSE or automatically retries a request.
Database publication independently validates, including direct RPC callers.

Migration `20261002151000_nse_b06_3_systematic_product_masters.sql` follows both
B06.2 migrations. Its migration-owned registry entries map SIP/STP/SWP to private
`validate_sip_v1`, `validate_stp_v1` and `validate_swp_v1` functions. The registry's
parser profile is `NSE_WEB_<variant>_V1`; the typed receipt retains the common
implementation version `nse-systematic-web-v1` and the same explicit layout ID.
SCH registration and all applied migrations are unchanged; NAV/SET stay disabled.

The existing `prepare_nse_master_download` → outbox → worker →
`finalize_nse_master_download` path captures B06.1 evidence and dispatches validation
in SQL. The adapters call the same `validate_systematic` parser as the service RPC,
retaining its exact digests, types, ownership checks and immutable rows. They catch
only enumerated parser rejections inside a subtransaction, rolling back every
partial typed row and receipt before returning `REJECTED`. The shared runtime
retains the staged snapshot, rejection receipt and completion. A whole-file rejection
reports zero accepted rows; `rejected_rows=0` does not claim a measured bad-row count.
Integrity, ownership, audit and unexpected errors propagate and roll back finalization.

Successful runtime receipts say `STRUCTURE_ONLY_REFERENCE_ONLY` and keep
`publication_gate=BLOCKED`: the worker performs no publication. The explicit service
publisher remains a separate reference-only CAS action. Its receipts, current reads
and product pages explicitly report `REFERENCE_ONLY`, `UNINTERPRETED` and
`PRODUCT_SEMANTICS_UNCOMMISSIONED`. This does not unblock business publication,
SCH crosswalk approval, or investor eligibility. A publication caller must retain
its expected-current value across acknowledgment retries; the worker has no such
value because it never publishes.

The shared worker/adapter implementation, event contract and dispatcher routes need
no changes. The combined Deno manifest retains B06.2 and B06.3 suites. Changes to
schema/semantics require a new parser version and additive migration; existing
receipts, rows and publication history cannot be rewritten.

## Local verification

All fixtures are synthetic. The maintained SQL runner creates a fresh disposable
PostgreSQL 17.6.1.155 container with `--network none`, applies the complete migration
chain, runs `plpgsql_check`, repeats the B06.3 suite, then tests concurrent CAS and
acknowledgment replay. It does not reset a shared Supabase instance. Run:

```bash
bash scripts/test_nse_systematic_sql.sh
bash scripts/test_nse_order_status_sql.sh
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 fmt
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 check
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 test
```

The B06.3 tests cover each profile's types, malformed files, exact lineage,
validation/publication separation, complete rollback, frozen readers, independent
variant pointers, older capture/version rejection, audit atomicity, all API roles,
private ACL/RLS catalogs, and concurrent publication/replay. Statement triggers
fail tests on investor, fund or operation mutation. Direct publication tests also
forbid outbox mutation; runtime integration tests allow only the existing shared
metadata-only job/event contract. The integration suite covers all three variants,
sealed-capture recovery, rejected files with no partial rows, completion-failure
rollback, private plugin ACLs, actual service-role execution, and concurrent
prepare/claim/finalize without automatic publication.

Validation results after reconciliation with `origin/develop` at `d029c80`:

| Check | Result |
| --- | --- |
| Protected NSE fmt/check/test | Pass; 779 tests; 71 fmt/check targets |
| B06.3 SQL/lint/concurrency | Pass; 489 assertions twice; no lint findings |
| Existing NSE SQL suites and concurrency | Pass after the new migration |
| SIP/STP/SWP runtime concurrency | One preparation, claim and validation per variant; no publication |
| All persistent SQL files, each on a fresh restored schema | Baseline 22 pass / 15 fail; candidate 23 pass / same 15 fail |
| Manifest/policy/Compose script tests; dispatcher tests | 22 pass; 55 pass |
| Existing order/payment concurrency | Pass on baseline and candidate |
| Existing registrar/referral concurrency | Same two baseline failures on candidate |
| Documentation, migration history, commit format and shell syntax | Pass |

The broad SQL suite is **not green**. Its 15 unchanged baseline failures are listed
in the [foundation validation notes](NSE_MASTER_DOWNLOAD_FOUNDATION.md#validation-and-remaining-limits).
`SUPABASE_DB_CONTAINER=<disposable-container> sh supabase/tests/run_all.sh` stops at
`issue_114_service_role_protected_table_select:workspaces` on both baseline and
candidate. Separate fresh-schema runs establish that no prior pass regressed.
Registrar concurrency reports `PAN encryption configuration is unavailable` on
both versions; referral concurrency reports `referral_profile_not_resolved` on
both versions. No existing ACL, fixture, financial logic or CI requirement was
changed to conceal those failures.

Reconciliation receipts are `/tmp/b063-reconciled-{fmt,check,deno}.log`,
`/tmp/b063-reconciled-{systematic-sql,all-nse-sql}.log`,
`/tmp/b063-reconciled-{baseline,candidate}-all-db.log`,
`/tmp/b063-reconciled-{baseline,candidate}-run-all.log`,
`/tmp/b063-reconciled-extra-concurrency.log` and
`/tmp/b063-reconciled-validation-comparison.json`. Each broad SQL file ran on a
fresh restored schema. The baseline was an archive of `origin/develop` at
`d029c80`, and every baseline migration remains byte-for-byte unchanged.
The only test-harness correction during integration removed a redundant attempt
to drop a session-temporary fixture trigger before the new runtime races.
No hosted mutation, NSE UAT, live-container/systemd change, push or PR was performed.
