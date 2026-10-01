# NSE B03 settlement and redemption reports

B03 is a local, evidence-first candidate for four distinct read-only contracts.
It records account-owned observations, not settlement, payout, allotment finality,
order completion, reconciliation or holdings truth. No provider commissioning or
hosted deployment is implied. B11 order/leg linkage and ingestion deduplication
remain prerequisites for any future financial distributor.

## Authority and candidate base

The implementation was based exactly on freshly fetched `origin/develop`
`09d3dd2d13fe9fe60b85876f5dc54a909e8e164f` (2026-10-01). The canonical
`/home/ubuntu/moneybowl` checkout was clean at that same SHA. Work is isolated on
`nse-b03-settlement-redemption-local` at
`/home/ubuntu/moneybowl-worktrees/nse-b03-settlement-redemption-local`.

Sources read directly under `/home/ubuntu/nse-uat-contract`:

- `docs/NSEMF_API_Details_V1.9.7.pdf`, printed/PDF pages 121–135, plus
  ORDER_STATUS pp78–83 for source identifier lineage.
- `NSEInvest API Realease_21-05-2025.postman_collection 2.json`, requests
  #35, #36 and #37 (vendor spelling `Allotement Statement Report`). No non-demat
  payout request exists in this collection. The environment artifact was read
  with output limited to key names; no credentials were copied or used.
- `analysis/NSE_COHERENT_IMPLEMENTATION_PLAN_V2_001.md` and `.json`, B03,
  source precedence, evidence/retry policy, B11 boundary and historical evidence.
- Recovered analysis `17_NSE_CONTRACT_CONFLICTS.md`, C024/C025/C026/C032.
- `analysis/live_uat/live_uat_results.json`, `live_response_schema_catalog.json`,
  `live_uat_summary.md`; controlled-write `first_purchase_lifecycle.md` and
  `nnf_v1_9_7_reconciliation.md`. Older inferred order/payment aliases are not
  ownership authority for B03.
- Current migrations, NSE helpers/workers/tests, integration architecture,
  AGENTS.md and implementation/database-security skills. Current source,
  including B01/B02 commissioning fixes, determines the reused lifecycle.

## Independent wire contracts

Every route below uses **POST**, shared authentication and JSON. The route
prefix is exactly `/nsemfdesk/api/v2/reports/`.

| API key | Exact route suffix | Handbook section/pages | Supported request |
| --- | --- | --- | --- |
| `REDEMPTION_PAYOUT` | `REDEMPTION_PAYOUT` | Redemption Payout Date Report API, p121 request; pp122–123 response, next section p124 | `from_date`, `to_date`, mandatory `report_type`, derived `order_id` **or** `member_unique_ids` |
| `REDEMPTION_PAYOUT_NON_DEMAT` | `REDEMPTION_PAYOUT_NON_DEMAT` | Redemption Payout Date Report – Non Demat API, p124 request; pp125–126 response | Its own `from_date`, `to_date`, mandatory `report_type`, derived `order_id` **or** `member_unique_ids` |
| `REDEMPTION_STATEMENT` | `REDEMPTION_STATEMENT` | Redemption Statement Report API, p126 request; pp127–129 response | `from_date`, `to_date`, derived `order_ids` **or** `member_unique_ids`; no `report_type` or `date_type` |
| `ALLOTMENT_STATEMENT` | `ALLOTMENT_STATEMENT` | Allotment Statement Report API, pp129–130 request; pp130–135 response | `from_date`, `to_date`, explicit `date_type`, derived `order_ids` **or** `member_unique_ids`; no `report_type` |

Each field table independently requires real `DD-MM-YYYY` dates with at most a
30-day difference, including when an ID filter overrides other filters. Reversed,
invalid, null or blank dates reject. No seven-day ORDER_STATUS/PROV rule is reused.

Both payouts enumerate `Order Date`, `Payout Date`, `Fund Transfer Date` with
exact casing/spaces. They have no client-code selector. The statements' formal
optional fields are `order_type` (All/NRM/STP/SWP), `sub_order_type`
(NRM/SWITCH/STP/ALL), `client_code`, `transaction_type` (P/R), `order_status`
(All/VALID/INVALID), and `settlement_type` (ALL/L0/L1/OTHERS). These ignored
non-ID variants are **not exposed** in this candidate. Payout `amc_code` is also
not exposed. Unknown fields and caller-supplied provider IDs always reject.

