# NSE B01 client readiness reports

Local candidate for all six B01 account-scoped read slices, `NSE_INVEST` / `UAT` / `NNF_1.9.7`. No provider call, hosted migration, deployment or commissioning is part of this change. No entire API is blocked; unsupported selectors below fail closed.

## Authority and contract decisions

The primary source is `/home/ubuntu/nse-uat-contract/docs/NSEMF_API_Details_V1.9.7.pdf`. Printed and PDF page numbers coincide. Supporting sources are the actual `NSEInvest API Realease_21-05-2025.postman_collection 2.json` requests and `uat-nsemf.postman_environment.json` in that directory. The environment was inspected for variable roles only; no credential value was copied.

Recovered sources under `analysis/NSE_INTEGRATION_ANALYSIS_V1_001_REVISION_001_RECOVERED_001/`: `02_NSE_API_CATALOG_V1.md`, `03_NSE_API_CATALOG_V1.json`, `17_NSE_CONTRACT_CONFLICTS.md`, `21_DECISION_LOG.md`, `07_NSE_OPERATION_SAFETY_MATRIX.md`, and `09_NSE_GENERIC_EXECUTOR_ARCHITECTURE.md`. The current coherent Markdown/JSON plan's B01, storage/evidence rules and V2-02/V2-03 decisions govern the batch design; current source governs reuse.

| Stable API | Handbook / Postman traversal ordinal | Exact POST suffix after `/nsemfdesk/api/v2/reports/` | Resolution |
| --- | --- | --- | --- |
| NSE_CLIENT_AUTHORIZATION | pp142–145; #39 “Client Authorization report” | `client_authorization` | C005: lowercase handbook route, no uppercase fallback. C032: its own date selector, independent of order reports. |
| NSE_CLIENT_DETAIL | pp145–150, request table p146; absent from Postman | `CLIENT_DETAIL_REPORT` | V2-03: explicit `MODIFIED_DATE` from enum. Reject padded `MODIFIED _DATE` default prose. The plan cites p145; the actual field table is p146. |
| NSE_TWO_FA | pp141–142; #38 “2FA Report” | `2fa` | C004: lowercase route. C033: handbook `product_type`, not Postman's `Product_type`. Product variants remain disabled here. |
| NSE_CLIENT_KYC_REPORT | pp192–193; #59 “Client KYC Status Report API” | `CLIENT_KYC_REPORT` | V2-02: only trusted PAN; reject the handbook/Postman example combining PAN and client. Alternate requiredness remains unresolved. |
| NSE_FATCA_REPORT | pp157–160, request table p158; #41 “FATCA Report API” | `FATCA_REPORT` | Wrapped table label and sample establish `pan_pkern_no`; do not rename to `pan_pekrn_no`. PAN response column is separately `pan_rp`. |
| NSE_ELOG_REPORT | pp162–164; absent from Postman | `ELOG_UPLOAD_REPORT` | Separate report from the eLOG upload mutation and its path conflict C003. |

Existing historical `analysis/live_uat/live_uat_results.json`, `live_response_schema_catalog.json` and `collection_vs_live_schema_diff.md` record #38/#39/#41/#59 as **skipped**, with no observed schema or business outcome. There is no B01 evidence for the ORDER_STATUS/PROV_ORDERS nonempty-success diagnostic compatibility rule. These historical files do not commission this candidate.

## Endpoint-specific requests and supported scope

All six use existing NSE authentication/configuration/client, POST JSON, JSON Accept, refused redirects, 30-second timeout and 1 MiB response bound. All scope comes from the registered integration account and that investor's verified canonical PAN record, within an active workspace and active investor membership. An external UCC associated with another local NSE UAT account is rejected. The source loader checks PAN record ownership as well as canonical linkage; a foreign canonical pointer never grants scope.

