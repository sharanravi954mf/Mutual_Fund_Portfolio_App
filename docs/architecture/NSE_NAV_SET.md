# NSE B06.4 — NAV observations and blocked SET evidence

Rebased onto freshly fetched `origin/develop` (`d029c80`, merged B06.2) on
2026-10-02. B06.2 owns MASTER_DOWNLOAD orchestration, worker, events and dispatcher
routes. This slice registers private SQL validators in that runtime and retains
the existing NAV observation and blocked SET domain seams. No worker, event,
dispatcher route or browser command is added.

The unpublished local migration is now
`20261002152000_nse_b06_4_nav_set_observations.sql`, after B06.2's `150000`/`150100`
and distinct from B06.3's candidate. No applied migration was edited.

## Evidence and limits

Sources were read locally under `/home/ubuntu/nse-uat-contract`; no new UAT call
was made. The coherent plan's B06/F02/F03/C035 requires separate variants,
owned evidence, crosswalks and source decisions before business publication.

| Source | Supports | Does not establish |
| --- | --- | --- |
| Handbook v1.9.7 pp191–192 | NAV/SET variants; pipe-separated success; JSON failure; NAV has no header | Column layouts, precision scale, SET header |
| Current Postman collection, request #58 | Exact route and SCH request; no saved response | NAV or SET layout |
| `NSE_MF_WebfileStructure.pdf` p83, NAV MASTER | Eight ordered NAV fields and widths; ISO valuation date; dividend flags | Observed v1.9.7 API compatibility or UAT commissioning |
| Same web-file document p77, SETTLEMENT CALENDAR | Seven named fields for the web report | MASTER_DOWNLOAD SET header and compatibility |
| Retained historical sweep #58 | 4,057,995 bytes, 44 columns, 15,243 records, header; SCH-shaped | NAV/SET ingestion proof |

The web-file PDF SHA256 is
`67ee2e34c7cf776a2731e950837bd3aa6f2e6f7e5f521cbdbbce5cc60aae307d`.
Handbook/Postman/plan hashes and B06.1 transport constraints are recorded in
[NSE_MASTER_DOWNLOAD_FOUNDATION.md](NSE_MASTER_DOWNLOAD_FOUNDATION.md).
There is no retained NAV/SET response fixture establishing live compatibility.
The NAV parser is explicitly **document-backed and uncommissioned**; supporting
web documentation is not represented as an observed API response. SET is blocked
because positional parsing would additionally require guessing its header framing.

## NAV parser and durable model

`validate_nse_nav_snapshot(workspace, snapshot)` is the sole parser. It reloads
and locks B06.1 ownership, requires NAV, checks complete HTTP 200 file evidence,
decrypts/verifies every chunk, and recomputes the exact whole-body digest.
The service accepts no caller-supplied rows, source hashes or parser approval.

`NSE_NAV_WEB83_V1` reads these eight positions:

| Position | Typed field | Validation |
| --- | --- | --- |
| 1 | `nav_date` | Real `YYYY-MM-DD` date, no later than capture's UTC date |
| 2–4 | `nse_scheme_code`, `scheme_name`, `rta_scheme_code` | Nonempty; maximum 30/200/10 characters |
| 5 | `dividend_reinvestment` | Y/N/Z |
| 6 | `isin` | Twelve-character ISIN shape; not an identity/crosswalk approval |
| 7 | `nav_value`, `nav_lexeme` | Positive plain decimal, maximum 14 characters; exact numeric and original string |
| 8 | `rta_code` | Nonempty, maximum 10 characters |

UTF-8, one optional initial BOM, LF/CRLF and one optional final newline are
accepted. No header is removed. Empty/padded/control-bearing fields, bare CR,
internal blank lines, extra/missing columns, invalid dates, future valuations,
exponents, signs, nonpositive NAVs and duplicate scheme/date keys reject the
whole snapshot. Equal duplicates also reject; no deduplication or correction
is inferred. More than 100,000 rows rejects before any observation insert, matching
the shared runtime receipt bound. These are conservative local validation rules, not claims that
NSE guarantees every field mandatory or every identifier approved.

`nse_nav.validations` records parser/layout/source identity, accepted count,
rejection code/line, commissioning and publication gates. `observations` retains
each valuation date, exchange/RTA identity, option evidence and exact decimal.
A rejected row rolls back all observations before an immutable REJECTED receipt
is inserted. Infrastructure, authorization and evidence-integrity failures raise
errors instead of becoming semantic rejection receipts. Receipts and typed rows
commit atomically; repeated/concurrent validation returns the same receipt and
creates no duplicate rows or audit. Fresh evidence versions preserve corrections
and history even if the content digest repeats. B06.1 snapshots stay unchanged.

