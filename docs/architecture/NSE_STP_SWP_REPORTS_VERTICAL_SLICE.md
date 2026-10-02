# NSE B05 STP, SWP and AMC Pause observations

This local candidate implements seven READ_BOUNDED contracts. One
`STP_SWP_REPORTS` operation/event/worker family reuses integration accounts,
operations, interactions, encrypted REQUEST/RESULT evidence and the outbox.
It creates no provider-report tables, canonical schedules, withdrawals, pause
state, payments or projections. Those domains remain B12/B16 and later batches.
No hosted deployment or NSE UAT call was performed.

## Base and source authority

Fresh fetch on 2026-10-02 resolved `origin/develop` to
`65d73c23920934b0c77ee00e753fcfc0cc0aca32`. The canonical checkout was clean.
Worktree: `/home/ubuntu/moneybowl-worktrees/nse-b05-stp-swp-reports-local`.
Branch: `feature/nse-b05-stp-swp-reports-local`.

Sources under `/home/ubuntu/nse-uat-contract`, in precedence order:

1. `docs/NSEMF_API_Details_V1.9.7.pdf`, pp180–191 and pp275–277.
   The AMC response **continues onto p277**; the inventory's pp275–276 range
   alone is incomplete. SHA256
   `5c3c819d788e40ba28f8d2eb3a6b2faabc3a39c5e9bc658fa034cf4c26cc576a`.
2. `NSEInvest API Realease_21-05-2025.postman_collection 2.json`:
   actual recursive request traversal confirms STP/SWP requests 52–57.
   No saved responses. Registration requests omit current `member_unique_ids`.
   SHA256 `9db36cfb4bfb67b4481c9d8b462b0c534286f417e98067cd769b04e6f224f6fd`.
3. `analysis/NSE_COHERENT_IMPLEMENTATION_PLAN_V2_001.md` and `.json`, B05,
   C029/C030, ownership/evidence boundaries and commissioning gates. MD SHA256
   `e61c22ce66ab42418486e81a02f89572eff175600792bc7c59ec112ac6423f16`;
   JSON SHA256 `06f5680a69054900c2f7f9c46ff5100172484e6e78d554638facd090e6d794b7`.
4. Current B01–B04 source, browser facade, dispatcher and deployment configuration.