Allotment's `ORD_DATE` means order date; `ALT_DATE` means allotment date. The
service explicitly supplies `ORD_DATE` when the optional local choice is omitted.
It rejects `ORDER DATE`, `REQUEST DATE`, `ORDER_DATE`, padded/lowercase aliases and
null. Both choices serialize exactly, but an effective order/member filter
**overrides other filters** according to the handbook. B03 does not assert that
`ALT_DATE` further narrows an ID-selected result. A date-only/client-only variant
and report-date-to-allotment-date inference remain disabled.

All four tables allow at most 50 comma-separated order/member IDs. Payout's
singular `order_id` is still a list. Statements use plural `order_ids`. Order IDs
win; member IDs apply only if order IDs are absent. The service sends just the
chosen effective field, so simultaneous caller IDs cannot invert precedence.
Allotment's member column lists VARCHAR 25. All selected member IDs are bounded
by the prior ORDER_STATUS contract's 25-character limit regardless of endpoint.

## Proven selector lineage and constrained variants

`prepare_nse_settlement_redemption(workspace_id, integration_account_id, api,
filters, request_id?, selection?)` is service-only. API names omit `NSE_`.
Selection is mandatory for every API, exactly:

```json
{"result_id":"<local RESULT UUID>","row_indices":[0],"selector":"order"}
```

`selector` is optional and defaults to `order`; `member` uses proven returned
`member_unique_id` values. No raw NSE identifier is an accepted argument.
The service accepts 1–50 distinct positions from one immutable successful
ORDER_STATUS RESULT/REQUEST pair, belonging to the same registered NSE account,
workspace and UAT environment, NNF_1.9.7, exact endpoint/method, read-only
operation and successful latest interaction. It re-runs ORDER_STATUS's own
response validator against its retained request and verifies the owned UCC.
Source duplicates, non-string row values, mixed accounts, unsupported endpoints,
failed results, REQUEST UUIDs, malformed/out-of-range/repeated selections and
ambiguous member references reject. No broad member fallback exists.

Selected rows additionally require an order ID of digits, nonblank safe member
reference of at most 25 characters, member ID, scheme, ISIN, order date,
settlement ID/type and folio string. Their `order_type` and `order_sub_type` must
both be `NRM`. Redemptions/payouts require the source transaction `R`; allotment
requires `P`. These are conservative supported variants, not exhaustive native
response enums. Non-demat payout also requires a nonblank/non-placeholder owned
folio. Selecting a payout endpoint does not assert demat/non-demat equivalence
or derive a transaction mode from a different endpoint's vocabulary.

Disabled for all four: arbitrary IDs, unselected client/date/member-wide reads,
blank member references, systematic orders, switch/source/destination legs,
ambiguous registrar/correction lineage, missing source identity and source
endpoints other than ORDER_STATUS. PROV_ORDERS exposes `request_date` in its
sample, so it cannot supply B03's required order-date correlation here. B02's
product IDs and bank references are not silently relabeled as settlement orders.
Non-demat reads without an owned folio remain blocked. Member code padding is
not normalized: differing `4079`/`04079` strings fail correlation pending exact
endpoint commissioning. These restrictions constrain interpretation and never
trigger another provider request variant.

## Endpoint-specific response validation

Each response table independently defines `response_status` S/F,
`report_data_total`, `report_data`, and `error_remark`. A nonnegative integer or
digit-string count must match the array, bounded by 10,000 and the 1 MiB response
limit. S requires an array and the documented empty remark. Empty S is a
successful observation of no matching records, never proof that a write was not
sent or a financial state changed. F with zero count, blank data and a nonblank
string diagnostic is terminal `settlement_redemption_business_failed`; unknown
F shapes fail closed as `settlement_redemption_response_invalid`. Native F is
not a transport error. Nonempty S remarks fail with
`settlement_redemption_unknown_success_diagnostic`, including an apparently
familiar no-records phrase. There is no literal B03 historical diagnostic to
justify an exact compatibility exception. This policy is limited to these four
verified tables, not a universal NSE remark rule.

