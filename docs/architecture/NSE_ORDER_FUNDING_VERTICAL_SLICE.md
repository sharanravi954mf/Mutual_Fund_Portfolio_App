# NSE B02 order and funding observations

Local implementation for four scoped `NSE_INVEST` / `UAT` / `NNF_1.9.7` reads. This candidate makes no NSE calls, changes no hosted database and does not commission financial writes. All four APIs have an implemented account-scoped slice; unsupported selectors below fail closed.

## Authority and conflicts

Primary source: `/home/ubuntu/nse-uat-contract/docs/NSEMF_API_Details_V1.9.7.pdf`, including its change log. Printed and PDF page numbers coincide. Supporting sources: `NSEInvest API Realease_21-05-2025.postman_collection 2.json` and the environment's variable roles (no credentials copied). The current source base is fetched `origin/develop` at `b8245aa8e982ec550e73d29c96c64477550c1fb5`, including B01 and its ELOG diagnostic correction.

Recovered authority is under `analysis/NSE_INTEGRATION_ANALYSIS_V1_001_REVISION_001_RECOVERED_001/`: `02_NSE_API_CATALOG_V1.md`, `17_NSE_CONTRACT_CONFLICTS.md`, and `21_DECISION_LOG.md`. `NSE_COHERENT_IMPLEMENTATION_PLAN_V2_001.md` and its JSON companion define B02, B01 dependency, V2-01/V2-06 and the B11 financial-lineage boundary. The plan's older source SHA is not used as the implementation base.

| API | Primary authority | Supporting / historical evidence | Exact POST suffix after `/nsemfdesk/api/v2/reports/` |
| --- | --- | --- | --- |
| `NSE_ORDER_LIFECYCLE` | pp150–152 | Postman #40 “Order Lifecycle Report”; recovered C006 | `order_lifecycle` |
| `NSE_TRANSACTION_DETAIL` | pp152–157; added in v1.9.6, change log p281 | Absent from the older Postman collection and historical sweep | `TRANSACTION_DETAIL_REPORT` |
| `NSE_FUND_ORDER` | pp115–118; actual request field table p116 | Postman #33 “Member fund allocation order wise report other than PA”; plan V2-06 | `MEMBER_FUND_ALLOCATION/ORDER_WISE` |
| `NSE_FUND_AGE` | pp118–121 | Postman #34 “Agewise/Bankwise orders funds received report”; plan V2-01 | `MEMBER_FUND_ALLOCATION/AGE_WISE` |

C006 is resolved by the current handbook: lowercase lifecycle path wins over uppercase Postman; no case folding, redirect following or fallback request. The lifecycle sample supplies `Product_type` with a blank `product_id`, contradicting the conditional requirement in its table; the formal requirement wins. FUND_ORDER's `pg_bank_refno` is described as “order id” on p116 although its name and response refer to bank references. Neither Postman nor recovered evidence resolves this domain. That selector is disabled, including a blank field. The plan cites p115 for this concern; p115 is the endpoint and p116 the field definition.

TRANSACTION_DETAIL's optional PAN is labeled `Pan` in the p152 table and `pan` in the sample. Both spellings, and applicant-name queries, are outside this slice. They are unnecessary for the owned account/order selectors. No casing guess is transmitted.

Historical `analysis/live_uat/live_uat_results.json`, `live_response_schema_catalog.json` and `collection_vs_live_schema_diff.md` establish:

- #33 made one attempt and returned HTTP 400. No body, content type, business status or usable response schema was retained. This does not establish that the bank selector, dates, permissions or any particular field caused the failure. HTTP 400 stays terminal; no automatic variant probe is added.
- #34 returned HTTP 200, JSON, a string count, an empty array, success-like `response_status` and a nonempty string diagnostic. It establishes **only empty success**, not positive funding semantics or arbitrary success remarks.
- #40 was skipped for a missing safe client prerequisite. There is no lifecycle success-remark exception to derive from it.
- TRANSACTION_DETAIL has no endpoint-specific historical call in this older collection sweep.

These are historical findings, not evidence of current deployment or commissioning. No new provider call was used to implement this batch.

## Requests and supported selectors

Every request is POST JSON with the existing authentication/client, JSON Accept, redirect refusal, a 30-second timeout and a 1 MiB response limit. Public workers accept only an exact local `event_outbox_id`; service-only preparation accepts owned workspace/account UUIDs, the closed API name, date options and an optional opaque evidence selection. No caller UCC, PAN, member reference, bank reference, order ID or product ID is accepted.

