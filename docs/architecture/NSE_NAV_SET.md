# NSE B06.4 — NAV observations and blocked SET evidence

Built on merged B06.1 (`6721741`). B06.2 owns MASTER_DOWNLOAD orchestration,
worker, events and dispatcher routes. This slice adds only database parser,
domain and service seams; no endpoint or provider call is added.

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
is inferred. These are conservative local validation rules, not claims that
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
B06.2's approved SCH crosswalk must supply an immutable, same-connection identity
and mapping version, MoneyBowl fund ID, AMC/ISIN/plan/option evidence, effective
version/date and an unambiguous review outcome. Name, NSE code or registrar-code
equality alone cannot authorize a link. Old observations must retain the exact
mapping used if a future publication is introduced.

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

After B06.2 captures and stages a variant, it can call:

- `createNseNavService(client).validate({ workspaceId, snapshotId })`, then
  `readPage(receipt, afterLine, limit)` for internal observation review.
- `createNseSetService(client).assess({ workspaceId, snapshotId })`, treating its
  result as a domain blocker, never business success or a retryable transport error.

All three tables use private schemas, RLS, zero policies and zero direct API-role
privileges. Only the three public service-role RPCs execute as definers with empty
search paths. Composite foreign keys bind variants and owners; existing member,
workspace and production restrictions run even for cached receipts. Immutable
assessment audits share the transaction and contain only status and digest.
Browser roles, including Platform Admin and operations users, have no access.

## Validation

All fixtures are synthetic. `scripts/test_nse_order_status_sql.sh` rebuilds the
full migration chain in a disposable PostgreSQL 17 container with networking
disabled, lints the new functions, runs B01–B06.1 and NAV/SET suites twice, and
checks concurrent snapshot allocation and assessment replay. NAV/SET tests cover
source precedence, no inferred crosswalk, dated corrections, snapshot paging,
multichunk evidence, truncation, atomic rejection, audit immutability and ACLs.
The protected Deno manifest includes NAV/SET services and their tests.

Local results: 689 Deno tests pass (645 baseline + 44 new); protected fmt/check
pass. Both SQL passes include 244 NAV/SET assertions; version and assessment
concurrency pass. All new PL/pgSQL functions lint without warnings/errors. The
22 script tests, Compose check, 54 dispatcher tests, documentation, migration
history and commit validators pass. Disabling pytest's cache for this read-only
test environment emits the unrelated `Unknown config option: cache_dir` warning.

The broad SQL suite is not green: fresh-schema runs give 21 baseline / 22 candidate
passes and the same 15 failures listed in the B06.1 foundation document. Referral
concurrency still fails with `referral_profile_not_resolved`; `run_all.sh` stops at
the existing protected-workspaces SELECT assertion in issue 114. No previously
passing SQL suite fails. Logs are `/tmp/b064-{deno,check,fmt,sql,python,dispatcher}.log`
and `/tmp/b064-{baseline,candidate}-all-db.log`. Reset/lint use the disposable
offline harness rather than the shared Supabase instance. No hosted database
reset, deployment, real secret access, NSE call, push, PR or merge is part of this slice.
