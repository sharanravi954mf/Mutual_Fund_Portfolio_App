# NSE B06.3 — SIP, STP and SWP product references

B06.3 adds three explicit document-profile parsers, immutable typed reference rows,
and atomic reference publication on the merged B06.1 foundation (`6721741`). It
has no worker, event, dispatcher route, investor registration or schedule mutation.
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
registrar identifiers, SCH rows or investor state is implied. B06.2's eventual
approved scheme crosswalk and separately characterized product semantics are
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

## B06.2 integration seam

`createNseSystematicMasterService(client)` accepts an RPC client and a frozen
`{workspaceId, connectionId, snapshotId, fileType}` scope. `validate` loads the
B06.1 manifest and chunks, checks scope/bounds/chunk and body digests, assembles
bytes before decoding, parses, and verifies the database validation receipt.
`publish(scope, expectedCurrentSnapshotId)` uses that validation then invokes the
atomic publisher. It never fetches NSE or automatically retries a request.
Database publication independently validates, including direct RPC callers.

After B06.2 merges, its shared runtime can stage B06.1 evidence and call this seam
for the selected systematic variant. It must retain the expected-current value
across acknowledgment retries. No B06.2-owned runtime/dispatcher file was edited.
The shared Deno manifest has append-only test entries to retain when merging.
Changes to schema/semantics require a new parser version and additive migration;
existing receipts, rows and publication history cannot be rewritten.

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
fail tests on any investor, fund, operation or outbox mutation.

Validation results on this worktree:

| Check | Result |
| --- | --- |
| Protected NSE fmt/check/test | Pass; 757 tests (645 baseline, 112 added) |
| B06.3 SQL/lint/concurrency | Pass; 318 assertions twice; no lint findings |
| Existing NSE SQL suites and concurrency | Pass after the new migration |
| All persistent SQL files, each on a fresh restored schema | Baseline 21 pass / 15 fail; candidate 22 pass / same 15 fail |
| Manifest/policy script tests; dispatcher tests | 22 pass; 54 pass |
| Documentation, migration history, commit format and shell syntax | Pass |

The broad SQL suite is **not green**. Its 15 unchanged baseline failures are listed
in the [foundation validation notes](NSE_MASTER_DOWNLOAD_FOUNDATION.md#validation-and-remaining-limits).
`SUPABASE_DB_CONTAINER=<disposable-container> sh supabase/tests/run_all.sh` stops at
`issue_114_service_role_protected_table_select:workspaces` on both baseline and
candidate. Separate fresh-schema runs establish that no prior pass regressed.
Logs and the comparison are retained under `/tmp/b063-*`; no existing ACL, fixture,
financial logic or CI requirement was changed to conceal those failures.