| API | Required identity and distinct structural behavior |
| --- | --- |
| Payout | `order_id`, `member_code`, `client_code`, `member_unique_id`, `scheme_code`, `isin`, `transaction_type=R`, `first_applicant_pan`, `settlement_id/type`, `order_date`; `rta_transaction_no`, `rta_scheme_code`, `funds_payout_status`, `allotted_amount`, payout/transfer date strings. Order date uses `DD MON YYYY`, matches prior `DD/MM/YYYY`; nonblank payout/transfer dates use this endpoint's sample format. |
| Non-demat payout | Same explicitly verified common identity columns, plus exact owned `folio_number`. Its own `product_code`, `payout_desc`, `mailed_date`, `despatch_status`, `instrm_no`, `instrm_bank`, `payee_acno`, `funds_payout_date`. Nonblank mailed/payout dates use the sample's `MM/DD/YYYY h:mm:ss AM/PM` shape. It does not borrow demat's RTA-scheme or transfer-date columns. |
| Redemption statement | `orderno`, `membercode`, `clientcode`, member reference, `schemecode`, ISIN, `settlementid`, `settlementype`, `rtatransactionno`; order/report dates use `DD-MM-YYYY`. `ordertype`/`ordersubtype` must be the supported `NRM` leg. `validflag`, `dptrans`, `allottednav`, `allottedqty`, **`allottedamt`** remain native strings. |
| Allotment statement | `orderno`, **`memberid`**, `clientcode`, member reference, scheme/ISIN, settlement and registrar identity; order/report dates use its current sample's `YYYY-MM-DD`. Supported NRM legs only. `validflag`, `dptrans`, NAV/quantity, **`allotmentamt`**, `pgbankrefno` retain their native fields. `reportdate` is not invented as proof of final allotment time. |

The parsers require these string columns, retain additional string columns only
as encrypted evidence, and reject non-string row values. Exact member reference,
UCC, member ID, scheme, ISIN, order ID/date, settlement ID/type must match the
selected prior row; payout also checks PAN, and non-demat checks folio. Native
`funds_payout_status` and `validflag` are not promoted to paid/valid/settled state;
the sample `S,T,R` is not treated as an exhaustive non-demat enum.

A positive response must cover every selected order exactly once. Empty reads
are allowed separately; a partial positive selection fails. Duplicate order IDs,
duplicate registrar transaction IDs, foreign/extra/missing rows or unsupported
switch legs fail the entire trusted interpretation. Multiple selected normal
orders remain separate observations. Corrections/reversals and finality cannot
be established by an isolated matching row; there is no financial projection.

## Conflict and historical evidence resolutions

| Conflict | Current resolution |
| --- | --- |
| C024 | p121 explicitly includes `member_unique_ids`, maximum 50, subordinate to `order_id`; pp123 returned member references enable business-field correlation. Old #35 omits the filter. Implement current table with owned selections. |
| C025 | p126 independently defines member IDs subordinate to plural `order_ids`; pp128–129 return `member_unique_id`. Old #36 omits the newer fields. No payout field/schema aliases. |
| C026 | p130 explicitly adds member IDs (VARCHAR 25), subordinate to plural `order_ids`; pp132–134 contain returned references, including a blank example which the conservative selected slice excludes. Old #37 omits the filter. |
| C032, allotment portion | p130 enumerates `ORD_DATE`/`ALT_DATE` and their distinct meanings. ORDER_STATUS has no date_type; PROV uses space-separated different values. Neither definition is reused here. Old #37 lacks this field. |

Historical sweep metadata dated 2026-08-31 establishes: #35 payout was **not
attempted**, because a safe owned `order_id` was missing; #36 redemption statement
and #37 allotment returned HTTP200 JSON with a success-like status, string count,
empty array and nonempty string diagnostic, 101 bytes each. The sweep explicitly
did not retain raw values. Non-demat payout was absent. Therefore no exact
nonempty-remark compatibility rule is enabled. No historical positive row,
correction, switch leg, registrar finality, payout credit or settlement semantics
is proven. Controlled-write documents describe future lifecycle/alias plans;
they supply no completed B03 financial projector or positive evidence.

