# NSEInvest UCC vertical slice

Status: locally implemented and validated; not deployed; no CLIENTCOMMON183 call made. Formal contract: NSEMF API Details v1.9.7 (June 2026), endpoint POST /nsemfdesk/api/v2/registration/CLIENTCOMMON183. The older May 2025 Postman /CLIENTCOMMON path is recorded as a conflict; the formal v1.9.7 path wins.

## Scope and classification

The single implemented API is integration_key=NSE_INVEST, integration_environment=UAT, category=CLIENT, safety_class=WRITE_CLIENT, operation_type=UCC_REGISTRATION, api_key=CLIENTCOMMON183, contract_version=NNF_1.9.7. The mapper emits exactly one 175-field reg_details record.

Canonical MoneyBowl tables may represent minor and non-individual investors. This first mapper deliberately supports only adult, individual, resident, single-holder, physical, one verified bank, non-PAN-exempt, verified KYC, nomination-opt-out profiles. Unsupported variants fail local validation before REQUEST evidence or transport.

## Flow

    canonical MoneyBowl data
      workspaces / memberships / profiles / profile_pan_records
      investor_registration_profiles / investor_addresses / investor_bank_accounts
             |
             v
    prepare_nse_ucc_registration + integration operation
             | transactional
             v
    integration.nse.ucc_registration_requested in event_outbox
             | claim token + lease + SKIP LOCKED
             v
    database source projection -> CLIENTCOMMON183 mapper/NNF validation
             |
             v
    immutable encrypted REQUEST interaction
             |
             v
    existing NseClient transport (one call)
             |
             v
    immutable encrypted RESULT interaction
             |
             v
    distributor -> integration_operations + integration_accounts
             |
             +-----------------------------+
             |                             |
             v                             v
    SUCCESS / REG_SUCCESS         RECONCILIATION_REQUIRED
             |                             |
             +-------------+---------------+
                           v
    Client Master READ (explicit verification purpose)
             |
             v
    immutable read REQUEST/RESULT evidence
             |
             +-> post-success local verification metadata
             +-> ambiguous-write reconciliation on exact identity match

## Tables

| Table | Responsibility |
| --- | --- |
| investor_registration_profiles | Canonical legal/onboarding/KYC/holding semantics missing from profiles. It supports individuals and non-individuals and does not impose the first-slice adult rule. |
| investor_addresses | Canonical current domestic/foreign addresses. |
| investor_bank_accounts | Canonical verified bank relationships with Vault-backed account-number encryption, keyed lookup HMAC, masks, and encryption/HMAC key reference/version. |
| integration_accounts | Current workspace/investor/integration identity. For NSE, external_account_id is the client_code/UCC. It contains no duplicated PAN, address, contact, or bank data. |
| integration_operations | Current logical lifecycle and normalized business/reconciliation state. It does not contain historical HTTP evidence. |
| integration_api_interactions | Generic immutable REQUEST/RESULT API evidence for NSE and future outbound integrations. No UCC response table exists. |

Existing workspaces, workspace_memberships, profiles, profile_pan_records, and event_outbox are reused. Advisor/EUIN and order tables are not required by CLIENTCOMMON183. No nominee table is created because this slice opts out.

## Source mapping

| CLIENTCOMMON183 field(s) | MoneyBowl source |
| --- | --- |
| client_code | integration_accounts.integration_metadata.external_account_candidate; becomes external_account_id only after correlated success. |
| holder names, DOB, gender, holding | investor_registration_profiles business fields. |
| tax_status, occupation_code | canonical residency/occupation plus controlled integration_metadata.nse_codes mapping. |
| PAN/exemption | profile_pan_records canonical encrypted PAN plus investor_registration_profiles.pan_exempt. |
| client_type | first-slice mapper policy P (Physical); canonical model is not restricted to physical. |
| bank type/account/MICR/IFSC/cheque name | one active verified default investor_bank_accounts row; account number decrypted only inside the service source projection. |
| address/city/pincode | current domestic investor_addresses row. |
| NSE state/country | canonical region/country plus controlled integration_metadata.nse_codes mapping. |
| email/mobile | profiles. |
| communication, KYC/CKYC, paperless, declaration ownership, nomination choice | investor_registration_profiles plus controlled NSE declaration codes. |
| div_pay_mode | controlled integration_metadata.nse_codes. |
| other banks, joint holders, guardian, demat, foreign address, nominees | present in the 175-field record as blank because their conditions are absent. |