| API | Complete vendor request fields and rules | Supported MoneyBowl request |
| --- | --- | --- |
| Authorization | Required `from_date`,`to_date`: `DD-MM-YYYY`, maximum **seven-day gap**. Optional `client_code`: up to 50 UCCs, overrides other filters. Optional `auth_status`: `PENDING`/`AUTHORIZE`/`REVIEW`. Optional `date_type`: `AUTH_SENT_DATE`/`AUTH_DONE_DATE`, defaults to `AUTH_SENT_DATE`. | One trusted `client_code`, both required real dates, explicit default `date_type`; `auth_status` emitted only when supplied. Dates remain syntactically required even though the UCC overrides filters. |
| Detail | Required `from_date`,`to_date`: `DD-MM-YYYY`, seven-day gap. Optional `client_code`: up to 50, overrides other filters. Optional `auth_status`: same three documented request values. Optional `date_type`: `AUTH_SENT_DATE`/`AUTH_DONE_DATE`/`MODIFIED_DATE`. | One trusted UCC, both required dates, explicit `MODIFIED_DATE` default or exact supported alternative; optional exact-case `auth_status`. |
| TWO_FA | Optional `product_type`: `PUR`/`RED`/`SWITCH`/`SIP`/`STP`/`SWP`. `product_id`: comma-separated maximum 50 order/registration IDs, mandatory when type supplied, overrides other inputs when entered. Required `from_date`,`to_date`: product registration dates, `DD-MM-YYYY`, seven-day gap. Optional `client_code`: up to 50. | Trusted UCC plus required dates. Neither product field is emitted. Product selection, including arbitrary IDs or a type with blank ID, is rejected: current MoneyBowl has no proven product lineage for this API. The vendor sample violates its conditional rule and is not copied. |
| KYC | `pan_no` marked mandatory, up to 50, PAN-only overrides other inputs. Optional `client_code`, up to 50, mutually exclusive with PAN, client-only overrides others. Conditional dates if neither selector, client creation dates, `DD-MM-YYYY`, seven-day gap. | Exactly `{pan_no: trustedPan}`. No UCC/date-only query; the internal requiredness contradiction is isolated to those variants. No caller PAN accepted. |
| FATCA | Optional `pan_pkern_no`: up to 50 PAN/PKERN identifiers; overrides other inputs. Dates conditional when no identifier, `DD-MM-YYYY`, maximum 31-day gap. | Exactly `{pan_pkern_no: trustedPan}`. PKERN and date-only/member-wide variants disabled. No ignored date fields emitted. |
| ELOG | Optional `client_code`: up to 50, overrides other inputs. Dates required when no UCC, `DD-MM-YYYY`, maximum 31-day gap. | Exactly `{client_code: trustedUcc}`. Date-only/member-wide variants disabled. |

The first three sections explicitly show Jan 21–28, corroborating a seven-day difference (eight inclusive dates). They do not inherit ORDER_STATUS's seven-inclusive-date rule. Unsupported fields and null/blank/incorrect-case enums are rejected, not normalized. MoneyBowl's conservative UCC syntax is 1–20 ASCII letters/digits/underscore/hyphen; this is a local supported-slice constraint, not a claimed B01 vendor size table.

## Response contracts and interpretation

Each section shows `response_status:"S"`, `report_data_total` as a decimal string and `report_data` as an array. Accept a digit string or nonnegative safe integer count only when it equals array length, with a local maximum of 10,000 rows (also bounded by 1 MiB). Zero rows is a successful read. Do not treat zero rows as readiness or permission to write.

Authorization, Detail and TWO_FA samples include `error_remark:""`; require that exact successful shape. KYC, FATCA and ELOG samples omit `error_remark`; do not require it, but accept it only if blank when present. No endpoint accepts a nonempty successful diagnostic without its own characterization. The B01 sections do not define complete failure schemas; a native `F` is terminal business failure regardless of accompanying rows. No failure yields trusted rows. Unknown envelope statuses, malformed JSON, unusable counts and incompatible rows are terminal failures. Raw diagnostic text never becomes an operational category.

Row samples contain string fields, but do not specify mandatory rules or complete enums for every column. The implementation validates a minimum typed interpretation below; every present row value must be a string. Other string columns remain encrypted evidence only. Names, contact details, dates of birth, PAN/Aadhaar, bank/demat/folio identifiers, declarations, wealth/tax data and free-text remarks must not enter logs, response summaries or business tables.

