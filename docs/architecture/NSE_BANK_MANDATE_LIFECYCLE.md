# B07 bank and mandate lifecycle foundation

Status: local implementation, **partial B07**. MANDATE_STATUS is implemented;
MANDATE and CLIENTBANKDTL ADD/DEL remain blocked. Nothing is commissioned.
Fresh fetched base: `ff531db2bec12d003091eec33ffbff52bfb101c2`.

## Source decisions and unresolved contracts

Primary sources are the current MoneyBowl schema, NSE handbook v1.9.7 printed
pages 70–74 and 83–84, the 2025-05-21 Postman collection, and coherent plan V2
B07/C031. Collection examples were inspected as data, never executed.

| Contract | Exact path after `/nsemfdesk/api/` | Implementation status |
| --- | --- | --- |
| NSE_MANDATE_STATUS | `v2/reports/MANDATE_STATUS` | Bounded service-only read, worker, encrypted evidence, safe summary |
| NSE_MANDATE | `v2/registration/product/MANDATE` | Blocked review proposal only; no request builder, registration worker or send route |
| NSE_CLIENTBANKDTL ADD | `v2/registration/CLIENTBANKDTL` | Distinct blocked `BANK_ADD` proposal; no mutation queued |
| NSE_CLIENTBANKDTL DEL | `v2/registration/CLIENTBANKDTL` | Distinct blocked `BANK_DEL` proposal; default bank rejected, all other deletes blocked |

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

Local validation outcome: 867 NSE Deno tests passed (39 B07 tests), 81 fmt/check
targets passed, 56 dispatcher tests passed, 21 manifest tests and the diagnostic
policy test passed. Both focused B07 and the complete NSE current-schema SQL
harness passed; B07 PL/pgSQL lint reported no findings. B01–B06, existing UCC,
dispatcher, frontend and concurrency regressions passed. No UAT request, hosted
mutation, push, PR, merge, deployment, credential or live infrastructure change
was performed.