The common local eligibility gate requires an active workspace, active investor membership, registered account with a unique NSE UAT UCC, and an owned verified canonical PAN. The PAN gate is a conservative MoneyBowl source requirement for this batch, not an additional vendor requirement for funding reports. PAN is sent by none of these four supported requests; it privately validates TRANSACTION_DETAIL rows. The existing single configured NSE member connection is reused; multi-member connection modeling remains outside this batch.

| API | Vendor definitions | Implemented request and limits |
| --- | --- | --- |
| Lifecycle | Required `from_date`,`to_date` in `DD-MM-YYYY`, product registration dates, maximum **seven-day gap**. Optional `client_code` up to 50. Optional **`Product_type`**: `PUR`, `RED`, `SWITCH`, `SIP`, `STP`, `SWP`, `MANDATE`, `SIP CANCEL`, `XSIP CANCEL`, `STP CANCEL`, `SWP CANCEL`. `product_id` accepts at most 50 order/registration IDs, is mandatory with a type, and when supplied overrides other inputs. | One trusted UCC plus required dates. Optional type/IDs are derived together from owned B01 TWO_FA RESULT rows, all of one type. Only `PUR`/`RED`/`SWITCH`/`SIP`/`STP`/`SWP` have that demonstrated lineage. Mandate and cancellation selectors remain unsupported; their rows can be privately observed under the owned UCC. Required date syntax/window remains enforced even when ignored by the effective ID selector. |
| Transaction detail | Required `from_date`,`to_date`, `DD-MM-YYYY`, seven-day gap; **three-day gap** for `LAST_ACTIVITY_DATE`. Optional `client_code` (20), `applicant_name`, PAN. Optional `order_id` up to 50 overrides all other filters. Optional `systematic_reg_id` up to 50 SIP/XSIP/STP/SWP registrations overrides other filters **only if order_id is absent**. Optional `date_type`: `REQUEST_DATE`, `ORDER_DATE`, `LAST_ACTIVITY_DATE`; default `REQUEST_DATE`. | Trusted UCC plus both dates and explicit default/exact enum. Optional singular `order_id` derives from owned ORDER_STATUS or PROV_ORDERS RESULT rows. No plural `order_ids` wire field. Systematic selector alone or together with order ID is rejected: existing evidence does not prove an endpoint-specific registration mapping for the full SIP/XSIP/STP/SWP domain. No ignored arbitrary registration IDs are sent. |
| Fund order | Required `from_date`,`to_date`, `DD-MM-YYYY`; **no maximum date gap is specified**. Optional `client_code` up to 50 and ambiguous `pg_bank_refno` up to 50. The example spans a year. | Exactly the two real ordered dates and trusted UCC. No invented seven/31-day restriction. `pg_bank_refno` is omitted and rejected as an option. Response volume/time and attempts remain bounded. |
| Fund age | Required `date`, `DD-MM-YYYY`. Optional `client_code` up to 50; `settlement_type` from settlement master, default lowercase `all`; `amc_code` and `scheme_code` from their masters. | Exactly one date, trusted UCC and `settlement_type:"all"`. Master-specific settlement/AMC/scheme variants are disabled until trusted reference ownership exists. No arbitrary scheme or member-wide fallback. |

Seven- and three-day gaps mean date differences, not inclusive-day counts borrowed from ORDER_STATUS. Unknown fields, invalid dates, reversed intervals, null/blank fields, padded/lowercase enums and caller identifiers fail closed. Optional date_type defaults only when absent; null/blank values are rejected locally. UCC syntax is conservatively limited to 1–20 ASCII letters/digits/underscore/hyphen, and selected IDs to nonblank ASCII letters/digits/underscore/hyphen; these are local supported-slice restrictions, not invented vendor length definitions.

`prepare_nse_order_funding(workspace_id, integration_account_id, api, filters, request_id?, selection?)` uses API names without `NSE_`. `selection` defaults to JSON null or is exactly `{result_id: localResultUuid, row_indices: [zeroBasedIndex, ...]}`. It accepts 1–50 distinct rows/identifiers from one successful immutable RESULT belonging to the same account/workspace. A REQUEST UUID, unsuccessful result, foreign account, mixed lifecycle types, out-of-range/duplicate index, unknown field, or unsupported source endpoint is rejected. The source report is revalidated using its own parser and retained REQUEST, before IDs are extracted. The selected identifiers are retained encrypted; only the opaque result UUID and row positions are plain context. TRANSACTION_DETAIL receives effective `order_id` only, so its documented precedence cannot be inverted by caller options.

## Endpoint-specific responses