| API | Minimum accepted row columns | Identity and native interpretation |
| --- | --- | --- |
| Authorization | `client_code`, `primary_holder_pan`, `auth_status`, `first_holder_auth_status` | Exact retained UCC and primary PAN. Sample `auth_status:"SUCCESS"` is a response value, not the request enum `AUTHORIZE`. Other native strings remain private, with no consent mapping. |
| Detail | `client_code`, `primary_holder_pan`, `auth_status`, `ucc_status`, `primary_holder_kyc_checked`, `primary_holder_kyc_status` | Exact UCC/PAN. Preserve `Inactive`, `-`, whitespace and independent KYC/RTA/upload statuses; never equate envelope S with readiness. |
| TWO_FA | `client_code`, `product_type`, `product_id`, `primary_holder_authentication_status` | Exact UCC; documented product type and nonblank bounded-by-body identifier syntax. Unrequested product IDs may be observed only under the owned UCC; they cannot be supplied as new selectors. Holder authentication strings are not promoted to consent. |
| KYC | `client_code`, `client_pan`, `holding_type`, `holder_name`, `holder_dob`, `kyc_status`, `status_remark` | Exact UCC and requested PAN. Blank client/PAN sample placeholders are not evidence of identity. A PAN report returning other UCCs fails the entire supported account slice. |
| FATCA | `pan_rp`, `pekrn`, `camsuploadstatus`, `camsresponsestatus`, `kfinuploadstatus`, `kfinresponsestatus` | Exact requested primary PAN. No UCC invented where the report provides none. Upload status and RTA response status are separate native strings, not investor verification. |
| ELOG | `client_code`, `pan`, `pan_type`, `elog_type`, `cams_status`, `kfin_status` | Exact UCC and primary PAN. Other-holder PAN rows are outside this slice and invalidate the response. `F` and `NSELM` are sample row values, not fabricated exhaustive enums. |

One malformed, foreign or duplicate row rejects the whole interpretation. Authorization/Detail/KYC allow one row for the owned client; TWO_FA identity is `(product_type,product_id)`. FATCA/ELOG reject exact duplicate rows while allowing distinct upload-history rows; they have no invented uniqueness key. JSON containing decoded NUL/lone UTF-16 surrogates is rejected before classification, matching PostgreSQL jsonb limits. The complete textual response is still encrypted as RESULT.

Controlled DEV UAT on 2026-10-01 established one endpoint-specific envelope exception: `ELOG_REPORT` returned `response_status=S`, `report_data_total="0"`, an empty `report_data` array, and a non-empty string `error_remark`. MoneyBowl therefore treats an ELOG success remark as diagnostic-only when the rest of the success envelope is structurally valid. The diagnostic remains only in encrypted RESULT evidence and is never projected to summaries/logs. Other B01 endpoints keep their existing stricter remark rules until endpoint-specific evidence says otherwise.

The sections also contain many optional/sample-only fields: Authorization's holder KYC/FATCA/AOF/eLOG/contact fields and five bank slots; Detail's separate CAMS/KFin upload/response/remark columns per holder/document; TWO_FA's holder contact/authentication datetime/reply-time fields; FATCA's tax residence/TIN/UBO/Aadhaar/wealth/declaration/creator/file fields; ELOG's upload/RTA response times/reasons. Do not reuse those spellings across APIs: examples include Authorization `third_holder_aof_elog_remakrs`, Detail `first_holder_eLog_exists`, FATCA `po_bir_inc ` (trailing space), and ELOG `cams_status`. The current interpretation neither renames nor distributes these fields.

## Durable architecture and authorization

`prepare_nse_client_readiness(workspace_id, integration_account_id, api, filters?, request_id?)` is service-only. The closed `api` values are the table's names without `NSE_`. Only the first three APIs accept date options; only Authorization/Detail accept their documented status/date-type options. All other filters are empty. Reusing a local request UUID with the same inputs is idempotent; changing inputs or owned identity conflicts.

One `CLIENT_READINESS` / `READ_ONLY` operation retains the explicit API key and endpoint-specific category. One `integration.nse.client_readiness_requested` event retains immutable filters, API, local PAN reference, and an **encrypted trusted UCC/PAN snapshot** with its existing encryption-key reference. The snapshot is necessary because canonical PAN records and account identity can change; an opaque reference alone would not preserve historical classification. It contains MoneyBowl source identity, not provider responses. The insert guard independently verifies snapshot identity against the owned source. Before each REQUEST, current registration/membership/canonical identity must still match the retained snapshot. After transport, source changes cannot erase or rebind RESULT history.

No tables or columns are added. The additive migration creates scoped functions, one partial unique outbox index and one immutable context trigger, and extends the existing dispatch feed's expired-read-claim predicate to B01. Finished contexts cannot be edited/deleted: retention must preserve both context and the existing evidence keys. Identity helpers/classifiers have no service/browser grants; the seven lifecycle/source/summary facades are service-only, with empty definer search paths. Browser personas, including platform admins, are denied. No new browser API, raw-response/decryption facade, RLS policy or direct table grant is introduced.

`nse-client-readiness-worker` accepts only an exact event UUID and the shared `NSE_WORKER_TOKEN`. It loads trusted API/source state, uses static typed dispatch, and refuses caller endpoint/filter/scope overrides. Oracle's existing router gains one route; its polling, dry-run default and token handling are unchanged. No six-token or six-worker expansion is needed.

## Evidence, retry and distribution boundary

