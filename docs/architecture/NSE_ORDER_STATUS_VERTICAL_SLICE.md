# NSE ORDER_STATUS vertical slice

Locally implemented for `NSE_INVEST` / `UAT` / `NNF_1.9.7`. No deployment or live NSE call is part of this change. The operation identity is `TRANSACTION` / `READ_ONLY` / `ORDER_STATUS`; it has no UCC verification purpose or reconciliation target.

## Contract authority

Primary source: `NSEMF_API_Details_V1.9.7.pdf`, printed pp78–83, “Order Status Reports API”, available in `/home/ubuntu/nse-uat-contract/docs/`.

Supporting source: `/home/ubuntu/nse-uat-contract/NSEInvest API Realease_21-05-2025.postman_collection 2.json`, root request 21, “Order Status Report”. It specifies POST, the exact endpoint below, and the five mandatory request properties. It has no saved response examples.

Conflict resolution: `/home/ubuntu/nse-uat-contract/analysis/NSE_INTEGRATION_ANALYSIS_V1_001_REVISION_001_RECOVERED_001/`, especially `17_NSE_CONTRACT_CONFLICTS.md` C023/C032, `21_DECISION_LOG.md` D21, and `14_NSE_NEXT_ENGINEERING_CHANGE.md` NSE-T002. The explicit p78 restriction resolves the shared p79 example: ORDER_STATUS never sends `date_type`. The older collection omits the newer `member_unique_ids` filter; the handbook governs. The ORDER_STATUS response example on pp82–83 is used despite its inherited “Provisional Report” heading; it has `order_date`, whereas the PROV_ORDERS example has `request_date`. There is no unresolved implementation-blocking contract conflict.

Transport: `POST /nsemfdesk/api/v2/reports/ORDER_STATUS`, JSON, using the existing NSE configuration, authentication and client. The new gateway refuses redirects, uses a 30-second timeout and bounds responses to 1 MiB. Tests inject transport; they never contact NSE.

## Request

| Vendor field | Handbook contract (p78, names corroborated by p79/request 21) | MoneyBowl behavior |
| --- | --- | --- |
| `from_date`, `to_date` | Mandatory, `YYYY-MM-DD`, maximum seven-day range | Strict real dates; seven inclusive calendar dates, matching the p79 Nov 10–16 example; retained with ID filters |
| `trans_type` | Mandatory: `P`, `R`, `ALL` | Exact values |
| `order_type` | Mandatory: `ALL`, `NRM`, `SIP`, `XSP`, `STP` | Exact values |
| `sub_order_type` | Mandatory: `ALL`, `NRM`, `SPOR`, `SWH`, `STP` | Exact values |
| `client_code` | Optional VARCHAR(20) | Always supplied from the registered integration account; caller cannot supply it |
| `order_status` | Optional: `All`, `VALID`, `INVALID` | Preserve the documented capitalization; blank when omitted |
| `settlement_type` | Optional: `ALL`, `L0`, `L1`, `OTHERS` | Blank when omitted |
| `order_ids` | Optional comma-separated list, at most 50; overrides other filters | Only derived from prior successful evidence belonging to the account |
| `member_unique_ids` | Optional comma-separated list, at most 50; table VARCHAR(25); overrides other filters only without `order_ids` | Only derived from prior successful evidence; at most 25 characters per member ID |
| `date_type` | Available only for Provisional Order Report | Rejected and never emitted |

ID precedence does not waive required request syntax. Both TypeScript and SQL enforce the mandatory fields even for an ID refresh. Optional blank strings follow the p79 request example. Request enums are not reused as response-row enums.

## Response and observations

The p79 envelope defines mandatory `response_status` (`S`/`F`), `report_data_total`, `report_data`, and `error_remark`. The table describes a numeric count, while pp79/82 examples encode it as a decimal string: accept either a nonnegative integer or a digit string, requiring exact agreement with the array length. On `S`, `report_data` is an array and `error_remark` is blank. On `F`, `report_data` is blank and `error_remark` carries the provider error; that error remains only in encrypted evidence. Empty `S` arrays are successful reads with zero observations.

The ORDER_STATUS sample on pp82–83 contains these row keys:

```text
member_id, order_date, order_time, order_id, settlement_id, client_code,
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

Those examples do not establish per-column mandatory rules or a complete lifecycle enum. MoneyBowl therefore does not fabricate a typed settlement or order-completion model. Its acceptance checks require usable string `client_code`, `order_id`, and `order_status` to correlate the whole report. Every row must match the requested client and, when IDs are present, the effective ID selector. One foreign or malformed row invalidates the whole report; no partial observation is distributed. Unknown nonblank order statuses contribute only to `other_count` and remain raw only in encrypted evidence. JSON containing decoded NUL or unpaired UTF-16 surrogates is rejected by both classifiers because PostgreSQL cannot represent those strings.

HTTP success, envelope success, and order status are distinct. An `S` report containing `INVALID` orders is a successful read. Neither a zero-row result nor any order status reconciles a write, changes a MoneyBowl order, or permits resubmission. The database independently classifies the raw response and rejects a worker classification that disagrees.

Private observations contain only workspace/account/operation/evidence UUIDs, timestamp, and `record_count`, `valid_count`, `invalid_count`, `other_count`. Provider identifiers, names, amounts, contact/bank/folio details and free-form remarks never enter observations, outbox payloads, HTTP worker responses or logs.

## Service facade and ownership

All lifecycle/source/observation RPCs are executable only by `service_role`. Browser callers, including platform admins, family guests, operations users and advisors, cannot call them. Tables have RLS enabled, no policies and no direct API-role grants; mutation happens through the service RPCs. Definers use an empty search path.

`prepare_nse_order_status(workspace_id, integration_account_id, filters, request_id?, scope_result_id?, scope_rows?, id_filter?)` creates the operation, private non-PII query options and exactly one outbox event in one transaction. `request_id` is an optional local idempotency UUID. Repeating it with the same arguments returns the original operation; different arguments conflict. `filters` permits only the date and enum fields in the request table. Unknown keys, including arbitrary client codes and order IDs, are rejected.

The account must be registered for NSE UAT, belong to the given workspace, and have active investor membership in an active workspace. A client identity used by another integration account is rejected. Source assembly rechecks these requirements before REQUEST evidence can be recorded.

For a range report, omit all scope arguments. For an ID refresh, provide a previous successful ORDER_STATUS RESULT UUID, a one-dimensional array of 1–50 zero-based row indices, and exactly one `id_filter`: `order_ids` or `member_unique_ids`. The selected RESULT must have a successful private observation for the same account and workspace. The source RPC decrypts it, verifies every selected row's client, and derives the IDs in memory. Selection references are stored; raw IDs are not copied into query metadata. This provides ID-filtered reads without inventing an NSE order-ownership mapping that MoneyBowl does not yet have.

`get_nse_order_status_source` is service-only. `start_nse_order_status` compares the exact request JSON with the database-owned source before encrypting the same serialized bytes passed to transport. `get_nse_order_status_observation(workspace_id, integration_account_id, operation_id)` returns only the matching private summary. No raw-response/decryption RPC is exposed.

## Lifecycle and dispatch

The new worker requires a valid internal bearer token and explicit event UUID. It follows the existing claim-token, lease, `SKIP LOCKED` and single-call evidence conventions. REQUEST and RESULT persistence may each retry once with identical captured inputs; NSE transport is invoked once per claimed attempt. RESULT evidence, operation/outbox state and the private observation commit atomically. Existing UCC workers and their distribution behavior are unchanged.

Transport failures and HTTP 408/429/500/502/503/504 use bounded read retries, with a maximum of three claimed attempts. Other HTTP failures are terminal. Envelope failure, malformed content and scope mismatch are terminal business failures with encrypted evidence. An expired claim before REQUEST consumes an attempt and remains bounded, including an expired retry claim. An abandoned REQUEST gets one immutable `TRANSPORT_FAILURE` RESULT, followed by a fresh call ID on retry. It never becomes write-side ambiguity. The dispatch feed includes expired ORDER_STATUS retry claims so they cannot get stuck before their next REQUEST.

The reviewed route is `integration.nse.order_status_requested` → `nse-order-status-worker`. Its configured bearer-token reference is `NSE_ORDER_STATUS_WORKER_TOKEN`. No token or credential is created or changed here. Future activation requires configuring that token consistently on the worker and dispatcher before deploying the updated routes. No hosted configuration is changed by this implementation.

## Local validation

From the isolated worktree:

```bash
python3 scripts/nse_test_manifest_v1.py validate
python3 -B -m unittest discover -s scripts -p nse_test_manifest_v1_test.py -v
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 fmt
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 check
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 test
scripts/test_nse_order_status_sql.sh
git diff --check
```

The SQL runner creates a new container with `--network none`, no exposed ports and temporary database storage; applies standard missing Auth/Storage platform definitions and every repository migration; runs the existing generic dispatcher and NSE UCC regressions and the ORDER_STATUS regression twice; explicitly verifies rollback; then removes the container. No application tables, constraints or triggers are stubbed or disabled. The existing UCC test now supplies its own missing synthetic PAN keys inside its rollback transaction. The platform fixture is needed because the cached bare Postgres image does not run the separate GoTrue/Storage services' schema upgrades.

Deterministic tests cover exact request syntax, enums, date and ID limits, precedence, counts, malformed/empty/failed reports, ID/account/workspace rejection, API-role privileges, immutable encrypted bytes, idempotency/conflicts, one transport call, HTTP retry classification, exhausted attempts, expired claim recovery and dispatch discovery. Dispatcher tests include the actual checked-in ORDER_STATUS route.