No older recovered analysis was needed. Platform mechanics retain the current
[Supabase database-function guidance](https://supabase.com/docs/guides/database/functions):
empty definer search paths, qualified relations and explicit privilege revocation.

## Exact endpoint contracts

All are POST with existing NSE authentication and JSON. Stable identities have
prefix `NSE_`; the internal API key is the table's API column. The exact route is
`/nsemfdesk/api/v2/reports/` followed by the route suffix below.

| API | Route suffix | Pages / Postman | Native selectors, in precedence order | Request dates |
| --- | --- | --- | --- | --- |
| STP_REG_REPORT | STP_REG_REPORT | 180–182 / 52 | `stp_reg_id`, then `member_unique_ids`, then `client_code`, then dates | DD-MM-YYYY, 31-day gap |
| STP_CAN_REPORT | STP_CAN_REPORT | 182–184 / 53 | `stp_reg_id`, then `client_code`, then dates | DD-MM-YYYY, 31-day gap |
| STP_INST_DUE_REPORT | STP_INST_DUE_REPORT | 183–185 / 54 | `stp_reg_id`, then `client_code`, then dates | DD-MM-YYYY, 7-day gap; from cannot be past |
| SWP_REG_REPORT | SWP_REG_REPORT | 185–187 / 55 | `swp_reg_id`, then `member_unique_ids`, then `client_code`, then dates | DD-MM-YYYY, 31-day gap |
| SWP_CAN_REPORT | SWP_CAN_REPORT | 187–189 / 56 | `swp_reg_id`, then `client_code`, then dates | DD-MM-YYYY, 31-day gap |
| SWP_INST_DUE_REPORT | SWP_INST_DUE_REPORT | 189–191 / 57 | `swp_reg_id`, then `client_code`, then dates | DD-MM-YYYY, 7-day gap; from cannot be past |
| SIP_AMC_PAUSE_REPORT | SIP_AMC_PAUSE | 276–277 / absent | Independent `client_code`, `registration_no`, `modification_type`, `request_id`; request ID makes rest optional | DD/MM/YYYY, 7-day gap; no documented non-past rule |

The six STP/SWP request tables define max-50 comma-separated registration/UCC
lists; the two registration reports independently add max-50 member references.
Dates are mandatory when registration ID and UCC are absent, including the
member-only supported registration slice. An effective registration/member/UCC
selector ignores the other filters. Optional date pairs are validated but are
not claimed to narrow UCC/member results. Every supplied pair must contain real
calendar dates, a strictly later end, and no more than the documented elapsed gap.
Due non-past checks use the India market day as an explicit MoneyBowl policy.
Historical result interpretation does not expire prior valid evidence.

AMC Pause does not inherit that precedence. Dates are mandatory when all three
of registration number, client code and request ID are absent. The table defines
client code VARCHAR15, registration number Numeric15 and request ID VARCHAR11.
The latter identifies a pause request, not the SIP registration. `modification_type`
is documented as VARCHAR5 while listing both PAUSE and seven-character UNPAUSE.
Only the explicit `PAUSE` selector is implemented. UNPAUSE, unfiltered modification
queries, arbitrary registration/request IDs and guessed response aliases are blocked.
The complete published example on pp276–277 supports the PAUSE-shaped observation
parser; it does not establish a separate UNPAUSE schema or reconciliation predicate.

## Owned selectors and frontend availability

The service-only preparation interface is:

```text
prepare_nse_stp_swp_reports(workspace_id, integration_account_id, api,
  filters = {}, request_id = local UUID, selection = JSON null)
```

Only optional `from_date`/`to_date` may enter filters. UCC comes from the registered
UAT integration account. Active workspace/investor membership, verified canonical
PAN, account identity and unique UCC are rechecked before send. PAN stays encrypted
in context and is not sent by these reports. No failed query broadens its selector.

| Variant | Service preparation | Browser console |
| --- | --- | --- |
| STP registration/cancellation; SWP registration/cancellation/due | Registered investor's single UCC | Available subject to existing authorization, identity and DEV gate |
| STP/SWP registration member filter | Same-account, same-endpoint successful registration RESULT plus row positions | Not exposed; UCC variant available |
| STP due | Owned STP registration RESULT plus row positions, yielding `stp_reg_id` only | Blocked: `OWNED_STP_REGISTRATION_SELECTION_REQUIRED` |
| AMC Pause | Single registered UCC plus fixed `modification_type=PAUSE` | Available when UCC length is at most 15; PAUSE only |
| Raw identifiers, date-only/member-wide, other registration-ID variants, AMC request-ID/UNPAUSE | Disabled | No generic input interface |

Evidence selections have exactly `result_id`, `row_indices` (1–50 distinct integer
positions), and `selector` (`member` for registration reports; `registration` for
STP due). SQL verifies account/workspace/UAT/integration/version/API/path/method,
latest successful immutable RESULT and paired REQUEST, decrypts and independently
revalidates all rows, and requires the source to have used the account's UCC.
REQUEST IDs, foreign/mixed/failed evidence, wrong API, duplicate/out-of-range
positions and recursive selection sources reject.

C029/C030 resolve in favor of the current handbook's `member_unique_ids`, absent
from older Postman requests 52/55. Selected member references must be unique in
the entire source report and match returned registration identity and frozen
business fields exactly. The local safe reference character bound is 1–100 ASCII
letters/digits/underscore/hyphen; 100 is a local bound, not a vendor VARCHAR claim.
STP snapshots registration number/date, member reference/code, both NSE scheme
codes, frequency, start/end dates, amount and units. SWP snapshots its corresponding
registration/date, reference/code, NSE scheme, frequency, start/end, amount and units.
A positive member result must cover all selected registrations once.

STP due uniquely lacks `client_code` and `member_code` in its published rows.
Its UCC-only variant is therefore disabled. A validated STP registration RESULT
supplies number, frequency, transfer amount/units, folio and internal reference.
Returned due rows must match those values exactly. Duplicate number/due-date
pairs reject; multiple different due dates for an owned registration are allowed.
No parsing of names, embedded scheme-code prefixes or registration timestamps is
used to invent ownership. A subset or empty due report proves no schedule state.

Flutter still calls authenticated browser-safe RPCs, never workers or service
RPCs. The catalog has 32 command kinds, 27 account-scoped commands plus four
conditional B03 commands and blocked STP due. Dates remain browser ISO dates;
the trusted facade compiles AMC dates to slashes. The UI label is now
**NSE Investor / UCC Integration**. Existing DEV/UAT build and database gates,
authorization, idempotency, rate limits, audit, polling and safe DTOs remain intact.

## Response envelopes and exact rows

The six STP/SWP envelopes have exactly `response_status`, `report_data_total`,
`report_data`. AMC independently requires `response_status`, `response_data_total`,
`report_data`, `error_remark`; the latter must be the empty string. Counts may be
nonnegative integral numbers or digit strings, must equal array length and are
bounded at 10,000. Every row field below is required as a string; extra fields,
wrong types, missing fields, duplicates, foreign/mixed UCCs or member codes fail
the whole report. No column aliases or status meanings are invented. Native row
status, remarks, amounts and dates remain encrypted vendor strings.

Success requires native S. Empty S/zero/array is an observation only. Any diagnostic
on the six STP/SWP endpoints, any nonempty AMC diagnostic, uncharacterized F, count
conflict or unknown schema is terminal and fails closed. B05 has no diagnostic
compatibility exceptions. STP/SWP registration/cancellation uniqueness is their
registration number; SWP due uses `swp_regn_no`/`due_date`; AMC uses `request_id`.
Two AMC request IDs for one SIP registration remain distinct observations. AMC
row registration/request IDs are restricted locally to decimal strings within
15/11 characters; the native request-ID type remains VARCHAR11, not a claimed
numeric vendor contract. Broader lexical forms need characterization.

### STP_REG_REPORT row fields

```text
status, member_code, client_code, stp_registration_no, folio_no, internal_ref_no, from_amc_name, to_amc_name, from_scheme_name, to_scheme_name, stp_registration_date, stp_start_date, stp_end_date, frequency_type, trxn_mode, transfer_amount, transfer_units, no_of_transfers, first_order_todays_flag, euin_declaration, euin_number, sub_br_code, remarks, sub_br_arn_code, buy_sell_type, from_nse_scheme_code, to_nse_scheme_code, email_id, mobile_no, member_unique_id
```

### STP_CAN_REPORT row fields

```text
member_code, client_code, stp_registration_no, folio_no, from_amc_name, to_amc_name, from_scheme_name, to_scheme_name, stp_registration_date, stp_start_date, stp_end_date, frequency, trxn_mode, transfer_amount, transfer_units, no_of_transfers, euin_declaration, euin_number, sub_br_code, remarks, stp_cancellation_date, stp_cancelled_by
```

### STP_INST_DUE_REPORT row fields

```text
stp_registration_no, client_name, folio_no, internal_ref_no, stp_registration_date, amc_name, from_scheme_name, to_scheme_name, frequency_type, dp_trans, transfer_amount, transfer_units, due_date, prev_transfer_date, no_of_transfer_completed, first_order_todays_flag, euin_declaration, euin_number, sub_br_code, remarks, entry_by
```

### SWP_REG_REPORT row fields

```text
status, member_code, client_code, swp_registration_no, folio_no, amc, scheme_name, frequency_type, swp_registration_date, swp_start_date, swp_end_date, withdrawl_amount, withdrawal_units, no_of_withdrawls, euin_declaration, euin_number, subbrcode, first_order_flag, int_ref_no, remark, sub_broker_arn_code, nse_scheme_code, transaction_mode, mobile_no, email_id, bank_account_no, member_unique_id
```

### SWP_CAN_REPORT row fields

```text
member_code, client_code, swp_registration_no, folio_no, amc, scheme_name, swp_registration_date, swp_cancellation_date, swp_start_date, swp_end_date, frequency_type, withdrawl_amount, withdrawl_units, no_of_withdrawls, euin_declaration, euin_number, subbrcode, remark, swp_cancelled_by, nse_scheme_code
```

### SWP_INST_DUE_REPORT row fields

```text
member_code, client_code, client_name, swp_regn_no, folio_no, internal_ref_no, regn_date, amc_name, scheme_code, scheme_name, frequency_type, installment_amt, installment_units, due_date, prev_paid_date, no_of_installments_paid, total_installment_amt_sold, unit_sold, entry_by, dp_trans, euin_declaration, euin_number, subbrcode, first_order_flag, remark
```

### SIP_AMC_PAUSE_REPORT row fields

```text
client_code, sip_registration_no, scheme_code, scheme_name, amount, sip_start_date, sip_end_date, no_of_instalments_paused, date_of_activation, pause_from_date, pause_to_date, request_id, entry_by, modified_date, modified_instalments
```

## Diagnostic compatibility policy

`nse_response_diagnostics_v1.json` is the versioned rule authority. A small typed
matcher returns either an exact rule or no match. PostgreSQL has an immutable
private function containing the same snapshot; a local parity test enforces exact
agreement. There is no policy table, mutable UI or service-role editing surface.
Rules bind stable API, native status, literal diagnostic, count, empty-array shape,
normalized outcome, safe category, retry=false and evidence provenance. Endpoint
parsers still validate structure, counts, rows and ownership independently.

| Stable API | Status / literal | Required shape | Result |
| --- | --- | --- | --- |
| NSE_CLIENT_KYC_REPORT | S / `No record(s) found.` | Count zero, empty array | SUCCESS; `client_readiness_report_received` |
| NSE_ORDER_LIFECYCLE | S / `No record(s) found.` | Count zero, empty array | SUCCESS; `order_funding_no_records` |
| NSE_TRANSACTION_DETAIL | S / `No record(s) found.` | Count zero, empty array | SUCCESS; `order_funding_no_records` |
| NSE_FUND_ORDER | F / `No record(s) found` | Count zero, empty array | BUSINESS_FAILURE; `order_funding_no_records` |
| NSE_FUND_AGE | F / `amc_code value is not valid.` | Count zero, empty array | BUSINESS_FAILURE; `order_funding_amc_code_invalid` |

All are terminal without transport retry. Unknown diagnostics return no match and
fail closed in the migrated paths. No case-folding, trimming, punctuation variants,
global no-record success, or aliases are introduced.

The CLIENT_KYC_REPORT rule is based on the exact HTTP200/S/zero/empty envelope
supplied from retained 2026-10-02 DEV/UAT commissioning evidence. Its diagnostic
exists only in encrypted RESULT evidence; safe metadata and browser DTOs expose
no diagnostic. Parser, worker and durable SQL finish regressions cover it.

Deliberately retained legacy rules, **not generalized by this framework**:
ORDER_STATUS and PROV_ORDERS keep their current independent diagnostic parsers;
ELOG_REPORT keeps its existing string-diagnostic success handling; FUND_AGE keeps
its existing S/empty diagnostic handling and B02's native F/empty-string failure
shape. The current ELOG rule is broader than an exact literal whitelist. Moving
or narrowing those behaviors needs their exact retained evidence and separate
review; this candidate does not silently characterize additional strings.
Existing tests for all these paths pass unchanged.

## Evidence, persistence and retry boundaries

`integration.nse.stp_swp_reports_requested` routes to
`nse-stp-swp-reports-worker` with `NSE_WORKER_TOKEN`. The worker accepts only an
event UUID authenticated by that shared internal token. Its endpoint map is closed.
Every request is serialized once, encrypted before transport and sent byte-for-byte.
It uses existing NSE configuration/authentication and bounded evidence-call mechanics:
30-second transport, 1 MiB response, redirect rejection and three-attempt maximum.
Only 408/429/500/502/503/504 and network/timeout failures permit bounded read retry,
with at least 30 seconds' backoff. Business/unknown/schema/ownership outcomes do not.
Persistence acknowledgement retries reuse captured bytes and never repeat transport.

SQL independently interprets retained bytes. Worker/SQL disagreement retains the
RESULT and becomes terminal interpretation mismatch. BOM, malformed UTF-8 and NUL
use existing binary evidence transport; hashes/lengths describe the actual bytes.
Expired REQUEST recovery records truthful transport-failure evidence, never a
claim that a request was not sent. Context and REQUEST/RESULT are immutable.
Service-only summaries contain local references, API, timestamp, status/category
and count. Financial tables are protected by statement-level mutation guards in tests.

Three new additive migrations implement the family, diagnostic policy and browser
catalog. No historical migration, financial table or RLS policy was rewritten.
Private helpers have no PUBLIC/anon/authenticated/service-role execution grant;
only the seven worker service facades are service-callable. Browser users retain
only the existing authenticated application facade.

## Validation record

Baseline was recorded before implementation edits, separately in
`/tmp/nse-b05-local/BASELINE.txt`: fresh base above; 48 Deno fmt/check targets;
502 NSE tests in 21 suites; 21 Python manifest tests; 16 dispatcher tests;
50 Flutter tests; all 70 migrations from scratch; generic dispatcher/UCC plus
ORDER_STATUS/PROV/B01/B02/B03/B04/frontend twice, rollback cleanliness and browser
concurrency; docs and 27 frozen migration-history checks passed.

Current local validation commands and observed results:

| Validation | Result |
| --- | --- |
| Manifest validator and Python manifest/policy tests | PASS; 22 tests (one new parity test) |
| Protected offline Deno runner fmt/check | PASS; 58 targets |
| Protected offline Deno test | PASS; 620 tests / 24 suites, 118 added: 60 B05 contract, 51 B05 worker, 6 diagnostic, 1 KYC worker |
| Disposable network-none PostgreSQL harness | PASS; 73 migrations from scratch; all historical suites retained; B05 1,539 assertions per pass, twice; rollback cleanliness and facade concurrency |
| B05 facade tests | Six new account commands, blocked STP due, denied-persona matrix under actual authenticated role; raw identifiers denied |
| Flutter tests and feature analysis | PASS; 51 tests (one new B05 test), no feature analysis issues |
| Dispatcher pytest | PASS; 54 tests (16 baseline, 38 deployment/reconciliation tests) |
| Dispatcher test/runtime Docker build | PASS; isolated test image runs with network none, UID10002, read-only root and dropped capabilities; no live activation |
| Synthetic Compose rendering and deployment preflight | PASS against installed Compose 5.5.0; no daemon/provider calls |
| Shell syntax and sudoers syntax | PASS; bootstrap not executed |
| Documentation, migration history and diff checks | PASS; 27 Markdown files, 27 frozen migrations; clean diff |

Commands from the worktree root:

```bash
python3 scripts/nse_test_manifest_v1.py validate
python3 -B -m unittest discover -s scripts -p 'nse*test.py' -v
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 fmt
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 check
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 test
bash scripts/test_nse_order_status_sql.sh
# Dispatcher pytest working directory: services/outbox-dispatcher
/tmp/moneybowl-prov-test-env/bin/python -B -m pytest
# Worktree root:
python3 scripts/test_outbox_compose.py
bash -n scripts/test_nse_order_status_sql.sh services/outbox-dispatcher/deploy/bootstrap.sh
visudo -cf services/outbox-dispatcher/deploy/dispatcher.sudoers
python3 .github/scripts/validate_docs.py
python3 .github/scripts/validate_migration_history.py
python3 .github/scripts/validate_commits.py
git diff --check
```

Flutter uses `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter`, with
`test --no-pub test/features/nse_integration test/authentication/route_guard_test.dart test/referral_attribution_test.dart`
and `analyze --no-pub lib/features/nse_integration test/features/nse_integration`.
Logs are in `/tmp/nse-b05-local/`; no credential/evidence values were logged.
Sandbox Docker/socket restrictions required authorized test escalation. New-test
issues corrected during implementation: SQL CASE parentheses, a TypeScript tuple
spread, KYC test-gateway endpoint expectation, manifest reviewed-path allowlists,
and Compose's string representation of byte-valued memory limits. None were
reported as passing before correction. Running dispatcher pytest from the repo
root caused import-collection errors; the documented service working directory passes.

## Commissioning questions and blocked variants

- No positive B05 UAT responses or live no-record diagnostics were gathered here.
  Characterize each endpoint's actual field set, count type and bounded empty shape
  before treating it as a reconciliation gate. Unknown differences fail closed.
- Prove member-reference lookup behavior and selected-registration coverage using
  owned STP/SWP data. STP due requires correlated positive registration evidence;
  its missing client identity is not resolved by sending an arbitrary ID.
- Independently verify AMC PAUSE date behavior and full row shape. UNPAUSE remains
  blocked until its size/schema conflict is resolved by authoritative material.
  Request-ID selection and pause-state reconciliation remain future scope.
- Commissioner must confirm existing root-owned env values equal the live
  dispatcher's values without printing them. Presence of all three required keys
  was verified read-only; exact equality is enforced during reconciliation.
- Dispatcher automation source is implemented, but bootstrap and host commissioning
  are required. See [dispatcher automation runbook](ORACLE_OUTBOX_DISPATCHER_RECONCILIATION.md).

## Changed-file inventory

- `.github/workflows/outbox-dispatcher.yml`
- `docs/CHANGELOG.md`
- `docs/architecture/NSE_STP_SWP_REPORTS_VERTICAL_SLICE.md`
- `docs/architecture/ORACLE_OUTBOX_DISPATCHER_RECONCILIATION.md`
- `docs/architecture/SYSTEM_ARCHITECTURE.md`
- `lib/features/nse_integration/domain/nse_models.dart`
- `lib/features/nse_integration/presentation/nse_integration_page.dart`
- `scripts/nse_response_diagnostics_policy_test.py`
- `scripts/nse_test_manifest_v1_test.py`
- `scripts/test_nse_order_status_sql.sh`
- `scripts/test_outbox_compose.py`
- `services/outbox-dispatcher/Dockerfile`
- `services/outbox-dispatcher/deploy/bootstrap.sh`
- `services/outbox-dispatcher/deploy/compose.yaml`
- `services/outbox-dispatcher/deploy/config.example.json`
- `services/outbox-dispatcher/deploy/dispatcher.sudoers`
- `services/outbox-dispatcher/deploy/moneybowl-outbox-dispatcher-reconcile.service`
- `services/outbox-dispatcher/deploy/moneybowl-outbox-dispatcher-reconcile.timer`
- `services/outbox-dispatcher/deploy/moneybowl-outbox-dispatcher-reconcile@.service`
- `services/outbox-dispatcher/deploy/process-spool.py`
- `services/outbox-dispatcher/deploy/reconcile.py`
- `services/outbox-dispatcher/deploy/routes-contract.json`
- `services/outbox-dispatcher/deploy/webhook-dispatch.override.conf`
- `services/outbox-dispatcher/routes.json`
- `services/outbox-dispatcher/tests/test_reconcile.py`
- `supabase/config.toml`
- `supabase/functions/_shared/nse/NSE_TEST_MANIFEST_V1.json`
- `supabase/functions/_shared/nse/nse_client_readiness.ts`
- `supabase/functions/_shared/nse/nse_order_funding.ts`
- `supabase/functions/_shared/nse/nse_response_diagnostics.ts`
- `supabase/functions/_shared/nse/nse_response_diagnostics_test.ts`
- `supabase/functions/_shared/nse/nse_response_diagnostics_v1.json`
- `supabase/functions/_shared/nse/nse_stp_swp_reports.ts`
- `supabase/functions/_shared/nse/nse_stp_swp_reports_fixtures.ts`
- `supabase/functions/_shared/nse/nse_stp_swp_reports_test.ts`
- `supabase/functions/nse-client-readiness-worker/index_test.ts`
- `supabase/functions/nse-stp-swp-reports-worker/adapters.ts`
- `supabase/functions/nse-stp-swp-reports-worker/handler.ts`
- `supabase/functions/nse-stp-swp-reports-worker/index.ts`
- `supabase/functions/nse-stp-swp-reports-worker/index_test.ts`
- `supabase/functions/nse-stp-swp-reports-worker/types.ts`
- `supabase/migrations/20261002114757_nse_b05_stp_swp_reports.sql`
- `supabase/migrations/20261002114758_nse_response_diagnostic_policy.sql`
- `supabase/migrations/20261002114759_nse_b05_browser_catalog.sql`
- `supabase/tests/nse_client_readiness_vertical_slice_test.sql`
- `supabase/tests/nse_frontend_integration_v1_test.sql`
- `supabase/tests/nse_response_diagnostics_test.sql`
- `supabase/tests/nse_stp_swp_reports_vertical_slice_test.sql`
- `test/features/nse_integration/nse_integration_test.dart`