Serialize once, persist the exact UTF-8 REQUEST string encrypted before transport, then send those identical bytes. The existing client provides one bounded call; the worker passes the exact bounded RESULT bytes through a base64 RPC argument, independently of text interpretation, including HTTP failures, business failures and malformed bodies. Base64 is transport encoding only: SQL encrypts the original bytes and hashes/counts those original bytes. Valid UTF-8 retains the existing text-ciphertext convention; invalid UTF-8 or literal NUL uses pgcrypto binary encryption in the same ciphertext column. A BOM is retained, never silently stripped. Byte/text disagreements are rejected before persistence; malformed encoding is a terminal failed interpretation with exact binary evidence. [PostgreSQL pgcrypto](https://www.postgresql.org/docs/current/pgcrypto.html) documents the binary encrypt/decrypt functions used by this bounded extension. Digests, byte lengths, key version/reference, operation/correlation/call IDs and attempt number are preserved. No request/response body is logged.

The worker computes an in-memory interpretation; the finish RPC independently validates it, then atomically retains RESULT and updates operation/outbox state. Repeating REQUEST/RESULT persistence after acknowledgement loss returns the same evidence for identical captured inputs; conflicting replay fails. Persistence retry never repeats provider transport. Existing evidence append-only triggers and phase-lineage guards remain authoritative.

Transport failure or HTTP 408/429/500/502/503/504 permits at most three claimed attempts. Each new attempt has a new call ID; old pairs remain. Other HTTP statuses, F, malformed reports or ownership mismatch are terminal. Dispatcher retry delay remains 30 seconds by default. Lease expiry before REQUEST consumes its claim budget; abandoned REQUEST gets a truthful encrypted empty `TRANSPORT_FAILURE` RESULT with `client_readiness_read_lease_expired`, not a fabricated original response. Oversize/incomplete transport follows the existing failure convention: no partial report projection or claim that an empty body is original provider evidence.

`get_nse_client_readiness_summary(workspace_id, integration_account_id, operation_id)` derives only the validated count/outcome/native envelope status, API, local UUIDs and observation timestamp from retained evidence and identity. It exposes no provider row or native holder/RTA status. Worker responses are `no-store` and contain only safe outcome/count. A successful report does not update registration, KYC, bank, consent or order tables.

A future distributor must define a specific readiness predicate, exact subject/product ownership, allowed native states, positive endpoint-specific UAT evidence and an idempotent replay/audit boundary using retained RESULT. There is no currently justified business destination for these reports, so this change deliberately stops at private summaries.

## Validation and commissioning boundary

The deterministic contract tests independently cover all six request paths, required fields, selectors, casing, dates, successful empty/nonempty shapes, native failure, malformed/foreign/duplicate rows, counts and PII exclusion. Worker/gateway tests cover authentication, evidence order, bounded transport, acknowledgement loss, transient/terminal HTTP and transport failures. The SQL suite exercises the real current migration sequence, grants/API roles, scope, snapshots, immutable bytes/hashes, idempotency/conflicts, retries/exhaustion, expiry discovery and rollback, alongside existing dispatcher/UCC/ORDER_STATUS/PROV_ORDERS regressions.

Commands from the worktree:

```bash
python3 scripts/nse_test_manifest_v1.py validate
python3 -B -m unittest discover -s scripts -p nse_test_manifest_v1_test.py -v
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 fmt
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 check
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 test
scripts/test_nse_order_status_sql.sh
# From services/outbox-dispatcher, with pinned requirements installed:
/tmp/moneybowl-prov-test-env/bin/python -B -m pytest
python3 .github/scripts/validate_docs.py
python3 .github/scripts/validate_migration_history.py
python3 .github/scripts/validate_commits.py
bash -n scripts/test_nse_order_status_sql.sh
git diff --check
```

The SQL runner uses the existing cached PostgreSQL 17.6.1.155 image with network disabled, no published ports and temporary data; it applies all migrations, runs UCC/dispatcher and repeats all three report suites, verifies rollback and removes the container. Synthetic keys exist only in rolled-back test transactions. No linked/hosted database is touched. Compose is unchanged.

Real UAT remains required separately for each endpoint before using its evidence as a write gate: owned nonempty rows, empty/failure envelopes and diagnostics, media type and real field optionality, casing, date/filter precedence, upload-history multiplicity and bounds. TWO_FA product variants need trusted product lineage and C033 characterization. KYC client/date-only alternatives need vendor clarification of p192. Joint/guardian/PAN-exempt/PKERN and member-wide queries remain outside this candidate. Current member credentials are reused; no member-connection/domain model is invented.
