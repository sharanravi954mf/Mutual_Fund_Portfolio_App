# B07 bank and mandate lifecycle

## Operational candidate — 2026-10-06

Base: `2819143d4dc064c39fed7e8ac0254fe2b3ade1b9`. Prior reviewed commit:
`afd0af732ae43ddb34409e1c00e1b2b06e3fbfdd` (preserved). This pass adds a local
implementation for approved B07 writes. **No write is UAT CONFIRMED.** The earlier
review-only model and its BLOCKED rows remain immutable and cannot authorize this
new lifecycle.

| API | Completion status | Actual NSE UAT outcome in this pass |
| --- | --- | --- |
| MANDATE_STATUS | IMPLEMENTED | NOT ATTEMPTED; existing bounded read preserved |
| MANDATE | BLOCKED — UAT inputs/characterization | NOT ATTEMPTED; zero provider calls |
| BANK_ADD | BLOCKED — designated additional test bank | NOT ATTEMPTED; zero provider calls |
| BANK_DEL | BLOCKED — designated safe created relationship | NOT ATTEMPTED; zero provider calls |

### Actual external prerequisites

The user authorized controlled B07 UAT mutations. That authorization is retained;
no further generic permission to mutate NSE UAT is needed. What is still missing
is the designated test-data/terms bundle. The retained local
`private/ucc_fixture.json` was inspected without printing its values: it declares
`environment=NSE_UAT`, `synthetic=true`, `status=PREPARED_NOT_SUBMITTED` and
`submission_allowed=false`. It is not the later registered fixture. Historical
Attempt #4 and Client Master reports identify successful DEV operations, but do
not designate an additional bank for this B07 exercise or supply approved mandate
amount/type/start/end dates. The agent requested those inputs; none was supplied
in this pass. No collection sample, placeholder, unrelated bank, or historical
provider success was substituted for that designation.

Read-only DEV inspection subsequently confirmed that historical registration
operation `9f879567-2be2-4509-9f76-ce7ac9e41857` remains SUCCESS and its integration
account remains REGISTERED/UAT. There is exactly one verified active owned bank:
savings, canonical default, MICR absent. The queries selected only opaque IDs,
state, booleans and counts; no raw UCC/PAN/account or credentials. They did not
create an NSE call or constitute fresh provider reconciliation. No additional
owned bank exists for the planned ADD→DEL exercise.

- BANK_ADD needs a designated existing UAT investor/integration account and a
  verified owned additional test bank, with an approved explicit default choice.
- BANK_DEL needs that controlled ADD's relationship, fresh positive non-default
  verification and the designation establishing that this isolated test
  relationship is safe to delete. It cannot target a pre-existing unrelated bank.
- MANDATE needs the designated UAT bank and approved amount/type/dates/processing
  provenance. Non-empty MICR remains blocked pending real NSE characterization
  of `micr_no` versus `micr_code`. The implemented subset omits optional MICR and
  requires the canonical MICR to be absent. `registration_date` is included only
  with an explicit MEMBER processing selection and an approved valid date; it is
  omitted for PROVIDER processing. Neither behavior is claimed UAT confirmed.

There is no remaining *schema-absence* blocker: the new authority model, workers,
write evidence and reconciliation are implemented locally. The external inputs
above still prevent a safe real provider call. No provider validation rejection,
success, or reconciliation evidence was fabricated to resolve a contract conflict.

### Synthetic UAT operator authority

The registered UAT fixture predates the current public-signup identity model and
has no end-user Auth identity. A later additive migration therefore provides one
private database-operator-only fixture path. It is limited to an existing
NSE_INVEST/UAT/REGISTERED account, active verified owned bank, active investor
membership and an unexpired uat_cases designation with exact UUID and SHA-256
binding. The helper is explicitly revoked from PUBLIC, anon, authenticated and
service_role; browser and workers cannot mint this authority. The frozen intent
records authority_mode=UAT_OPERATOR and no actor_user_id; normal investor
drafts/approvals remain unchanged.

This path is for controlled synthetic NSE UAT characterization only. It does not
stand in for production investor consent and does not relax the worker's exact
UAT-host check, evidence-before-transport rule or no-blind-write-retry policy.