Each sample has `response_status`, `report_data_total`, `report_data`, `error_remark`. Count accepts a digit string or nonnegative integer and must equal the array length; local row limit is 10,000, additionally constrained by response bytes. `S` with zero rows is a successful read, never proof of absence of a prior financial action. `F` is terminal and never produces observations. FUND_ORDER, FUND_AGE and TRANSACTION_DETAIL document `F` with blank report data; only zero-count/blank-data failures get the normalized business-failure category. Other contradictory F envelopes remain invalid failures. Lifecycle has only an S sample; any F fails without trusting accompanying rows.

For lifecycle, detail and fund order, successful `error_remark` must be the documented empty string. For FUND_AGE only, a nonempty string is accepted **when count is zero and data is an empty array**, normalized as `order_funding_empty_success_diagnostic`. Nonempty remarks with positive rows remain invalid. Missing/non-string remarks, unknown statuses, unusable counts and malformed JSON fail closed. Exact diagnostics remain encrypted in every case.

The handbook provides sample string columns without mandatory rules or exhaustive native status enums for every row. Each parser validates the following minimum supported shape and requires all present row values to be strings. Additional string columns remain evidence-only. Missing identity, a foreign/mixed row or invalid structural value fails the whole interpretation, with no partial trusted projection.

| API | Minimum row structure / scope | Interpretation boundary |
| --- | --- | --- |
| Lifecycle | `client_code`, `product_type`, `product_id`, `order_status`, `payment_status`, `reconciliation_status`; exact owned UCC, documented product type and nonblank product identifier. A selection additionally requires exact retained type and selected ID. | Native authentication/payment/reconciliation/mandate/refund strings remain private. One `(product_type,product_id)` per response; duplicate keys reject the whole response. No response date precedence is guessed from inconsistent example dates. |
| Transaction detail | `client_code`, `primary_holder_pan`, `product_type`, `product_id`, `sip_registration_no`, `order_status`, `payment_status`, `reconciliation_status`; exact UCC/PAN and selected order ID when supplied. | Native `product_type` is descriptive, e.g. `NORMAL PURCHASE`, not lifecycle's `PUR`. `sip_registration_no` is retained, not silently renamed to the request's broader `systematic_reg_id`. Duplicate `(product_type,product_id)` rejects the response. |
| Fund order | `clientcode`, `cfppgbankrefno`, `utrno`, `id`, `totalamount`, `totalallocatedamount`, `remainingamount`, `mappedorders`, `settledorders`, `allotmentorders`; exact UCC and nonblank reference/row identity. | No arithmetic, settlement, refund or mapped-order parsing. Sample p117 repeats `id` with different references, so no invented `id` uniqueness. Exact duplicate objects reject the response. |
| Fund age | `clientcode`, `orderno`, `date`, `schemecode`, `orderstatus`, `funds_received_status`; exact UCC, nonblank order/scheme and sample-supported `DD/MM/YYYY` date matching the requested date. | `I`/`C`, `INVALID`/`payment_not_initiated` are examples, not settled flags or exhaustive enums. Exact duplicate objects reject the response. Nonempty support follows the handbook conservatively and is uncharacterized in UAT. |

Unselected account queries establish account-owned observations, not canonical order linkage. Funding bank references, account numbers, names, folios, amounts, holder contacts/PANs and provider diagnostics are never logged, returned by summaries or written to ordinary observations/business tables. No native financial status is promoted to paid, settled, reconciled or invested.

## Lifecycle, schema and evidence

One `nse-order-funding-worker` explicitly dispatches the four builders/parsers. It reuses `NseClient`, authentication/configuration, the shared attempt-local evidence helper, and `NSE_WORKER_TOKEN`. Oracle routes `integration.nse.order_funding_requested` to this worker. Each event is claimed exactly once per attempt; no endpoint, scope, retry policy or token override comes from its HTTP caller.

The additive migration adds **no tables or columns**. It adds 13 B02 functions (seven service-only preparation/source/lifecycle/summary facades, six private helpers), one partial unique event index and one immutable-context trigger. It extends the existing dispatcher feed's expired-read predicate for `ORDER_FUNDING`. There are no new table grants, browser RPCs, RLS policies or secrets. All definers have empty search paths and qualified names. Browser roles, including platform admins, have no access to B02 source/evidence/summary facades.

One generic `ORDER_FUNDING` / `READ_ONLY` operation retains its explicit API key and TRANSACTION/PAYMENT category. The immutable event contains API, dates, owned PAN record reference, optional opaque selection, encryption-key reference and encrypted UCC/PAN/derived-selector snapshot. The insert guard independently binds this snapshot to trusted source/evidence. Before each REQUEST the current registered account, membership, canonical identity and selected evidence must still match. After transport, source changes cannot rebind or erase historical RESULT interpretation.