## Worker, schema, evidence and retry boundary

One `nse-settlement-redemption-worker` uses explicit endpoint builders/parsers,
existing NseClient/auth/config, `nse_evidence_call` and `NSE_WORKER_TOKEN`.
`integration.nse.settlement_redemption_requested` routes through the existing
Oracle dispatcher. HTTP callers may supply only `event_outbox_id`.

The append-only migration adds **no tables or columns**, no RLS policies,
no browser grants, no API-specific secrets and no financial migrations. It adds
15 functions (seven service facades, eight private helpers), one partial unique
outbox index, an immutable-context trigger and extends expired-read dispatcher
recognition while preserving ORDER_STATUS/PROV/B01/B02 routes. Definers have
empty search paths and qualified references; PUBLIC/anon/authenticated cannot
execute B03 facades; service_role cannot execute private decrypt/selector/parser
helpers. Preparation binds an active workspace/investor, unique registered UCC,
verified canonical PAN and immutable selected evidence. Current identity is
rechecked before transport; after send the snapshot governs historical results.

REQUEST is serialized once, encrypted before transport, then sent identically.
Every attempt has a fresh call ID, immutable REQUEST/RESULT pair, exact bytes,
SHA-256, byte length, method/path, environment, correlation/attempt/key references
and timestamps. RESULT preserves bounded UTF-8, BOM, malformed UTF-8 and embedded
NUL through the established base64 RPC transport and text/binary pgcrypto
ciphertext. Safe header metadata excludes credentials and cookies. Unknown JSON,
malformed/foreign reports and parser disagreement retain exact RESULT evidence.
SQL independently interprets durable results; disagreement becomes terminal
`settlement_redemption_interpretation_mismatch`, never a successful worker reply.

Maximum three claimed attempts. Reviewed HTTP retries are 408/429/500/502/503/504;
transport retries are network failure/timeout only. Oversize/invalid response and
invalid request errors are terminal. Claims and the dispatcher enforce a bounded
30-second retry delay (the dispatcher can delay further); recovery consumes
expired pre-request claims and records truthful empty TRANSPORT_FAILURE evidence
for orphaned REQUESTs. This is not proof of NOT_SENT. Recovery never authorizes
financial writes. Persistence acknowledgement retries reuse captured inputs and
cannot repeat provider transport. F/malformed/foreign/mixed results never retry.

Service-only summaries return local UUIDs, API, observation time, count, envelope
status and normalized category, not provider rows, references, folios, banks,
amounts, PAN/UCC, holder details or provider diagnostics. No public.transactions,
portfolio, holding, folio, canonical order, payment or settlement state changes.
Compose, hosted settings and secrets remain untouched.

## Local validation and commissioning gates

The configured manifest adds seven fmt/check targets and two test suites, keeping
all existing UCC registration/verification/Client Master, ORDER_STATUS,
PROV_ORDERS, B01 and B02 coverage. Tests use synthetic owned prior evidence,
mocked transport, current-schema PostgreSQL RPCs and rollback-only keys.
The harness applies every current migration in a disposable PostgreSQL
17.6.1.155 container, with network disabled and no published ports. It runs generic
dispatcher/UCC SQL and twice runs ORDER_STATUS/PROV/B01/B02/B03, checks rollback
cleanliness and removes the container. B03 installs transaction-local guards
that reject mutations to the current transactions, portfolios, folio_references,
portfolio_folio_references, order_requests and payment_events relations.
The current schema has no separate public.folios or scheme_holdings table. Exact executed results accompany the
committed candidate; the following are the required commands:

```bash
python3 scripts/nse_test_manifest_v1.py validate
python3 -B -m unittest discover -s scripts -p nse_test_manifest_v1_test.py -v
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 fmt
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 check
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 test
scripts/test_nse_order_status_sql.sh
# services/outbox-dispatcher working directory:
/tmp/moneybowl-prov-test-env/bin/python -B -m pytest
# repository root:
python3 .github/scripts/validate_docs.py
python3 .github/scripts/validate_migration_history.py
python3 .github/scripts/validate_commits.py
bash -n scripts/test_nse_order_status_sql.sh
git diff --check
git diff 09d3dd2d13fe9fe60b85876f5dc54a909e8e164f..HEAD --check
```