The source RPC exposes plaintext sensitive business values only to service-owned assembly. No source projection is stored in the outbox or logs. The permanent mapper never reads private fixture JSON or documentation sample identities.

## Validation

The mapper validates every populated field against NNF requiredness/conditionality, type/length, documented format, and enums where specified. This includes first/middle/last names, valid DD/MM/YYYY adult DOB, PAN, bank/account/IFSC/MICR, cheque_name, address lines (safe 40-character interpretation for the NNF address_2 discrepancy), city/state/pincode/country, email/mobile, communication mode, KYC/conditional CKYC, paperless and declaration flags, dividend mode, holding, physical mode, and nomination opt-out. Nonblank optional values are validated; unsupported variants produce field/code diagnostics without values.

## State machine

PREPARED -> QUEUED transactionally. QUEUED or retryable SUBMISSION_FAILED -> SUBMITTING only after immutable REQUEST evidence commits. SUBMITTING terminates as SUCCESS, VALIDATION_FAILED (local validation occurs before submission), BUSINESS_FAILED, HTTP_FAILED, terminal/retryable SUBMISSION_FAILED, or RECONCILIATION_REQUIRED.

- A genuine mapper contract error is VALIDATION_FAILED. A source/RPC infrastructure failure occurs before transport and remains recoverable under the bounded outbox policy; it does not permanently invalidate the investor.
- HTTP 200 + REG_FAILED is BUSINESS_FAILED.
- HTTP 400 and 403 are definitive HTTP_FAILED.
- HTTP 500/503 and other possibly mutating provider failures are RECONCILIATION_REQUIRED.
- A proven NOT_SENT failure on attempt 1 becomes SUBMISSION_FAILED with retry_allowed=true. Attempt 2 exhausts the budget and leaves retry_allowed=false.
- Safe retry start clears completed_at, native status/remark, and retry state; the account becomes REGISTRATION_PENDING.
- REG_SUCCESS requires a nonblank returned client_code exactly matching the submitted client_code. Mismatch preserves evidence and requires reconciliation without replacing the existing external_account_id.

## Evidence, encryption, and headers

A call has immutable REQUEST and RESULT rows sharing call_id. Identical replay with the same call_id returns the existing row; conflicting evidence fails. Therefore a lost start-RPC response does not duplicate REQUEST evidence, and temporary RESULT persistence failure retries the same evidence without another NSE call. A second external call uses a new call_id and adds history.

Exact business payloads are pgcrypto AES-256 encrypted with a Vault key. Each row stores payload_encryption_key_reference and payload_encryption_key_version so historical ciphertext remains attributable during controlled rotation. PAN uses the existing PAN key functions; bank account storage uses separate encryption and lookup-HMAC key references/versions. No general decryption RPC exists, RLS has no browser policies, and service-only RPCs own lifecycle mutation.

Safe header metadata is allowlisted: request content_type/user_agent/accept and response content_type/x_request_id/x_correlation_id. Arbitrary headers and Authorization, api-key/secret, encrypted-password, Cookie/Set-Cookie, access/session/refresh tokens are rejected. NSE member/credential context is not stored.

## Crash recovery and outbox

The existing event_outbox remains the only queue. Claiming uses FOR UPDATE SKIP LOCKED, fenced claim tokens, leases, retry counters, and max attempts. For CLIENTCOMMON183, an expired claim with no REQUEST evidence is proven NOT_SENT and becomes bounded retryable SUBMISSION_FAILED; an expired SUBMITTING claim with REQUEST but no RESULT receives immutable AMBIGUOUS evidence and becomes RECONCILIATION_REQUIRED.