REQUEST is serialized once, persisted encrypted before transport and then sent identically. RESULT retains exact bounded bytes, including BOM, malformed UTF-8 and embedded NUL, using the demonstrated B01 base64 RPC transport. Base64 is not the encryption format: SQL decodes, validates the byte/text agreement and encrypts the original bytes. Valid UTF-8 uses existing text ciphertext; unrepresentable text uses pgcrypto binary ciphertext in the same column. Hash and byte length cover original bytes. Both phases preserve operation/account/workspace, correlation ID, unique call ID, attempt number, endpoint, method, key reference/version and timestamps. An exact evidence acknowledgement retry reuses captured inputs; conflicting replays reject. Prior attempts remain immutable.

Transport failure and HTTP 408/429/500/502/503/504 permit at most three claimed attempts. Every retry uses a new call ID. Other HTTP responses, native F, unknown successful diagnostics, malformed data and scope mismatches are terminal. Persistence acknowledgement retries never repeat provider transport. Expired claims before REQUEST consume their budget; orphaned REQUEST gets a truthful empty TRANSPORT_FAILURE result tagged `order_funding_read_lease_expired`. Oversize/incomplete transport uses the existing transport-failure convention; partial bytes are not represented as a complete provider report. Dispatcher delay remains unchanged.

The finish RPC independently validates the response against immutable request/context, atomically retains RESULT and updates lifecycle state. If JavaScript and PostgreSQL interpretations disagree (including numeric-precision or unsupported JSON shapes), it preserves the exact bytes and records terminal `order_funding_interpretation_mismatch`; the worker checks the persisted outcome before acknowledging success. This bounded B02 improvement prevents a parser disagreement from discarding RESULT evidence. `get_nse_order_funding_summary(workspace_id, integration_account_id, operation_id)` privately revalidates retained successful evidence and returns only count, normalized category, native envelope S, explicit API, local UUIDs and observation time. It returns no rows or financial statuses. Worker replies are `no-store` and contain only safe outcome/count. No order, transaction, ledger, bank, portfolio, holding, UCC or readiness table is updated.

## Validation and remaining commissioning gates

From the worktree, the configured offline toolchain and network-isolated disposable PostgreSQL harness run:

```bash
python3 scripts/nse_test_manifest_v1.py validate
python3 -B -m unittest discover -s scripts -p nse_test_manifest_v1_test.py -v
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 fmt
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 check
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 test
scripts/test_nse_order_status_sql.sh
# Working directory services/outbox-dispatcher; existing pinned test environment:
/tmp/moneybowl-prov-test-env/bin/python -B -m pytest
# Repository root:
python3 .github/scripts/validate_docs.py
python3 .github/scripts/validate_migration_history.py
python3 .github/scripts/validate_commits.py
bash -n scripts/test_nse_order_status_sql.sh
git diff --check
git diff b8245aa8e982ec550e73d29c96c64477550c1fb5..HEAD --check
```

Contract/worker tests cover all four paths, fields, selectors, casing, date windows, empty/nonempty/failure envelopes, diagnostic policy, counts, duplicate/mixed/foreign rows, byte preservation, evidence-before-send, acknowledgement loss, retry bounds and privacy. The SQL suite applies **every current migration** to the cached PostgreSQL 17.6.1.155 image, network disabled, no published ports and temporary data. It runs generic dispatcher and UCC regressions, then ORDER_STATUS, PROV_ORDERS, B01 and B02 twice, checks rollback cleanliness and removes the container. Synthetic test keys exist only within rolled-back fixtures. API-role/catalog checks, encrypted snapshots, real prior-report selector lineage, immutable attempt pairs and dispatcher expiry recovery are included. Compose is unchanged. Full base-to-HEAD review and clean local/canonical Git status are handoff requirements; test results are reported with the candidate.

Before using B02 as a prerequisite for financial writes, separately establish:

1. Authorized real UAT success/failure and owned nonempty rows for every endpoint, especially FUND_ORDER's unresolved HTTP 400 and FUND_AGE's unobserved positive rows. Characterize optional row fields, media types, real report volume, dates/timezones and any new diagnostic patterns without generalizing across endpoints.
2. Lifecycle exact lowercase route, product selectors, override behavior and required date rules; transaction order precedence, product-to-order correlation and three-day activity boundary. Blank/systematic/name/PAN variants remain unsupported pending precise contract/lineage decisions.
3. Vendor clarification of `pg_bank_refno` identifier domain, supported use and response correlation. No bank-reference variant may be enabled from its name alone.
4. Proven master/member/product/registration lineage for currently disabled variants, and B11's durable canonical order/financial linkage. A future distributor needs exact subject/order/attempt correlation, idempotent replay from immutable RESULT, endpoint-specific native state predicates and validated financial semantics. Report S, an empty result or a funding status string alone cannot authorize payment retry or financial-state mutation.