### Durable authority and transport boundaries

Additive migration: `20261006105515_nse_b07_approved_write_intents.sql`.
`draft_nse_bank_mandate_write` accepts opaque workspace/account/bank IDs, action,
strict business terms and a stable request UUID. It derives UCC/account/IFSC/type
server-side, freezes the exact encrypted request and hash, and records investor,
actor auth/profile IDs, version and time. MANDATE gets one stable `MB`-prefixed
20-character member reference. Replays require identical scope/action/terms.

The owner can inspect `get_nse_bank_mandate_draft` (masked bank plus business
terms), then explicitly call `approve_nse_bank_mandate_write(id, version)`.
Approval is a separate immutable event binding the exact frozen request hash and
actor. `revoke_nse_bank_mandate_write` records immutable revocation before send.
Draft/approval/revocation produce sanitized audit events. Historical review
proposals are not used as approvals. Browser roles cannot prepare, claim, read
transport source, decrypt evidence, finish or reconcile operations.

A private operator-provisioned `uat_cases` record binds the bank/account to an
external designation UUID and SHA-256, owned Client Master/MANDATE_STATUS baseline
RESULT IDs and an expiry of at most one day. No case is pre-provisioned by the
migration and no client/service insert API is granted. Its designation must refer
to actual retained operator/test-data authority; synthetic SQL test designations
are never real UAT authority. Baselines must belong to the exact account/workspace,
be recent at designation, and contain the exact UCC with valid report envelopes.
Provider mandate rows referencing a deletion bank block deletion.

`prepare_nse_bank_mandate_write` is service-only. Preparation and REQUEST
persistence recheck approval/revocation, current investor link/membership, account
UAT state, unchanged frozen bank/UCC and the designated case. DEL additionally
requires this case's correlated native successful ADD receipt (a reconciled
ambiguous ADD is insufficient), exact original provider bank identity, and the
latest verification to be positive and within 15 minutes, explicit N/default
false, no prior deletion receipt, no approved mandate
for the bank, no canonical orders for that investor/workspace and no known
mutating transaction/payment/systematic operations for the integration account.
These conservative checks plus the isolated-test designation are the bounded UAT
policy; they are not a general production dependency inventory.

All writes use the existing integration tables/outbox, not a parallel job system.
The single finite `nse-bank-mandate-worker` handles three typed write events and
one B07 verification event. It accepts only `event_outbox_id`. Its NSE gateway
requires exactly `https://nseinvestuat.nseindia.com` and disables redirects.
Raw URLs, raw UCC/PAN/account substitutions and arbitrary API execution are absent.

Exact REQUEST text is encrypted before HTTP; exact RESULT bytes, including invalid
UTF-8, are encrypted before business projection. SQL independently interprets
captured responses. HTTP 200 alone is not success. For **writes**, only the narrow
pre-transport PROVEN_NOT_SENT path can retry (maximum three claims); provider HTTP
400/403 are terminal definitive failures matching the established UCC write
policy. MAYBE_SENT, unmatched responses and expiry after a write REQUEST become
RECONCILIATION_REQUIRED, with no resend. Expired REQUESTs receive an explicit
missing-result evidence record. Persistence
acknowledgement retries reuse bytes/IDs and never repeat HTTP. The separate
BANK_MANDATE_VERIFY operation is READ_ONLY/READ_BOUNDED: uncertain read transport
and HTTP 408/429/500/502/503/504 can retry up to the same three-attempt cap without
weakening the no-resend rule for writes. Responses expose
fixed categories only; `evidence_recorded` is not a provider success assertion.

### Reconciliation and provider relationships

Service-only `prepare_nse_bank_mandate_verification(write_id, request_id)` queues
an explicit read using frozen identity; verification is not a resend. The worker
persists the read evidence and invokes `reconcile_nse_bank_mandate_write`.

- MANDATE uses exact `memberMandateIds` and compares UCC/member reference, bank,
  amount, type, start/end and registration date when present. Native status alone
  never proves authority. Zero/multiple/foreign/mismatched rows remain unresolved.
