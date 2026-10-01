# NSE B04 SIP and XSIP report family

B04 implements nine read-only report adapters with one worker. Results are private
observations backed by encrypted evidence. No schedule, cancellation, installment,
payment, holding or transaction state is created or changed. This is a local
candidate for review; no endpoint has been commissioned by this work.

## Base and authoritative sources

The fresh `git fetch origin develop` on 2026-10-01 resolved to
`0b4b1008f2707a301152fc658645c53eb14524e1`, unchanged from the supplied SHA.
The canonical `/home/ubuntu/moneybowl` checkout was clean. Implementation is in
`/home/ubuntu/moneybowl-worktrees/nse-b04-sip-xsip-reports-local`, branch
`feature/nse-b04-sip-xsip-reports-local`, created from that exact SHA.

Sources, in precedence order, under `/home/ubuntu/nse-uat-contract`:

1. `docs/NSEMF_API_Details_V1.9.7.pdf`, June 2026, PDF/printed pp164–180.
   Read the request tables and complete response examples; p165 was also
   rendered and visually inspected to verify the corrupt SIP total key.
   SHA-256: `5c3c819d788e40ba28f8d2eb3a6b2faabc3a39c5e9bc658fa034cf4c26cc576a`.
2. `NSEInvest API Realease_21-05-2025.postman_collection 2.json`, requests
   43–51 in actual collection traversal. These contain no saved responses.
   Request field names were compared without displaying credential values.
   SHA-256: `9db36cfb4bfb67b4481c9d8b462b0c534286f417e98067cd769b04e6f224f6fd`.
3. `analysis/NSE_COHERENT_IMPLEMENTATION_PLAN_V2_001.md`, B04, source precedence,
   storage/evidence/retry boundaries and conflict ledger C027/C028/C041.
   SHA-256: `e61c22ce66ab42418486e81a02f89572eff175600792bc7c59ec112ac6423f16`.
4. Current source at the fresh base: integration architecture, B01/B02/B03
   helpers/workers/migrations/tests, manifest, dispatcher, repository instructions
   and implementation/database security skills.

No older recovered analysis was needed. The environment credential file was not
read. The task's supplied historical finding is retained as a limitation:
requests 43–51 were not successfully characterized. No historical B01/B02/B03
success/no-record diagnostic exception is evidence for B04.