Client Master is READ_ONLY and has separate truthful recovery. An expired QUEUED claim with no REQUEST is safely requeued within the bounded budget. An expired SUBMITTING read with REQUEST but no RESULT receives an immutable TRANSPORT_FAILURE RESULT that closes the abandoned call; a retry uses a new call_id and preserves the original pair. A timeout/network failure with no usable response is also TRANSPORT_FAILURE, not write-side ambiguity, and is safely retryable only while attempts remain.

## Response distribution

Exact raw response remains only in encrypted RESULT evidence. HTTP status/success, byte/hash/timing, native reg_status, sanitized remark category, outcome and failure flags are normalized on the interaction. integration_operations receives current native status, sanitized remark category, timing/retry/ambiguity state. Only a valid correlated REG_SUCCESS updates integration_accounts to REGISTERED, external_account_id, current_registration_status=REG_SUCCESS, and non-PII registration reference metadata. The CLIENTCOMMON183 RESULT identifier is stored as registration_result_interaction_id; it is registration evidence, not independent read verification.

## Read verification and reconciliation

Request 69, Client Master report (POST /nsemfdesk/api/v2/reports/client_master_report), is the minimum read-only verification path. It is represented as integration_key NSE_INVEST, category RECONCILIATION, safety_class READ_ONLY, operation_type UCC_VERIFICATION, api_key CLIENT_MASTER_REPORT, contract_version NNF_1.9.7. The same service-owned worker supports two explicit operation purposes and always requires a specific event_outbox_id:

- POST_REGISTRATION_VERIFICATION targets a successful UCC_REGISTRATION. An exact match writes non-PII CONFIRMED local verification metadata. A no-match records NOT_CONFIRMED but never reverses REGISTERED, SUCCESS, or the NSE-native REG_SUCCESS status.
- AMBIGUOUS_WRITE_RECONCILIATION targets RECONCILIATION_REQUIRED. Only exact read evidence can resolve the target to SUCCESS. A no-match leaves it unresolved and never schedules or submits another CLIENTCOMMON183 call.

The Client Master filter contains exactly client_code, PAN as an empty string, and blank from_date/to_date. PAN is not transmitted as an additional filter. Exact identity correlation is still mandatory: database-side inspection compares the returned client_code and returned PAN with the client_code and PAN in the encrypted original CLIENTCOMMON183 REQUEST evidence. A 2xx response alone is insufficient.

Local verification is distinct from NSE-native registration state. current_registration_status remains REG_SUCCESS. Non-PII integration_metadata.nse_registration stores registration_result_interaction_id and the latest Client Master verification operation/result IDs, purpose, local status, checked timestamp, and verified timestamp.

The generic invariant is ambiguous_outcome => reconciliation_required. Reconciliation can therefore also represent a known, non-ambiguous local-versus-integration discrepancy.

## Worker invocation and source failures

Both UCC workers require a valid JSON object with an explicit event_outbox_id. Malformed or missing input returns 400 and cannot claim another investor's event. Mapper contract failures become VALIDATION_FAILED; source/RPC infrastructure failures remain pre-request recoverable and do not permanently close a valid registration. CLIENTCOMMON183 is serialized once, recorded as immutable REQUEST evidence, and the exact same string is passed to NseClient with Accept and Content-Type application/json.

## Client-code collision protection

A partial unique expression index protects the normalized NSE_INVEST/UAT external_account_candidate within a workspace. The prepare RPC also provides a stable nse_ucc_candidate_collision error, while the index closes the concurrent race. Documentation sample client codes are never candidates.

## DEV prerequisites

Before one controlled write: review and apply the forward migration to hosted DEV only; provision versioned Vault keys; deploy the reviewed worker and coherent protected NSE credentials; load one purpose-approved synthetic profile with externally valid PAN/KYC/bank/contact values and approved NSE reference codes; collision-check the UCC candidate; then submit one outbox event/one record. Any ambiguity stops for reconciliation.