Reads require an explicit validated snapshot and the fixed parser version; pagination is
bounded to 1,000 rows, uses source line order and never switches to a newer snapshot.
Future parsers must retain this version's reader/receipts rather than reinterpret
old snapshots. The TypeScript service checks digest, snapshot, count, cursor and row shape on
every page, and keeps NAV decimals and bigint snapshot versions as strings.

## Crosswalk and source publication boundary

Every receipt has `BLOCKED_CROSSWALK_AND_SOURCE_POLICY`. No fund ID, inferred
mapping, current pointer or valuation publisher exists in this slice. NAV files
lack the complete AMC/plan identity required for a safe mapping on their own.
A future approved SCH crosswalk must supply an immutable, same-connection identity
and mapping version, MoneyBowl fund ID, AMC/ISIN/plan/option evidence, effective
version/date and an unambiguous review outcome. Name, NSE code or registrar-code
equality alone cannot authorize a link. Old observations must retain the exact
mapping used if a future publication is introduced. Merged B06.2 provides only
`PROPOSED`/`AMBIGUOUS`/`REJECTED` crosswalk candidates; it supplies no approval
state or authority to publish NAV.

The current source remains `daily-nav-updater` (`api.mfapi.in`) and registrar
persistence retains its existing fund mapping. Neither is changed. NSE observation
reads are evidence access, not authorization to use them in valuations. Before a
future publisher can be enabled, it must define source precedence, freshness per
valuation date, stale/future/missing-data behavior, corrections and approval;
atomically bind the approved crosswalk and receipt to a NAV-only publication
pointer with an expected prior version. Readers must pin that decision once.
The current migration's fixed blocked constraints require a reviewed additive
migration to introduce this authority; a service caller cannot toggle a flag.

A file ending on a valid row can be semantically incomplete even when the
transport length matches. B06.1 proves captured bytes, not provider completeness.
This limitation and uncommissioned API compatibility are additional reasons
observations cannot replace `mutual_funds.current_nav`.

## SET and B06.2 wiring

`assess_nse_set_snapshot(workspace, snapshot)` verifies owned SET evidence and
idempotently persists `BLOCKED_LAYOUT_UNCHARACTERIZED`, reason
`WEB77_API_COMPATIBILITY_AND_HEADER_UNCONFIRMED`. Even seven apparently valid
web-report fields remain blocked. There is no calendar row schema, parser,
publication or scheduling consumer. A future version needs authoritative API
layout/header/null/date rules and representative evidence, independently of NAV.

B06.2's existing service preparation now accepts exact `NAV` and `SET` variants
through its migration-owned registry. Only a commissioned, enabled, owned UAT
connection can capture; this migration creates none. Each job uses the same
claim, capture, staging, validation and completion transaction as SCH:

| Variant | Private adapter | Shared status / scope | Domain result |
| --- | --- | --- | --- |
| NAV | `nse_reference.validate_nav_v1(uuid)` | `STAGED_VALIDATED` / `DOCUMENT_BACKED_UNCOMMISSIONED_OBSERVATIONS`, or `REJECTED` | Dated `VALIDATED_OBSERVATIONS`, API `UNCOMMISSIONED`, publication blocked; or atomic zero-row rejection |
| SET | `nse_reference.validate_set_v1(uuid)` | Always `REJECTED` / `EVIDENCE_ONLY_LAYOUT_UNCHARACTERIZED` | `BLOCKED_LAYOUT_UNCHARACTERIZED`; no calendar rows |

SET's category is `nse_reference_set_layout_uncharacterized`. Zero accepted and
zero rejected rows mean no layout was interpreted. `REJECTED` rejects validation;
it does not assert that the provider's data is invalid. The completed outbox event
means terminal processing, never business success. It prevents repeated provider
calls for an uncharacterized layout. JSON/error bodies and incomplete transport
remain `CAPTURE_FAILED` and create no SET assessment.

NAV success uses `nse_reference_nav_observations_uncommissioned`; a parser rejection
uses `nse_reference_nav_layout_invalid`. The detailed rejection code/line remains
in the domain receipt. Shared `rejected_rows` is one only when the parser identifies
a failing line; it is not a full invalid-row count. The row-limit rejection carries
zero and no line. Every shared receipt still has `publication_gate=BLOCKED`.

The private adapters call the existing sole SQL parser/assessor. Domain rows and
audits, shared validation, immutable snapshot and completion commit atomically.
Failure to persist completion rolls them all back; sealed evidence can retry
finalization without recapture. Cached receipts still recheck ownership. Direct
service assessment and shared finalization serialize on the same connection and
evidence locks, reusing the domain receipt without duplicate observations/audits.