The [Supabase changelog](https://supabase.com/changelog/postgres-15-19-17-11-breaking-changes)
and [database-function guidance](https://supabase.com/docs/guides/database/functions)
were also consulted for infrastructure mechanics. B04 retains the existing AES256 evidence encryption
and empty definer search paths. No dependency, PostgreSQL-image or platform
upgrade is part of this batch.

## Nine endpoint contracts

All use POST, existing NSE authentication and JSON. The exact path for each
suffix below is `/nsemfdesk/api/v2/reports/<suffix>`. Local API keys omit `NSE_`;
external stable identities retain it. Each row was checked independently against
its own handbook table. Precedence describes the native contract, including
variants deliberately disabled in this candidate.

| Stable API / exact suffix | Pages / Postman | Native selector precedence | Date fallback |
| --- | --- | --- | --- |
| `NSE_SIP_REG_REPORT` / `SIP_REG_REPORT` | 164–166 / 43 | `sip_reg_id` > `member_unique_ids` > `client_code` > dates | 31 days |
| `NSE_SIP_CAN_REPORT` / `SIP_CAN_REPORT` | 166–168 / 44 | `sip_reg_id` > `client_code` > dates | 31 days |
| `NSE_SIP_INST_DUE_REPORT` / `SIP_INST_DUE_REPORT` | 168–169 / 45 | `sip_reg_id` > `client_code` > dates | 7 days, start cannot be past |
| `NSE_SIP_TOPUP_REPORT` / `SIP_TOPUP_REPORT` | 169–171 / 46 | `parent_sip_reg_id` > `client_code` > dates | 31 days |
| `NSE_STEPUP_REG_REPORT` / `STEPUP_REG_REPORT` | 171–173 / 47 | `sip_reg_id` > `client_code` > dates | 31 days |
| `NSE_XSIP_REG_REPORT` / `XSIP_REG_REPORT` | 173–175 / 48 | `xsip_reg_id` > `member_unique_ids` > `client_code` > dates | 31 days |
| `NSE_XSIP_CAN_REPORT` / `XSIP_CAN_REPORT` | 175–177 / 49 | `xsip_reg_id` > `client_code` > dates | 31 days |
| `NSE_XSIP_INST_DUE_REPORT` / `XSIP_INST_DUE_REPORT` | 176–178 / 50 | `xsip_reg_id` > `client_code` > dates | 7 days, start cannot be past |
| `NSE_XSIP_TOPUP_REPORT` / `XSIP_TOPUP_REPORT` | 178–180 / 51 | `parent_xsip_reg_id` > `client_code` > dates | 31 days |

All listed ID/UCC lists have native maximum 50. Top-up selectors are **parent**
IDs, not ordinary registration IDs. The registration reports explicitly add
`member_unique_ids` only when the primary registration selector is absent.
Cancellation, due, top-up and step-up request tables do not define that filter.
Step-up's date condition literally says "search by"; its two named selectors
are `sip_reg_id` and `client_code`. No extra search-by field or XSIP ID alias is
invented.

All request dates are real `DD-MM-YYYY` calendar dates. `to_date` must be strictly
greater than `from_date`; the documented gaps are implemented as maximum elapsed
days (31 or 7). Partial pairs, empty/null values, reversed/equal dates, impossible
calendar dates and overlong windows reject. The seven non-due endpoints do not
inherit the due endpoints' non-past rule.

Dates are conditionally mandatory when neither the named registration/parent
selector nor UCC is entered. Member-only registration queries still supply both
dates to satisfy that literal condition, even though the effective member
filter ignores other filters. Client queries may omit both dates; supplied pairs
are conservatively validated. **An effective UCC/member selector overrides dates;
B04 does not claim these dates narrow account/member report results.** Date-only
member-wide queries are disabled. Reads remain bounded by attempts, time, bytes
and row count, rather than a falsely asserted effective date range.

Due non-past checks use the India market day (`Asia/Kolkata`) as an explicit local
policy; the handbook does not specify a timezone. Preparation, source load and
REQUEST start check the current database day. The worker independently freezes
its invocation's India day from its injectable clock. Historical RESULT parsing
and summaries do not expire yesterday's valid evidence or repeat transport.
Tests fix the day and cover the 18:30 UTC India-midnight boundary.

## Supported owned selectors and blocked variants

The service-only RPC is:

```text
prepare_nse_sip_xsip_reports(workspace_id, integration_account_id, api,
  filters = {}, request_id = <local UUID>, selection = JSON null)
```

The default on **all nine** APIs is exactly the registered integration account's
UCC as `client_code`. It is derived from `integration_accounts`, never accepted
inside filters. The existing verified canonical PAN, active investor membership,
active workspace, registered NSE UAT account and unique UCC are rechecked before
transport. PAN is encrypted in the identity snapshot and never sent by B04.
Only optional `from_date`/`to_date` are accepted in filters.

For **SIP_REG_REPORT and XSIP_REG_REPORT only**, the caller can instead select
owned member references using local evidence positions:

```json
{"result_id":"<local RESULT UUID>","row_indices":[0],"selector":"member"}
```

This requires 1–50 distinct integer positions in a successful immutable
**account-scoped B04 registration report of the same endpoint**. SQL verifies
account/workspace, UAT, NSE integration, version NNF_1.9.7, endpoint/method,
read-only operation, latest successful RESULT and paired REQUEST. It decrypts
and revalidates the entire source response and confirms its requested UCC. A
member-selected source is disallowed to prevent recursive lineage chains.
Foreign/mixed/failed reports, REQUEST UUIDs, missing/out-of-range/duplicate
positions, wrong report family and unknown selectors reject.

Selected member references must be nonblank and unambiguous across the entire
source. The conservative local supported character slice is 1–100 ASCII letters,
digits, underscore or hyphen; 100 is a MoneyBowl bound, not an asserted handbook
VARCHAR size. All selected business fields must be nonblank. Selected registration IDs and member codes must be digit strings.
The snapshot retains registration ID/date, member reference/code, RTA scheme,
frequency, start/end and installment amount. Returned member-selected rows must
match all these business fields exactly. Positive responses must cover every
selected registration exactly once; an empty observation is separately allowed.
Changed schedule details fail interpretation and require review, not normalization.

Only `member_unique_ids` plus the required dates are emitted for that slice.
Ignored UCC or primary registration filters cannot override its ownership.
All variants below remain disabled:

- Raw caller UCC, SIP/XSIP registration ID, parent ID or member ID, including blank
  extra selector fields; all filters use a closed allowlist.
- Primary registration-ID selections for any endpoint. Although B04 now retains
  registration evidence, cross-report matching needs an explicitly reviewed
  selector and response correlation contract before enabling these variants.
- Parent-ID selections: an ordinary registration ID is not trusted parent/child
  lineage. Step-up ID variants also need explicit SIP/XSIP type correlation.
- Member filters for the seven endpoints whose tables do not define them.
- Multi-account/UCC lists, date-only reads, arbitrary provider URLs and broad
  member-wide fallback. No query automatically changes its selector after failure.

## Conflict resolutions and response interpretation

| Conflict | Resolution |
| --- | --- |
| C027 | SIP registration p165 explicitly defines max-50 `member_unique_ids`, subordinate to `sip_reg_id`; p166 returns `member_unique_id`. Old Postman #43 omits it. Implemented using owned same-endpoint evidence and exact registration/business correlation. |
| C028 | XSIP registration p173 independently defines the same member-filter precedence; p175 returns the reference. Old #48 omits it. Implemented independently with XSIP field names and owned XSIP evidence. |
| C041 | The rendered p165 visibly contains `reportXSIP Registration Report _data_total`. This is corrupt example text, not a supported wire key. The parser recognizes only `report_data_total`, the intact key in the other eight B04 examples. This is a conservative candidate interpretation, not proof of live SIP spelling; actual SIP total naming remains a commissioning gate. Any alternative/missing/extra total field fails closed with exact evidence retained. |

Each endpoint has a separate exact row-field list from its own example in both
TypeScript and SQL, with explicit endpoint builders/parsers. No alias union is
used. Every documented row field is required as a string; extra fields,
non-string values, missing fields and mixed/foreign UCCs fail the entire report.
A response cannot mix member codes. Digit-string registration identity is required.
Distinctive fields and multiplicity checks include:

| Endpoint | Distinct schema examples / duplicate identity |
| --- | --- |
| SIP registration | `sip_reg_number`, `sip_reg_date`, `sub_broker_code`, `euin`, `sub_broker_arn_code`, `member_unique_id`; duplicate registration number rejects |
| SIP cancellation | `sip_registration_no`, `sip_registration_date`, `sip_cancellation_date`, `sip_status`, `internal_ref_num`, `installments_amt`, `remark`; duplicate registration number rejects |
| SIP due | `sip_reg_number`, `reg_date`, `due_date`, `prev_paid_date`, `installment_amt`, `internal_ref_no`; duplicate registration/due-date pair rejects |
| SIP top-up | `reg_no`, `sip_xsip_amount`, `top_up_amount`, `principle_sip_reg_no`, `principle_sip_internal_ref_no`, `last_child_sip_reg_no`, `top_up_frequency/status`; duplicate top-up `reg_no` rejects |
| Step-up | `sip_xsip_regn_number/date`, `sip_xsip_type`, `stepup_start__effective_date` (two underscores), `stepup_enddate`, `stepup_frequency/amount`; duplicate registration/type/effective interval rejects |
| XSIP registration | `xsip_registration_no/date`, `brokerage`, `nse_mandate_id`, `sub_broker`, `euin_no`, `sub_broker_arn`, `member_unique_id`; duplicate registration number rejects |
| XSIP cancellation | `xsip_registration_no/date`, `xsip_cancellation_date`, `status`, `brokerage`, `nse_mandate_id`; duplicate registration number rejects |
| XSIP due | The example really uses `sip_reg_number`, plus `mandate_id`, `reg_date`, `due_date`, `prev_paid_date`; no `xsip_registration_no` alias. Duplicate registration/due-date pair rejects |
| XSIP top-up | Its own field list includes the same literal `principle_sip_reg_no` and child names as SIP top-up; no invented XSIP aliases. Duplicate top-up `reg_no` rejects |

Native row dates, amounts, remarks and status strings remain uninterpreted vendor
strings. For example SIP cancellation shows US timestamps, XSIP cancellation
slash dates, registration/due month-name dates, and top-up hyphenated month names.
They are neither converted to state nor promoted to proof of a cancellation,
paid installment or parent relationship. Row `remark`/`exchange_remark` fields
are retained as report data, distinct from undocumented envelope diagnostics.

All nine examples have `response_status`, count and `report_data`; they do **not**
define B03's `error_remark` envelope. Success requires exactly those three keys,
`response_status=S`, array data and a matching nonnegative integral number or
digit-string count, at most 10,000. An S/zero/empty array is only an observation
of zero returned rows. It does not prove absence of registration or cancellation.
Any `error_remark`, including an empty string or familiar "No record(s) found.",
is terminal `sip_xsip_reports_unknown_diagnostic`. Unknown keys, malformed JSON,
uncharacterized F responses and shape/count errors are terminal invalid evidence.
No undocumented F shape or success-diagnostic compatibility rule is enabled.

SQL reinterprets durable bytes independently. A worker/SQL disagreement becomes
terminal `sip_xsip_reports_interpretation_mismatch`; it cannot discard RESULT or
acknowledge success. Valid summaries expose only local UUIDs, API, timestamp,
count, native envelope status and normalized category, never provider rows or
sensitive identifiers, amounts, contacts or diagnostics.

## Infrastructure, security and retries

Migration `20261001220721_nse_b04_sip_xsip_reports.sql` is additive: 16 new functions
(seven service facades and nine private helpers), one partial unique event index,
one immutable-context trigger, and replacement of the existing dispatcher feed
function solely to recognize expired B04 read claims. No tables, columns, RLS
policies, browser grants or old migration edits. Existing dispatcher routes and
expired-claim families remain intact.

The service facades prepare, load, claim, recover, start, finish and summarize.
PUBLIC/anon/authenticated cannot call them; service_role cannot execute private
identity/decrypt/selector/parser helpers. Definers have empty search paths and
qualified references. Actual roles and catalog ACL/RLS are tested. The immutable
outbox holds local filters/selection references and an encrypted identity snapshot.
Account identity is rechecked before send; the snapshot governs historical results
after send. Deleting/changing retained context or interaction evidence is blocked.

`integration.nse.sip_xsip_reports_requested` routes to
`nse-sip-xsip-reports-worker` with `NSE_WORKER_TOKEN`. HTTP accepts only an exact
event UUID under shared internal bearer auth; no URL, API or provider selector
comes from HTTP. Existing NSE auth/config/client and `nse_evidence_call` are reused.
The worker performs one 30-second bounded read per attempt, rejects redirects and
caps the response at 1 MiB. REQUEST is serialized once, encrypted before send and
sent identically. Paired immutable REQUEST/RESULT evidence retains exact bytes,
SHA256, byte counts, safe headers, key/version, method/path, environment, call ID,
correlation/attempt and timestamps. BOM, malformed UTF-8 and NUL bytes use the
existing base64 transport and binary ciphertext path without losing evidence.
Oversize/incomplete reads retain truthful transport-failure evidence, not a claim
that an empty placeholder was the original body.

At most three claimed attempts; HTTP 408/429/500/502/503/504 and network/timeout
failures alone qualify for read retries. Claims enforce at least 30 seconds of
backoff, which the dispatcher may lengthen. Business/shape/foreign/unknown results,
nontransient HTTP, oversize/invalid responses and invalid requests do not retry.
Expired pre-REQUEST claims consume the budget. Orphaned REQUEST recovery creates
truthful empty transport-failure RESULT evidence; it never proves NOT_SENT.
Acknowledgement/persistence retries reuse captured inputs and cannot repeat the
provider transport. No read outcome authorizes a provider write or a resend.

No transactions, portfolios, folio references, portfolio-folio links, order requests
or payment events are mutated. SQL tests install statement-level mutation guards
on these actual current-schema relations. Canonical schedules and systematic write
intent/lineage remain B12; parent/top-up/control domains are future work.

## Validation record

Before any implementation edit, the existing baseline passed: manifest validation,
21 Python manifest tests, 41 Deno fmt/check targets, **406 Deno tests / 19 suites**,
all **68 migrations**, generic dispatcher and UCC SQL, two passes each of
ORDER_STATUS/PROV/B01/B02/B03 SQL, 15 dispatcher pytest tests, docs validation,
27 frozen migrations, shell syntax and clean diff checks. B04 tests did not exist
and were not counted in that baseline.

The first fetch and Docker run needed sandbox network/socket access; both succeeded
with authorized escalation. An initial dispatcher pytest invocation from the root
failed collection because `dispatcher` was not importable there; the configured
service working directory passed. After adding the manifest paths, two Python
count assertions still expected 41 files/19 suites; they were updated to the exact
reviewed 48 files/21 suites, retaining the allowlist checks.

Commands, from the worktree root unless stated otherwise:

```bash
python3 scripts/nse_test_manifest_v1.py validate
python3 -B -m unittest discover -s scripts -p nse_test_manifest_v1_test.py -v
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 fmt
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 check
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 test
scripts/test_nse_order_status_sql.sh
# Working directory: services/outbox-dispatcher
/tmp/moneybowl-prov-test-env/bin/python -B -m pytest
# Worktree root again
python3 .github/scripts/validate_docs.py
python3 .github/scripts/validate_migration_history.py
bash -n scripts/test_nse_order_status_sql.sh
git diff --check
git diff --cached --check
# After the local conventional commit
python3 .github/scripts/validate_commits.py
git diff 0b4b1008f2707a301152fc658645c53eb14524e1..HEAD --check
```

Final observed local results (2026-10-01):

| Command | Result |
| --- | --- |
| NSE manifest `validate` | PASS |
| Python manifest unittest discovery | PASS, 21 tests |
| Protected runner `manifest-v1 fmt` | PASS, 48 files |
| Protected runner `manifest-v1 check` | PASS, 48 targets |
| Protected runner `manifest-v1 test` | PASS, 502 tests / 21 suites; 96 new B04 tests (41 contract, 55 worker) |
| Disposable PostgreSQL harness | PASS, all 69 migrations; generic/UCC once; ORDER_STATUS/PROV/B01/B02/B03/B04 twice; B04 2,355 successful assertions per pass; rollback cleanliness and container cleanup |
| Dispatcher pytest in service directory | PASS, 16 tests |
| Docs validator | PASS, 24 Markdown files |
| Migration-history validator | PASS, 27 frozen migrations unchanged |
| Shell syntax; working/index diff checks | PASS |
| Commit validator and fresh-base-to-HEAD diff check | PASS after local commit; repeated after recording these results |

The first B04 test pass had 492 Deno tests and 2,220 SQL assertions per pass;
review added complete worker persistence replay coverage for all nine APIs, actual
worker-clock due checks, all private-helper ACLs and exact invalid-report RESULT
retention assertions. The final counts above include those additions. No unresolved
implementation/test failure remains. The candidate diff was reviewed, including
all new schemas, selectors, source guards, parsers and tests. A mechanical
comparison confirmed the SQL claim/recover/start/finish/summary lifecycle matches
B03 after the family rename, and the feed change preserves B03 and all older routes.

The SQL harness rebuilds all migrations in a disposable, network-isolated PostgreSQL
17.6.1.155 container with no published port, synthetic fixtures/keys and cleanup.
It exercises the existing generic/UCC regressions and repeats ORDER_STATUS, PROV,
B01, B02, B03 and B04 twice with rollback cleanliness checks. This is the current
NSE migration/regression harness; no hosted reset, hosted lint/advisor or live NSE
request was used. The separately maintained unrelated product suites are not
claimed as executed by this harness.

## Remaining UAT and future commissioning

Every API needs individually authorized controlled UAT before operational use:
owned positive and empty reports; exact native row/envelope fields, count type,
SIP count spelling, content types and volume limits; literal success/failure/no-record
diagnostics kept privately; selector precedence and ignored-date behavior; due
boundary/timezone and 7-day interpretation; 31-day boundaries for each other API;
and actual member reference business correlation on both registration endpoints.

Unknown shapes/diagnostics stay terminal with exact evidence. Any compatibility
exception needs endpoint-specific retained evidence and a separately reviewed
change. Registration, cancellation, due, top-up and step-up observations are not
proofs of write intent/effective state. Before any future writes, build B12's
canonical schedule/owned lineage and frozen intent, parent/child relationships,
positive endpoint-specific matchers, correction ordering and deduplication.
Empty cancellation data must never authorize a cancellation resend.

This work does not push, create a PR, merge, deploy, mutate hosted Supabase, call
NSE UAT, touch main/Production or rotate secrets. The committed candidate is for
review only.

## Complete changed-file inventory

```text
docs/CHANGELOG.md
docs/architecture/NSE_SIP_XSIP_REPORTS_VERTICAL_SLICE.md
docs/architecture/SYSTEM_ARCHITECTURE.md
scripts/nse_test_manifest_v1_test.py
scripts/test_nse_order_status_sql.sh
services/outbox-dispatcher/README.md
services/outbox-dispatcher/routes.json
services/outbox-dispatcher/tests/test_dispatcher.py
supabase/config.toml
supabase/functions/_shared/nse/NSE_TEST_MANIFEST_V1.json
supabase/functions/_shared/nse/nse_sip_xsip_reports.ts
supabase/functions/_shared/nse/nse_sip_xsip_reports_test.ts
supabase/functions/nse-sip-xsip-reports-worker/adapters.ts
supabase/functions/nse-sip-xsip-reports-worker/handler.ts
supabase/functions/nse-sip-xsip-reports-worker/index.ts
supabase/functions/nse-sip-xsip-reports-worker/index_test.ts
supabase/functions/nse-sip-xsip-reports-worker/types.ts
supabase/migrations/20261001220721_nse_b04_sip_xsip_reports.sql
supabase/tests/nse_sip_xsip_reports_vertical_slice_test.sql
```