Each API still requires individually authorized UAT commissioning: owned positive
rows, empty/F diagnostics with literal values kept privately, ID filter/precedence,
member-code formatting, exact dates, native states, real report volume and content
types. Payout requires confirmed payout/transfer/credit and correction semantics;
non-demat additionally requires its own folio, despatch, bank and date/state proof;
redemption statement requires registrar/leg and redemption completion semantics;
allotment requires ORD_DATE/ALT_DATE behavior and exact purchase/destination-leg,
allotment/correction/finality semantics. None was commissioned in this run.

Before any financial-write prerequisite, implement B11's durable account/order/
leg identity and endpoint-specific positive predicates; prove full switch leg
coverage and registrar corrections/reversals; establish immutable RESULT ingestion
keys, correction ordering, deduplication, transaction/folio destinations and
replayable audited distribution. Empty reads, HTTP200, envelope S or native status
strings alone can never authorize provider resend or financial mutation.

## Candidate validation results

The final local validation completed with these results (2026-10-01):

| Command from the block above | Result |
| --- | --- |
| Manifest `validate` | PASS |
| Manifest Python unittest discovery | PASS, 21 tests |
| Protected runner `manifest-v1 fmt` | PASS, 41 files |
| Protected runner `manifest-v1 check` | PASS, all 41 configured targets |
| Protected runner `manifest-v1 test` | PASS, 406 tests across 19 suites |
| `scripts/test_nse_order_status_sql.sh` | PASS, all 68 migrations, generic dispatcher/UCC regressions, two passes each of ORDER_STATUS/PROV/B01/B02/B03, rollback cleanliness and container cleanup |
| Pinned dispatcher pytest | PASS, 15 tests |
| Documentation validator | PASS |
| Migration-history validator | PASS, 27 frozen migrations unchanged |
| Shell syntax and working/index diff checks | PASS |

The commit validator and base-to-HEAD diff check are run again after the local
commit and reported with the final HEAD. Earlier syntax/type/fixture failures
were corrected before these passes. The stricter mutation test initially named
the architecture's proposed folio/holding tables; it now targets the actual
current relations listed above. No unresolved implementation/test failures remain.
The intentionally blocked variants and uncommissioned provider behavior remain
as documented, including unknown success diagnostics and all B11 financial gates.

The entire candidate diff was reviewed, including the new endpoint contracts,
source lineage, SQL/TypeScript classifiers, tests, routing/configuration and docs.
The retained lifecycle/byte-persistence code was also compared against B02; the
B03 differences are explicit API dispatch, strict selectors, transient-only
transport retries and claim-enforced backoff. No old migration was edited.

## Complete changed-file inventory

```text
docs/CHANGELOG.md
docs/architecture/NSE_SETTLEMENT_REDEMPTION_VERTICAL_SLICE.md
docs/architecture/SYSTEM_ARCHITECTURE.md
scripts/nse_test_manifest_v1_test.py
scripts/test_nse_order_status_sql.sh
services/outbox-dispatcher/README.md
services/outbox-dispatcher/routes.json
services/outbox-dispatcher/tests/test_dispatcher.py
supabase/config.toml
supabase/functions/_shared/nse/NSE_TEST_MANIFEST_V1.json
supabase/functions/_shared/nse/nse_settlement_redemption.ts
supabase/functions/_shared/nse/nse_settlement_redemption_test.ts
supabase/functions/nse-settlement-redemption-worker/adapters.ts
supabase/functions/nse-settlement-redemption-worker/handler.ts
supabase/functions/nse-settlement-redemption-worker/index.ts
supabase/functions/nse-settlement-redemption-worker/index_test.ts
supabase/functions/nse-settlement-redemption-worker/types.ts
supabase/migrations/20261001202404_nse_b03_settlement_redemption.sql
supabase/tests/nse_settlement_redemption_vertical_slice_test.sql
```

This implementation used no real NSE transport, hosted worker, hosted Supabase,
GitHub mutation, push, PR, deployment, Production change or secret rotation.
The canonical checkout's source was not modified. Synthetic database fixtures
and keys existed only inside the disposable rollback harness. Publication and
UAT commissioning are separate, future work requiring authorization.