The TypeScript services remain internal review seams:

- `createNseNavService(client).validate({ workspaceId, snapshotId })`, then
  `readPage(receipt, afterLine, limit)` for pinned observation review.
- `createNseSetService(client).assess({ workspaceId, snapshotId })`, exposing only
  the blocked domain receipt.

All three tables use private schemas, RLS, zero policies and zero direct API-role
privileges. Only the three public service-role RPCs execute as definers with empty
search paths. Composite foreign keys bind variants and owners; existing member,
workspace and production restrictions run even for cached receipts. Immutable
assessment audits share the transaction and contain only status and digest.
Browser roles, including Platform Admin and operations users, have no access.

## Validation

All fixtures are synthetic. `scripts/test_nse_order_status_sql.sh` rebuilds the
full migration chain in a disposable PostgreSQL 17 container with networking
disabled, lints the private adapters and public/domain functions, runs both SCH
and NAV/SET suites twice, and checks concurrent preparation, claim, finalization,
snapshot allocation and domain assessment replay. Runtime tests cover SET's
terminal rejection, sealed-capture recovery, rollback of domain/shared receipts
and audits on completion failure, ownership and actual service/browser roles.
Existing NAV/SET tests retain source precedence, no inferred crosswalk, dated
corrections, pinned paging, multichunk evidence, truncation, atomic rejection,
immutable audits and ACL coverage. The protected Deno manifest retains B06.2's
worker and B06.4's services, with 69 fmt/check targets and 27 suites.

| Check | Reconciled result |
| --- | --- |
| Protected Deno fmt/check/test | 69 targets; 710 tests pass |
| Full migration reset and PL/pgSQL lint | Pass; no new warnings/errors |
| Full NSE/UCC/dispatcher/B01–B06/facade SQL | Pass twice; SCH 235, NAV/SET 248, runtime integration 76 assertions per pass, plus actual role exercises |
| Reference, SCH, NAV/SET and frontend concurrency | Pass; prepare/claim/finalize and assessment replay produce no duplicates |
| Manifest/diagnostic-policy/Compose tests | 22 pass |
| Dispatcher/reconciler pytest | 55 pass |
| Documentation, migration history, shell syntax, whitespace | Pass |
| Every persistent SQL test on a fresh restored database | Develop: 22 pass / 15 fail; candidate: 24 pass / the same 15 fail |
| Existing order/payment concurrency | Pass on fresh develop and candidate |
| Existing registrar/referral concurrency | Same baseline failures: missing PAN key / unresolved referral profile |

The broad comparison found no new failing test or previously passing regression.
The full relevant NSE suite is green. The broad repository suite has existing
failures; unrelated fixtures, ACL contracts and CI were not changed. Both baseline and candidate
`run_all.sh` stop on `issue_114_service_role_protected_table_select:workspaces`.
Other baseline failures cover cancellation (#28), old timestamp fixtures
(#29/#30/#89/sprint hardening), local PAN-key setup (#32/PAN verification),
entitlement visibility (#39), referral resolution (#40), and final-hardening
profile mapping. See the [B06.2 baseline](NSE_MASTER_DOWNLOAD_SCH.md).

Reproduce the maintained relevant suite with:

```bash
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 fmt
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 check
/opt/moneybowl-toolchains/nse-test/deno-2.9.6-env-003/nse-test-runner manifest-v1 test
bash scripts/test_nse_order_status_sql.sh
python3 -m unittest scripts/nse_test_manifest_v1_test.py scripts/nse_response_diagnostics_policy_test.py scripts/test_outbox_compose.py
python3 .github/scripts/validate_docs.py
python3 .github/scripts/validate_migration_history.py
python3 .github/scripts/validate_commits.py
```

Local receipts: `/tmp/b064-reconcile-{deno,check,fmt,sql,python,dispatcher,docs}.log`,
`/tmp/b064-reconcile-{baseline,candidate}-all-db.log` and
`/tmp/b064-reconcile-extra-checks.log`; comparison inventory:
`/tmp/b064-reconcile-validation-comparison.json`. The broad comparison rebuilds fresh
schemas from the fetched develop archive and candidate, then restores an isolated
database for each persistent SQL test; it also runs `run_all.sh` and referral
concurrency in the disposable container. Existing applied migration blobs,
shared runtime implementation, route contract and function configuration are
byte-identical to fetched develop.
No hosted database, live Docker service, systemd unit, NSE endpoint, Production/main,
push, PR or merge is part of this local reconciliation. Reset/lint use only the
disposable offline harness, not the shared Supabase instance.