- ADD uses the documented Client Master request and compares UCC plus numbered
  account/type/IFSC/MICR/default fields. A unique matching row records an immutable
  `bank_relationships` projection with write/read evidence IDs. It establishes a
  provider relationship observation, not bank payment eligibility. Canonical bank
  records are unchanged.
- DEL accepts only a correlated native `SUCCESS` response as the positive write
  receipt and appends `bank_deletion_receipts`. A subsequent Client Master read
  is retained, but no missing row resolves an ambiguous deletion. Such a write
  requires an external positive receipt/vendor resolution; no automatic resend
  or inference from absence is implemented.

Generic integration scope/transition guards were extended only for owned B07
verification and SQL-validated positive evidence. Existing UCC recovery rules,
including the HTTP-failure read-reopen transition, remain intact. Dispatcher
configuration includes the finite B07 routes; no configuration was deployed.

### Validation

- Focused B07 current-schema SQL: original read/review regressions plus approved
  intent, exact evidence, replay, role/ownership, revocation, substitution denial,
  ambiguous-write reconciliation, default/dependency deletion protection and
  missing-result recovery. PL/pgSQL lint and real concurrent write prepare/claim
  run in the isolated disposable container.
- Full NSE SQL regression harness: UCC/dispatcher, B01–B07, frontend, B06 concurrency.
- Protected manifest fmt/check: 85 files. Deno: 904 passing tests.
- Dispatcher pytest: 63 passing tests. Manifest tests: 21. Diagnostic policy: 1.
- Documentation, migration-history, commit-format and whitespace validators.

Final local checks: both SQL harnesses passed, including the B07 write race and
two B01–B06 regression passes; B07 PL/pgSQL lint had no findings. Protected Deno
fmt/check passed all 85 targets and all 904 tests passed. Dispatcher pytest passed
63 tests; manifest validation plus 21 tests and the diagnostic policy test passed.
Documentation validation passed 54 Markdown files; the 27 frozen migration-history
entries passed and all pre-existing migrations remained unchanged. Commit-format,
shell syntax and whitespace checks passed. During development, the full harness
caught the UCC HTTP-read reopen transition missing from an initial trigger copy;
the final migration preserves the later current definition and the rerun passed. Local
logs use `/tmp/b07-operational-*`; no sensitive request/response payloads are
included in this document. All SQL fixtures are synthetic and disposable. No
hosted Supabase schema/data mutation, Production/main change, push, PR, merge,
deployment, order, payment, SIP or real-money activity occurred. No ambiguous NSE
write was retried; no NSE write was attempted at all.

## Historical discovery at reviewed commit afd0af7

The sections below record the earlier review-only implementation and validation.
Their statements about missing workflow/schema and absent mutation routes describe
that reviewed commit, not the operational candidate above.

## Source decisions and unresolved contracts

Primary sources are the current MoneyBowl schema, NSE handbook v1.9.7 printed
pages 70–74 and 83–84, the 2025-05-21 Postman collection, and coherent plan V2
B07/C031. Collection examples were inspected as data, never executed.

| Contract | Exact path after `/nsemfdesk/api/` | Implementation status |
| --- | --- | --- |
| MANDATE_STATUS | `v2/reports/MANDATE_STATUS` | IMPLEMENTED |
| MANDATE | `v2/registration/product/MANDATE` | BLOCKED |
| BANK_ADD | `v2/registration/CLIENTBANKDTL` | BLOCKED |
| BANK_DEL | `v2/registration/CLIENTBANKDTL` | BLOCKED |

The following are unresolved prerequisites, not permission inferred from provider
acceptance or a new boolean supplied by a caller:

- **MANDATE:** page 72's field table names `micr_no`; page 73 and the collection
  use `micr_code`. The handbook is internally inconsistent. A non-empty MICR
  write needs vendor confirmation; omitting an optional MICR would only resolve
  that subset. The conditional `registration_date` also needs a trusted decision
  on whether the mandate was processed by the member. More fundamentally,
  current MoneyBowl bank verification and B01 observations do not prove mandate
  authority for a specific amount, term and account. No approved consent artifact
  or policy establishing this authority is present in the supplied sources.
