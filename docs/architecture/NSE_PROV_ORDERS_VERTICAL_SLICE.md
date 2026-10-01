# NSE PROV_ORDERS vertical slice

Local candidate for `NSE_INVEST` / `UAT` / `NNF_1.9.7`, operation `TRANSACTION` / `READ_ONLY` / `PROV_ORDERS`. No live NSE call, deployment or hosted migration is part of this implementation.

## Contract authority

Read sources:

- `/home/ubuntu/nse-uat-contract/docs/NSEMF_API_Details_V1.9.7.pdf`: printed pp5–6 (authentication and origins), p78 (routes and request rules), p79 (request example and response envelope), pp79–82 (PROV_ORDERS example). The separate ORDER_STATUS example is on pp82–83.
- `/home/ubuntu/nse-uat-contract/NSEInvest API Realease_21-05-2025.postman_collection 2.json`: root request 20, “Provisional Report” (zero-based index 19). POST, exact route, JSON and the five mandatory fields; no saved response examples. Its omitted optional fields do not remove the handbook's current contract.
- `/home/ubuntu/nse-uat-contract/uat-nsemf.postman_environment.json`: UAT origin `https://nseinvestuat.nseindia.com` and existing authentication variable names. No environment value is copied into product code or tests.
- Recovered analysis directory `NSE_INTEGRATION_ANALYSIS_V1_001_REVISION_001_RECOVERED_001`: `02_NSE_API_CATALOG_V1.md` and `03_NSE_API_CATALOG_V1.json` entry NSE_PROV_ORDERS; `17_NSE_CONTRACT_CONFLICTS.md` C022/C032; `21_DECISION_LOG.md` D21; `07_NSE_OPERATION_SAFETY_MATRIX.md`; `08_NSE_RECONCILIATION_MATRIX.md`; `09_NSE_GENERIC_EXECUTOR_ARCHITECTURE.md`; `14_NSE_NEXT_ENGINEERING_CHANGE.md` T003. Historical standalone UAT metadata does not commission this implementation or establish every response variant.
- Existing safe UAT characterization in `/home/ubuntu/nse-uat-contract/analysis/live_uat/`, generated `2026-08-31T19:49:00.392Z`: `business_status_matrix.md` request 20; `live_uat_results.csv` / `live_uat_results.json` ordinal 20; `live_response_schema_catalog.json` ordinal 20; and `collection_vs_live_schema_diff.md` section “20. Provisional Report”. These independently establish PROV_ORDERS success with a nonempty diagnostic, as detailed below.

C022 resolves the older collection's omission of `member_unique_ids` in favor of the current handbook. C032/D21 apply `date_type` only to PROV_ORDERS. The shared example and the inherited “Provisional Report” heading on the ORDER_STATUS example do not collapse the contracts. No unresolved source contradiction blocks this implementation.

## Exact request

`POST /nsemfdesk/api/v2/reports/PROV_ORDERS`, `Content-Type: application/json`, existing NSE Basic authentication and member configuration. The adapter also selects JSON Accept, refuses redirects and uses the existing client with a 30-second timeout and 1 MiB response limit.

| Field | Vendor authority, p78 (names corroborated by p79) | MoneyBowl behavior |
| --- | --- | --- |
| `from_date`, `to_date` | Required `YYYY-MM-DD`, at most seven days | Real dates; seven inclusive calendar dates, following the Nov 10–16 example; required even with IDs |
| `trans_type` | Required `P`, `R`, `ALL` | Exact case and values |
| `order_type` | Required `ALL`, `NRM`, `SIP`, `XSP`, `STP` | Exact values |
| `sub_order_type` | Required `ALL`, `NRM`, `SPOR`, `SWH`, `STP` | Exact values |
| `client_code` | Optional VARCHAR(20) | Always supplied from the registered MoneyBowl integration account, never caller filters |
| `order_status` | Optional `All`, `VALID`, `INVALID` | Preserve mixed-case `All`; emit blank when absent |
| `settlement_type` | Optional `ALL`, `L0`, `L1`, `OTHERS` | Emit blank when absent |
| `order_ids` | Optional comma-separated maximum 50 IDs; overrides other filters | Derived only from selected rows in successful same-account PROV_ORDERS evidence |
| `member_unique_ids` | Optional comma-separated maximum 50 IDs; table VARCHAR(25); effective only without `order_ids` | At most 25 characters per ID; evidence-derived, never arbitrary caller IDs |
| `date_type` | Optional `REQUEST DATE` or `ORDER DATE`; null defaults to `REQUEST DATE`; provisional route only | Accept absent/null and explicitly emit `REQUEST DATE`; reject blank, other case or other values |

ID precedence does not waive documented mandatory syntax. MoneyBowl's service facade selects one effective ID filter at a time; the pure request validator and response classifier also verify the documented precedence when both lists are present. The client-code check on every returned row remains mandatory even when NSE ignores that filter due to IDs.

## Response contract and safe interpretation