- **ADD:** the request uses `bank_dtl`, `action_type: ADD`, `account_type`,
  `account_no`, `micr_no`, `ifsc_code`, `client_code`, and mandatory
  `default_bank_flag: Y/N`. The handbook's omitted flag in one example does not
  override its mandatory field table. Current canonical bank ownership does not
  establish specific bank-add consent or a complete provider bank relationship
  inventory. Existing B01 report observations are not permission to add a bank.
- **DEL:** the same documented endpoint uses `action_type: DEL`. Canonical
  `is_default` alone cannot prove provider default state, and current state lacks
  a complete bank dependency inventory covering mandates, orders and external
  active relationships. No negative-evidence or freshness rule establishes that
  a missing report row means safe deletion. Therefore every deletion remains
  blocked, even for an owned, verified, non-default bank.

A follow-up needs the consent source/approval policy and dependency evidence
contract, plus resolution of the mandate wire ambiguity. Do not convert these
proposals to approved intent by editing their state. A future additive model must
bind actual approval, complete frozen terms, evidence provenance and revocation
checks before enabling writes.

## Completion discovery gate — 2026-10-06

This pass completes the bounded discovery and block verification, not the three
provider writes. No transport builder, send route, approval flag or schema was
added. Fresh fetched `develop` and `origin/develop` both equalled
`2819143d4dc064c39fed7e8ac0254fe2b3ade1b9`; canonical develop was clean.

### Source precedence and provenance

The retained vendor inputs live in `/home/ubuntu/nse-uat-contract`, outside the
Git worktree. They were read as documents; no collection request, credential or
environment was executed. Reproducible input SHA-256 values:

| Input | SHA-256 |
| --- | --- |
| `docs/NSEMF_API_Details_V1.9.7.pdf` | `5c3c819d788e40ba28f8d2eb3a6b2faabc3a39c5e9bc658fa034cf4c26cc576a` |
| `NSEInvest API Realease_21-05-2025.postman_collection 2.json` | `9db36cfb4bfb67b4481c9d8b462b0c534286f417e98067cd769b04e6f224f6fd` |

The June 2026 v1.9.7 handbook's explicit field tables and changes take precedence
over the May 2025 collection. Examples corroborate casing but cannot waive a
mandatory field. An internal contradiction stays unresolved; no example becomes
vendor confirmation. The retained coherent plan V2, section B07 and C031, is a
planning source, not an NSE contract or investor consent artifact.