The p79 envelope has mandatory `response_status` (`S`/`F`), `report_data_total`, `report_data` and `error_remark`. The count is a Number in the table and a decimal string in the examples: accept a nonnegative safe integer or digit string, and require exact agreement with the array length. An `S` response requires an array. An `F` response has blank `report_data` and a provider error remark; a coherent empty failure has count zero. Empty successful arrays are valid reads. `error_remark` remains a required string, but its nonempty content does not invalidate an otherwise valid `S` report.

The handbook p79 describes `error_remark` as blank on success. Existing endpoint-specific UAT evidence contradicts that detail: request 20 records HTTP 200, `EXECUTED_SUCCESS`, `response_status:success_like`, and `error_remark:nonempty_diagnostic`. The JSON/CSV record also records `application/json;charset=UTF-8`, 101 response bytes and one attempt. The schema catalog records a non-null string remark, string total, string status and an empty `report_data` array (`record_count: 0`). The collection diff lists the four envelope fields as live-only because the collection has no saved response example; it reports no type mismatches. MoneyBowl therefore treats success remarks as diagnostic text, retained only in encrypted RESULT evidence, while preserving `S`/`F`, structural, count and account/identifier checks. This resolution is supported by PROV_ORDERS evidence itself, not an inference from ORDER_STATUS.

The safe characterization explicitly persisted neither response values nor derived identifiers. Tests reconstruct the observed empty-success shape with handbook `S`, a synthetic string zero count and a synthetic nonempty diagnostic; they do not claim to reproduce the original literal status/count/message. Additional nonempty fixtures verify the same rule without weakening PII or scope validation. The forward correction migration replaces only the provisional classifier and preserves the original candidate migration as history.

The PROV_ORDERS sample rows on pp79–81 contain:

```text
member_id, request_date, order_time, order_id, settlement_id, client_code,
first_applicant_name, scheme_code, scheme_name, isin, transaction_type,
amount, quantity, transaction_mode, DP_Folio_No, folio_no, login_id,
order_status, order_remark, sip_reference_no, settlement_type, order_type,
sip_registration_no, sip_registration_date, sub_broker_code, euin_code,
euin_declaration_flag, all_units, dpc_flag, order_sub_type, first_order,
investment_type, member_remark, kyc_declaration_flag, min_redemption_flag,
sub_broker_arn_code, bank_ref_no, account_no, mobile_no, email, mandate_id,
second_holder_email, second_holder_mobile, third_holder_email,
third_holder_mobile, member_unique_id
```

These are illustrative columns, not per-column mandatory declarations. MoneyBowl requires usable string `client_code`, `order_id`, and `order_status` for whole-report correlation. An effective member-ID selector additionally requires a matching string `member_unique_id`. A malformed or foreign row rejects the entire report; counts are never partially distributed. Unknown nonblank row statuses count as `other_count` and remain encrypted. Request enum sets do not constrain response rows: the handbook's provisional rows include `order_type` SO/SI and `settlement_type` T3/T1. `request_date` is retained as received, never renamed to `order_date` or projected to a canonical execution date.

HTTP success, report success, and individual order validity are separate. A successful report containing INVALID orders is still a successful read. Neither VALID, INVALID, a provisional remark, nor zero records proves settlement, cancellation, failed submission or permission to resubmit an order.

Shared p78 request validation and p79 envelope/identity classification reuse the existing pure ORDER_STATUS helpers without changing them. Both routes have their own historical evidence supporting nonempty success diagnostics; neither parser includes the diagnostic in its safe observation. Route-specific request/date semantics remain distinct, and ORDER_STATUS behavior is unchanged. Both TypeScript and SQL reject JSON containing decoded NUL or unpaired surrogate strings, which PostgreSQL cannot represent. SQL independently checks the worker's outcome/category against encrypted-request scope before committing evidence and state.

## Storage choice and service facade

The inspected generic `integration_operations` has lifecycle, account scope and last-evidence linkage, but no request-options column. `event_outbox.payload` already provides durable JSON context and is private under the current RLS policy surface. Store only validated date/enum filters and local UUID/row-index references there. Do not store the provider request, client/order IDs, row data, remarks or counts in the outbox.

No new tables or columns are added. The additive migration introduces ten endpoint/helper functions, a partial unique index guaranteeing one provisional event per operation, and a trigger that validates and freezes that event's identity/context, including after completion. It rejects deletion, payload changes and conversion from another event type. State/lease updates remain available to the existing lifecycle. Referenced evidence is already append-only and cannot be deleted; the guard and source RPC enforce existence and same-account successful-result ownership. Thus UUID selection references remain durable without a second query table. This deliberately retains provisional events as durable request context; any future outbox-purge design must preserve or migrate that context.

`prepare_nse_prov_orders(workspace_id, integration_account_id, filters, request_id?, scope_result_id?, scope_rows?, id_filter?)` is service-role-only. It atomically creates the operation and its event. Repeating a local request UUID with exactly the same parameters is idempotent; changed parameters conflict. Every account must be registered for NSE UAT in the given active workspace with active investor membership. An external client identity shared by another account is rejected. Source assembly and REQUEST persistence recheck account scope.

Range reports omit all three scope arguments. ID refreshes supply a previous successful PROV_ORDERS RESULT UUID, 1–50 zero-based row indices, and `order_ids` or `member_unique_ids`. Source assembly decrypts those immutable rows and derives IDs in memory. Cross-account/workspace, wrong-phase, unsuccessful, out-of-range, null and multidimensional selections fail closed. ORDER_STATUS results are not silently accepted as provisional evidence.

`get_nse_prov_orders_summary(workspace_id, integration_account_id, operation_id)` is service-only and returns null for a missing, unsuccessful or differently scoped operation. For success, it reopens the paired encrypted REQUEST/RESULT, revalidates scope, and returns only local UUIDs, timestamp, fixed native/category flags and `record_count`, `valid_count`, `invalid_count`, `other_count`. No additional observation storage is needed. Browser roles, including platform admins, operations users, family guests and advisors, cannot invoke these lifecycle/source/summary RPCs. Helpers are not directly executable by service_role either. Definers use an empty search path and qualified database objects.

## Evidence and lifecycle

The route is `integration.nse.prov_orders_requested` → `nse-prov-orders-worker`. Its entrypoint uses only the existing shared `NSE_WORKER_TOKEN`, with no per-API secret or fallback. The worker requires an explicit event UUID and owns no arbitrary next-event or provider-identity input.

REQUEST evidence is encrypted with the existing payload-key reference before the single transport call. The database checks request JSON against its source projection; the exact serialized string, byte count and hash are retained in the generic immutable evidence ledger. The identical serialized string goes to NSE. RESULT retains the full bounded raw body encrypted, plus the existing safe communication metadata and normalized categories. Malformed JSON, failed envelopes and scope mismatches are retained as failed RESULT evidence, never as successful business data. Sensitive provider fields and free-form diagnostics do not enter public worker responses or ordinary logs.

RESULT evidence and operation/outbox transitions commit together. REQUEST/RESULT persistence can retry once using captured identical inputs; persistence acknowledgement loss never repeats transport. Claimed reads have at most three attempts. Transport failures and HTTP 408/429/500/502/503/504 are bounded read retries; other HTTP failures and unusable report content are terminal. An expired claim consumes its attempt even before REQUEST. An abandoned REQUEST receives one immutable empty TRANSPORT_FAILURE RESULT; a retry uses a new call ID. No read attempt becomes write ambiguity. The generic dispatcher feed is extended only to discover expired PROV_ORDERS retry claims, preserving ORDER_STATUS behavior.

Responses exceeding the existing adapter bound or failing during transport cannot supply a complete raw body; they receive truthful empty transport-failure evidence, with no partial report projection. Confirm the response bound against realistic report volume before commissioning.

## Business distribution

The safe current projection is the generic operation's outcome, fixed remark category and last RESULT reference, plus the service-only derived summary. The account remains registered and its UCC state is unchanged.

Current `order_requests` records contain business intent and approval state; transactions/folios contain investment and ingestion lineage. No current durable NSE order-ID/member-unique-ID-to-order mapping or reviewed PROV_ORDERS status-to-domain transition exists. Consequently this read cannot safely update those tables, including when a row has matching amounts or scheme codes. A later NSE NORMAL submission/distribution slice must bind its original request/operation to a MoneyBowl order, then use a specific distributor to match client, member/order identifiers, scheme, side, amount/units and provenance before any audited domain transition. Empty or incomplete matches remain unresolved. There is no generic JSON updater or speculative financial projection here.

## Local verification and remaining UAT

Run from the worktree:

```bash
python3 scripts/nse_test_manifest_v1.py validate
python3 -B -m unittest discover -s scripts -p nse_test_manifest_v1_test.py -v
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 fmt
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 check
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 test
scripts/test_nse_order_status_sql.sh
python3 .github/scripts/validate_docs.py
python3 .github/scripts/validate_commits.py
git diff --check
```

Dispatcher tests run from `services/outbox-dispatcher` using `python -B -m pytest` with the pinned `requirements-dev.txt` installed in a disposable environment. The manifest retains all existing targets and adds the provisional adapter/worker tests. All transport tests use injected fetch; the configured NSE runner uses its pinned offline toolchain.

The SQL runner builds a fresh temporary PostgreSQL container with `--network none`, no ports and temporary storage; applies the existing minimal Auth/Storage platform fixture and **every current MoneyBowl migration**; runs dispatcher/UCC regressions and both report regressions twice; verifies rollback; removes the container. Application tables, constraints and triggers are real and enabled. Synthetic encryption fixtures exist only inside rollback transactions. No hosted service is accessed.

Real UAT remains necessary for current endpoint permissions/authentication, nonempty response shapes, REQUEST DATE versus ORDER DATE behavior, date boundaries, both effective ID selectors/precedence, realistic response volume, and later exact order reconciliation. The historical empty-success diagnostic is covered locally; it does not establish every response variant or commission this candidate. This candidate does not establish vendor-side order completion or deployment readiness. No new NSE call was made to resolve the diagnostic discrepancy.