A public NSE-domain search on 2026-10-06 found the
[NSE v1.9.7 handbook](https://www.nseinvest.com/nsemfdesk/resources/upload/apidetails/NSEMF_API_Details_V1.9.7.pdf).
Targeted searches for later 1.9.8/1.9.9 material and the two write routes found no
new authoritative resolution. This does not establish that private/vendor
clarifications do not exist. No newer contract was supplied or adopted.

### Exact write contracts and unresolved fields (gate A/B)

All three calls are POST with common NSE authentication and JSON bodies. The
following describes source evidence, not executable request templates. A future
MoneyBowl write should contain one frozen record although NSE documents up to 50.

**MANDATE**, `/nsemfdesk/api/v2/registration/product/MANDATE`, pp72–74:
mandatory `reg_data` array. Each record has mandatory `client_code` (VARCHAR 10),
`amount` (DECIMAL 15,2, maximum debit), `mandate_type` (`X` physical/scan or `E`
eNACH), `account_no` (VARCHAR 40), `ac_type` (`SB/CB/NE/NO`, VARCHAR 2),
`ifsc_code` (VARCHAR 11), `start_date` and `end_date` (DD/MM/YYYY; start cannot be
past). Optional MICR is NUMERIC 9: the field table says `micr_no`, while the
handbook examples and retained collection say `micr_code`. No resolution was
found. Optional `member_mandate_no` is VARCHAR 20 and must be unique across all
mandate registrations when provided; it is not documented as an idempotency key
that makes retransmission safe. The current locally unique 20-character reference
is only a reserved proposal reference; member-wide collision handling across
other systems is still needed before enabling registration.

`registration_date` is conditionally mandatory when the member processed the
mandate, DD/MM/YYYY, not future and not after start. These date constraints are
known; the trusted source proving *member processed* and that processing date is
absent. Substituting today's date or omitting it by assumption is not supported.
The response is `reg_data[]` echoing terms plus `reg_id`, `reg_status`,
`reg_remark`; the documented example is `REG_SUCCESS`. The two retained collection
responses corroborate that shape, not an exhaustive native status vocabulary.
`reg_id` and the supplied member reference are reconciliation identifiers.

**BANK_ADD / BANK_DEL**, `/nsemfdesk/api/v2/registration/CLIENTBANKDTL`, pp70–71:
mandatory `bank_dtl` array. Mandatory record keys are `client_code` (VARCHAR 20),
`action_type` (`ADD` or `DEL`), `account_type` (Account Type Master, VARCHAR 2),
`account_no` (VARCHAR 40), `ifsc_code` (VARCHAR 11), and `default_bank_flag`
(`Y/N`, VARCHAR 1). `micr_no` is optional NUMERIC 9. JSON casing is corroborated by
the handbook examples and collection. The field table's Action Type size 2 is
inconsistent with both literal actions; the explicit ADD/DEL values are the
supported literals, not truncated values. The ADD example omits the mandatory
default flag; that omission is not permission to infer it. Canonical savings,
current, nre and nro map via the existing UCC account-type mapping to SB, CB, NE,
NO, but bank ownership cannot choose the default flag for an investor.

The response is `bank_dtl[]`, echoing client/action/account/type/MICR/IFSC plus
`status` and `error_remark`, with `SUCCESS`/`FAIL` examples. No per-write ID or
member request reference is documented; the collection retains no responses for
this endpoint. The response example does not echo the default flag. Correlation
therefore needs the frozen UCC/account/type/IFSC and action, with separate read
proof of default state; it cannot rely on a generated provider bank ID.

### Authority and exact ownership (gate C/D)

Inspection included the full migration sequence through this base, not only the
B07 foundation. The later
`20261003233928_authorization_workspace_containment.sql` replaces the review RPC:
it first locks workspace scope and checks `can_select_order_request`, then retains
the stricter exact-investor, active membership and verified-bank checks. The
current actor needs an active investor link under that containment model.

| Existing model | What it proves | Missing authority for these writes |
| --- | --- | --- |
| `investor_bank_accounts` and `set_investor_bank_account` in the UCC migration | Workspace/investor scope, encrypted account identity, verification and local default | No investor approval of provider ADD/DEL or debit amount/type/term; local default is not provider default |
| `investor_registration_profiles`, `integration_accounts` and UCC REQUEST/RESULT evidence | Registration source and provider UCC outcome | No later bank-change/debit instruction or mandate processing provenance |
| B01 readiness and authorization report evidence | Scoped provider observations | No local acceptance artifact binding exact mutation terms, default choice and revocation |
| `family_delegations`, investor links and folio grants | Limited access/identity authority for their own purposes | No bank mutation or mandate-debit authority |
| `order_requests` and order/funding/systematic observations | Order intent or bounded provider reports | No exhaustive bank dependency ledger or mandate instruction |
| `nse_bank_mandate.intents` | Immutable owner-requested BLOCKED review, encrypted bank/UCC snapshot, local member reference | No accepted terms, consent evidence/version or approval/revocation lifecycle |

For any future write, the bank and registered NSE account must share the exact
active workspace and investor; resolve the actor through `current_user_profile_id`
and live investor linkage/membership. Load canonical verified active bank and
owned unambiguous UCC server-side. Freeze the exact bank identity, account type,
IFSC/MICR decision and UCC alongside actual investor authority for the action.
MANDATE also needs maximum amount, type, dates and member-processing provenance;
ADD needs the explicit Y/N default choice; DEL needs the provider relationship and
dependency proof. A caller may supply opaque owned IDs, never raw PAN/UCC/account
substitutions. The current review snapshot does not satisfy these future terms.

### Delivery evidence and positive reconciliation (gate E/F)

Reuse UCC's operation/interaction/outbox lifecycle, claim leases and
`createNseEvidenceCall`. The following is the required future write policy; it is
not implemented for B07 mutations:

| Delivery classification | Evidence and permitted transition |
| --- | --- |
| PROVEN_NOT_SENT | Trusted pre-transport failure proving the gateway was not invoked, or its narrow validated pre-transmission failure (`NOT_SENT` / `PRE_TRANSMISSION_FAILURE` in UCC). Only this class may retry the same approved frozen terms and reference. Missing RESULT alone is not proof. |
| MAYBE_SENT | Gateway invoked and completion uncertain, timeout/network failure, lost acknowledgement or expired claim after REQUEST. Retain encrypted exact REQUEST and failure/recovery evidence; prohibit resend and mark RECONCILIATION_REQUIRED. |
| SENT_WITH_RESULT | Persist exact encrypted response bytes/status and correlate with the immutable REQUEST, call/attempt IDs, hashes, byte lengths and claim. This describes delivery, not business success or authority. Uncorrelatable/malformed results remain reconciliation-required. |
| RECONCILIATION_REQUIRED | Persist unresolved operation state and read evidence. Only sufficient positive endpoint-specific evidence can resolve it. Zero/multiple/mismatched rows cannot permit retry. |

Persist exact serialized REQUEST before transport. Retry persistence with the
same bytes/IDs; a RESULT acknowledgement retry must never invoke HTTP again.
Do not copy read retries onto writes or assume UCC-specific HTTP dispositions
apply to these endpoints without source evidence. Summaries, logs and audits
retain fixed categories and opaque IDs, not account/PAN/UCC or raw diagnostics.

- **MANDATE:** pp83–84 offer `MANDATE_STATUS` selectors `mandate_id`,
  `memberMandateIds` and owned `client_code`. Its documented row includes
  `mandateId`, `memberMandateId`, `clientCode`, `bankAccountNumber`, `amount`,
  `mandateType`, `startDate`, `endDate`, `registrationDate`, `memberCode` and
  `status`. This is a potential positive read for frozen principal terms, not
  status-only reconciliation. Account type/IFSC/MICR are not present in that
  example; exact identity sufficiency and normalization must be source-bound.
  No frozen approved terms or such reconciliation policy exists. The current
  read parser establishes scoped existence only and must remain unchanged.
- **BANK_ADD:** Client Master pp203–206 exposes numbered account/type/MICR/IFSC,
  default flags (`YES/NO` in report examples, distinct from request `Y/N`), bank
  status and modification dates. CLIENT_DETAIL/CLIENT_AUTHORIZATION are also
  candidate observations. An exact positive account row may demonstrate current
  relationship state, but none supplies this write's native request identifier
  or proves this particular ADD caused it. A baseline, exact default comparison,
  acceptable status semantics and freshness/completeness policy are missing.
  No automatic positive reconciliation is enabled by mere row presence.
- **BANK_DEL:** no documented positive deletion receipt/tombstone read was found.
  A missing bank row or empty/stale report is not proof of deletion or absence of
  dependencies. No complete inventory covers active mandates, orders, funding
  and external provider relationships. Every DEL remains blocked even when the
  canonical bank is verified, owned and locally non-default.

### Plan and disposition

1. Preserve the implemented status read and all three immutable blocked proposals.
2. Add per-write queue/evidence sentinels, replay coverage, worker input denial and
   dispatcher refusal tests; retain existing read/evidence/fencing regressions.
3. Run current-schema B01–B07 and protected manifests; document any fixture drift.
4. Enable no write until the missing authority model, vendor decisions and read
   sufficiency contracts above are supplied and tested in a separate change.

No migration is needed for this disposition. In particular, creating a consent
boolean or a schema named consent would not supply the missing investor artifact.

## Ownership and immutable local review proposals

`nse_bank_mandate.intents` is private, RLS enabled and denies all direct access to
anon, authenticated and service_role. Its only producer is
`request_nse_bank_mandate_review(workspace, integration_account, bank, action,
request_id)`, executable by authenticated users. It resolves `auth.uid()` with
`current_user_profile_id()`, requires the account's investor to be the actor,
and checks an active workspace and current investor membership. It loads a
verified active canonical bank in the exact same workspace and investor scope.
No caller account number, UCC, consent assertion or dependency flag is accepted.

Every proposal is permanently `BLOCKED`. Its owner, source IDs, action, timestamp
and reason are immutable. Its bank/UCC source snapshot is encrypted with the
existing integration payload key; canonical bank storage retains its existing
encryption/HMAC handling. ADD and DEL are separate actions. Default-bank DEL
proposals are rejected. Account and bank locks serialize duplicate checks;
request IDs support exact replay, while conflicting replay and a second proposal
for the same account/bank/action fail. Each new proposal atomically writes one
immutable workspace audit with no account number or provider diagnostic.

MANDATE proposals reserve a server-generated unique 20-character member
reference. This is an owned local reference, **not** proof that registration was
sent, a registered provider relationship, consent, or legal authority. No proposal
creates an integration mutation operation or outbox event. No canonical bank row
is updated by this batch.

## Read path and C031

`prepare_nse_mandate_status(workspace, integration_account, 'MANDATE_STATUS',
filters, request_id)` is service-only, matching the existing trusted NSE worker
boundary. It requires a registered UAT integration account, active investor
membership, verified owned canonical PAN, and an unambiguous owned UCC. Browser
roles cannot prepare, claim, decrypt, complete or summarize provider reads.

Supported filters are `{}` or `{"intent_id": "owned-mandate-proposal-uuid"}`.
The first builds exactly `{"client_code":"owned UCC"}`. The second resolves the
owned proposal and builds exactly `{"memberMandateIds":"owned reference"}`.
C031's exact case is preserved. Provider precedence is mandate ID, member IDs,
then UCC/date selectors; this slice emits only one selector, so no filter can
silently override a scoping filter. Arbitrary mandate IDs, raw member references,
comma-separated lists, member-wide dates and caller URLs are rejected.

The parser requires a well-formed S envelope, matching total, empty diagnostic,
and exactly one result with the exact owned `clientCode`. A member-reference
query also requires the exact `memberMandateId` and the bank account from the
encrypted proposal snapshot. Zero rows, duplicates, multiple rows, mismatched
ownership, invalid data and F results cannot establish a positive match. No
native status vocabulary is invented: status strings stay evidence-only.
`APPROVED`, UMRN and upload dates never promote a proposal to authority, document
receipt, payment eligibility or a canonical bank relationship.

The immutable encrypted event identity survives source changes after submission.
The SQL finisher independently classifies the stored request and actual response
bytes rather than trusting a worker's success claim. Request/result hashes,
byte lengths, exact binary evidence, claim fencing and idempotent acknowledgement
replay follow the existing NSE infrastructure. Summaries expose only fixed
categories, counts, operation/scope IDs and timestamps.

## Worker, dispatcher and retry

Worker: `nse-mandate-status-worker`, authenticated by shared `NSE_WORKER_TOKEN`.
Event: `integration.nse.mandate_status_requested`. Body: `event_outbox_id` only.
Routes are repository configuration; no deployment was performed. The existing
dispatcher SQL is extended solely to discover expired B07 read retry claims.
The B01–B06 routes and state handling are preserved.

READ_BOUNDED: at most three attempts; transport failures and HTTP
408/429/500/502/503/504 can retry. Other HTTP errors and invalid/native business
results terminate. An expired read claim closes missing RESULT evidence before
retry. The provider response cap is 1 MiB. Evidence acknowledgement retries
repeat persistence only, never transport within an attempt.

No mutation retry or automatic reconciliation is enabled. The required future
policy is WRITE_NOT_SENT_ONLY: only a proven pre-transmission failure can resend.
Any MAYBE_SENT, ambiguous response or missing result must persist reconciliation
required and prohibit resend. A zero/multiple status result cannot authorize a
retry. Even a unique status match would need frozen mandate amount/type/term and
ownership comparisons before it could resolve a future ambiguous registration.
This foundation intentionally never claims that it performs that reconciliation.

## Validation and local operation

Migration: `20261002184553_nse_b07_bank_mandate_foundation.sql`; no applied
migration changed. Run:

- `bash scripts/test_nse_bank_mandate_sql.sh`: all current migrations, focused
  ownership/ACL, contract, evidence, replay, fail-closed proposals, SQL lint and
  simultaneous owner replay/read preparation/exclusive claim tests.
- `bash scripts/test_nse_order_status_sql.sh`: existing NSE SQL regression harness,
  including B01–B06, dispatcher and frontend, now also running B07.
- Protected env-003 `nse-test-runner manifest-v1 fmt/check/test`: offline manifest
  validation, TypeScript checking and all NSE tests including B07.
- Dispatcher pytest suite, manifest validators and documentation validators.

SQL harnesses create network-isolated disposable PostgreSQL containers from a
cached image and apply the complete repository schema. They neither reset a
shared local database nor connect to hosted Supabase. Fixtures are synthetic.
Positive mutation transmission tests are intentionally absent because the write
contracts remain blocked; tests assert that no such mutation can be queued.

Foundation validation (historical): 867 NSE Deno tests passed (39 B07 tests), 81 fmt/check
targets passed, 56 dispatcher tests passed, 21 manifest tests and the diagnostic
policy test passed. Both focused B07 and the complete NSE current-schema SQL
harness passed; B07 PL/pgSQL lint reported no findings. B01–B06, existing UCC,
dispatcher, frontend and concurrency regressions passed. No UAT request, hosted
mutation, push, PR, merge, deployment, credential or live infrastructure change
was performed.

## Completion candidate validation — 2026-10-06

All required final checks passed locally. The candidate changes documentation and
regressions only; production SQL, TypeScript workers, dispatcher routing and every
existing migration are byte-identical to the fresh base. No migration was added.

The initial unchanged B07 test failed with `mandate_status_account_scope_invalid`:
its INSERT into `auth.users` no longer auto-created a profile after the
Explorer-only signup migration. The full harness also exposed the dispatcher
fixture's missing-profile foreign key. NSE and dispatcher fixtures now explicitly
provision their synthetic profiles as database owner, just as the current frontend
fixture does. B07 provisions explicit investor links too, and expects the newer
containment gate's exact `not_authorized` denial. No runtime trigger, grant,
constraint or assertion was disabled. Fixtures remain rollback-only (concurrency
fixtures commit only inside the disposable container).

| Check | Result |
| --- | --- |
| `bash scripts/test_nse_bank_mandate_sql.sh` | PASS: all migrations, existing B07 cases plus no-operation/event/evidence sentinels for all three proposals and their replays; no B07 PL/pgSQL lint findings; concurrent owner replay/read preparation/exclusive claim |
| `bash scripts/test_nse_order_status_sql.sh` | PASS: generic dispatcher and UCC; two rollback passes of ORDER_STATUS, PROV_ORDERS, B01–B07 and frontend; B06 reference/master/NAV/SET and frontend concurrency; SQL lint |
| Protected env-003 `nse-test-runner manifest-v1 fmt` | PASS, 81 files |
| Protected env-003 `nse-test-runner manifest-v1 check` | PASS, 81 targets |
| Protected env-003 `nse-test-runner manifest-v1 test` | PASS, 870 tests, including three new mutation-input rejection tests; zero transport/claim/evidence for those rejected calls |
| Dispatcher `pytest tests -q` | PASS, 59 tests; three new per-write feed rejection cases prove no worker call |
| `python3 scripts/nse_test_manifest_v1.py validate` | PASS |
| `python3 scripts/nse_test_manifest_v1_test.py` | PASS, 21 tests |
| `python3 scripts/nse_response_diagnostics_policy_test.py` | PASS, 1 test |
| `python3 .github/scripts/validate_docs.py` | PASS, 54 Markdown files |
| `python3 .github/scripts/validate_migration_history.py` | PASS, 27 frozen entries; additionally every migration unchanged against the fresh base |
| Conventional commit and `git diff --check` | PASS |

The Deno runner is
`/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner`.
Dispatcher pytest used `/tmp/b061-test-venv/bin/python -m pytest tests -q` from
`services/outbox-dispatcher` (system Python lacks pytest). Docker access required
sandbox escalation; containers remained network-isolated. The first fmt check
found wrapping in the new test; it was corrected and the protected check passed.
No unresolved test failure or new SQL lint finding remains.

Local logs: `/tmp/b07-completion-{baseline-sql,sql,regression,fmt,check,deno,pytest}.log`.
These machine-local logs and retained vendor inputs are not committed. No hosted
Supabase/Production mutation, provider UAT request, push, PR, merge or deployment
occurred. B01–B06 regressions remain passing with the current schema.
