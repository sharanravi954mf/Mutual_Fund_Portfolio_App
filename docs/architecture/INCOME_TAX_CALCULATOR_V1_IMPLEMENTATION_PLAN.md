> **Current bounded V1 status (2026-10-05): local implementation and frozen automated validation complete; independent review and hosted commissioning remain outstanding.** The older status immediately below is preserved as historical evidence. See the [release contract](INCOME_TAX_CALCULATOR_V1_RELEASE_SCOPE.md) and [validation](INCOME_TAX_CALCULATOR_V1_VALIDATION.md#bounded-v1-release-validation--2026-10-05).

> Current status (2026-10-05): **PARTIAL LOCAL IMPLEMENTATION, UNCOMMITTED — NOT RELEASE READY**.
> The component-gated resumption appendices below supersede the earlier global stop.
> Historical blocked findings and evidence are intentionally retained.

> Local bounded-release implementation resumes under the [2026-10-05 scope decision](INCOME_TAX_CALCULATOR_V1_RELEASE_SCOPE.md). Four named investment IDs and four acceptance IDs are REQUIRED_FOR_V1; all other original IDs retain their recorded scenario and are explicitly mapped in the [pending/blocked register](INCOME_TAX_CALCULATOR_V1_PENDING_AND_BLOCKED.md). A deferred case must fail closed for both regimes. This statement changes the release gate, not the historical legal findings or the independent-review/professional/hosted gates.

# Income Tax Calculator V1 implementation plan

> Release-contract update (2026-10-05): the [bounded V1 release scope](INCOME_TAX_CALCULATOR_V1_RELEASE_SCOPE.md) supersedes this plan's historical requirement to implement all 37 acceptance entries before a local commit. The [pending and blocked register](INCOME_TAX_CALCULATOR_V1_PENDING_AND_BLOCKED.md) maps every original ID to the current release decision. The original blocked history and source questions below are preserved; deferral never authorizes a partial estimate.

Research started 2026-10-05, before tax implementation. Status: BLOCKED at the
research gate; this document is not an implementation or legal-verification claim.

## Verified repository boundary

Canonical `/home/ubuntu/moneybowl` was clean on `develop`. Fresh fetch succeeded
and HEAD and origin/develop were both
`85ccebf87721b5e52c62b209095ce7ebf474bd61`. Created previously absent branch
`feature/calculators-income-tax-v1` and worktree
`/home/ubuntu/moneybowl-worktrees/calculators-income-tax-v1` from that commit.
Read AGENTS.md and the implementation/Flutter finance UI project skills.
The user's local-only instructions supersede issue/project/PR workflow steps.
No additional AI sessions, remote writes, hosted queries, migrations, auth or
secret changes are authorized. Exactly one local feature commit is permitted
only after all required implementation checks pass.

## Mandatory research gate

Bind every rule to enacted provisions in the [source register](INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md).
Verify the 1961 Act for 1 April 2025–31 March 2026 (AY 2026–27), and the 2025
Act for 1 April 2026–31 March 2027 (Tax Year 2026–27), including applicable
Finance Act schedules, notified Rules and subsequent amendments. Use official
sources for law; competitor calculators are only numerical/UX comparisons.
Retain downloads, extraction and runner evidence outside Git at
`/tmp/moneybowl-income-tax-v1-evidence/`. A material unverified interaction
blocks tax implementation; do not replace it with an assumption or silently
reduce the requested scope.

## Planned feature architecture

Create `lib/features/calculators/income_tax/`, with pure Dart `models/` and
`domain/`, explicit independent year rule packs, deduction and special-income
components, and a presentation controller and Normal/Advanced screen. Append
one catalog definition after Loan Part Payment, EMI and SIP. Preserve their
models, mathematics, controllers, screens, and privacy/regression assertions;
change only the catalog and strictly necessary catalog-count assertions.

Use exact rational arithmetic backed by BigInt for money and percentages, with
plain decimal parsing and bounded input lengths. No binary floating-point tax
threshold comparisons. Do not round intermediate exemptions, one-third family
pension deductions, tax or relief. Apply statutory income and payable/refund
rounding separately, with explicit component reconciliation and audit entries.
Immutable typed outcomes distinguish successful estimates, invalid inputs and
unsupported cases. Both presentation modes call the same computation engine.

## Planned computation and input contract

1. Confirm resident ordinarily resident individual eligibility and age during
   the selected income period; reject unsupported categories explicitly.
2. Salary/employment pension includes HRA once. Capture whether employer NPS is
   already included, its statutory salary base and employer category. Require
   already-computed taxable perquisites; complex perquisite computation is out
   of scope. Compute eligible HRA separately for non-overlapping dated periods
   and statutory period salary; apply salary deductions once and within income.
3. Separately compute savings, eligible deposits, other interest, domestic
   dividends and ordinary family pension, all gross of TDS.
4. Compute up to one completed, fully owned self-occupied and one let-out
   property, using legally determined annual value, municipal taxes paid,
   statutory deduction and eligible interest. Capture self-occupied purpose,
   borrowing date, completion and certificate eligibility. Apply only permitted
   current-year intra/inter-head set-off and report unused/disallowed loss.
5. Compute eligible capped investment/pension, health, education-interest and
   interest deductions; prevent own-NPS duplication, respect eligible income
   and special-rate restrictions. No unrestricted other-deductions field.
6. Accept only nonnegative, already-computed qualifying listed equity/equity
   fund STCG/LTCG, with statutory/STT confirmation, before the annual LTCG
   threshold. Verify allocation of basic-exemption shortfall and set-offs.
7. Round statutory total income, reconcile components, compute ordinary and
   special-rate tax, regime-specific rebate and rebate marginal relief,
   component-specific surcharge and its distinct marginal relief, then cess.
8. Report liability before credits and payable/refund after TDS, TCS, advance
   tax and self-assessment tax, without claiming AIS/26AS verification.

## Planned presentation and privacy

Year selector with actual dates/Act, Normal/Advanced, Input/Rules & Assumptions,
Calculate/Reset, simultaneous regime comparison, expandable typed computation
and entered/allowed/disallowed deductions with reasons. A tie has no winner;
comparison is not a legal regime election. Preserve advanced data on mode
switch, or require explicit clearing confirmation. Every input/year change
invalidates results and revalidates. No silent year fallback.

Use existing Material theme, natural-height responsive controls at 320px through
desktop, Indian rupee formatting, large text, keyboard navigation and semantics.
Financial state remains ephemeral; no identifiers, documents, backend, network,
telemetry, logs, browser storage, restoration or URL financial values. Static
official references can be opened only through explicit user action.

## Validation and delivery gates

Before source edits run existing calculator and Explorer navigation tests.
Independently derive and source-link golden vectors before implementing the
engine: salary 15 lakh (old 257400/new 97500), salary 12.75 lakh (new zero),
salary 12.85 lakh (new taxable 1210000/tax 10400), and ordinary taxable 11 lakh
plus STCG 1 lakh (new 20800), for both year packs. Report discrepancies.

Cover every slab/rebate/surcharge/rounding boundary; ages; income/deduction
eligibility and caps; HRA periods/cities; NPS; health checkup aggregation;
education loan period; property set-offs; gains/shortfall/rebate/surcharge
interactions; credits; immutable trace reconciliation; malformed/unsupported
inputs; mode equivalence; switching/reset/staleness; navigation, layout and
privacy. Expected values must not come from the production engine.

Attempt synthetic comparisons with the official calculator and one renowned
calculator using the same year and input meaning; otherwise record NOT_RUN.
Run format, scoped analyzer, new domain/controller/widget/golden tests, all
calculator and Explorer regressions, full Flutter suite, local release web
build with loopback/synthetic configuration, docs/links, frozen migration
history, commit validator and diff/scope checks. No dependency change intended.
Document pre-existing Wasm/font warnings separately.

After all gates pass, update contract, validation, catalog documentation and
docs/CHANGELOG.md and create exactly one local commit:
`feat(calculators): add income tax comparison calculator`.
Tax-professional signoff and hosted commissioning are separate unperformed
release gates. A research blocker requires an INCOMPLETE/BLOCKED report,
not a feature-complete commit.

## Actual outcome

The baseline passed all **316 tests** before any product source edits. The first
sandboxed run could not bind Flutter's 127.0.0.1 test socket; the authorized
rerun passed in 92 seconds. Offline dependency resolution succeeded and did not
change tracked dependency files.

Research stopped without product source edits because the mandatory source
gate could not be satisfied. See the [precise blockers](INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md#blocking-verification-gaps)
and [validation record](INCOME_TAX_CALCULATOR_V1_VALIDATION.md).
Normal/Advanced UI, engine, rule packs, fixtures and feature tests were not
implemented. No feature commit was created because the implementation and
validation conditions for that commit were not met. The candidate remains
documentation only, uncommitted, on the isolated branch.

## Resumed research outcome — 2026-10-05

Reused the existing branch/worktree without resetting or recreating it. Fresh
fetch and readback again verified the expected clean canonical develop base,
zero feature commits, six documentation changes and the observed untracked
Python bytecode. The bytecode was neither staged nor indiscriminately removed.
The handoff and every retained evidence hash passed verification.

The Gazette review is now recorded. Active utility formula/VBA inspection
resolved the missing dividend-reference origins and identified the STCG-first
basic-exemption chain. The official index also exposed a newer v1.4 utility;
it was independently downloaded and statically inspected, without macros.

The gate remains blocked by the reproducible `B2-MR-112A-50L` discrepancy in
both utility versions, documented in the [resumed source register](INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md#resumption-on-2026-10-05--verified-evidence-and-concrete-conflict).
A pure-LTCG vector violates the enacted surcharge-relief ceiling by 15625
before cess, or 16250 after cess/rounding. The complete replacement mixed-income
method and all remaining rule rows are not certified. The original instruction
to stop for a material unresolved discrepancy therefore prevents tax code or
a feature-complete commit. All original scope and validation gates remain.

## Component-gated implementation resumption — 2026-10-05

The user's latest instruction supersedes the historical global stop gate above.
Preserve that history. Each component now requires enacted authority, separate
year applicability, an explicit interpretation and independent fixtures before
implementation. An unresolved dependency returns a typed `TaxNotYetVerified`
without any liability/comparison. Unsupported cases have a separate typed
result. Both presentation modes use one pure, exact-arithmetic engine.

Precheck again passed: canonical develop and freshly fetched origin/develop at
85ccebf87721b5e52c62b209095ce7ebf474bd61, clean; feature HEAD unchanged, zero
feature commits, the six documentation changes preserved, no application edits.
Retained evidence hashes passed. Calculator/Explorer baseline: 316 passed.

Implementation order: exact rational amounts and immutable models; distinct
versioned year packs; salary/ordinary slabs/rebates/cess and ordinary surcharge;
verified sole-category LTCG; independent deductions; controller and accessible
Normal/Advanced forms; remaining exemptions, property and mixed special income.
Register dependency gaps explicitly and test that they suppress estimates.
B2-MR-112A-50L is a KNOWN STATIC UTILITY DISCREPANCY, not a global stop condition.
No feature commit until the entire originally agreed scope and checks pass.

### Implemented local progress and next dependency branches

The planned independent feature area, exact arithmetic, immutable models, two
packs, common verified deductions, HRA periods, bounded property computation,
ordinary/special components, ephemeral controller and both presentation modes
are implemented. The fourth catalog route exists locally. Independent ordinary
and sole-LTCG fixtures and targeted deduction/property/UI tests now execute.
The earlier documentation-only statements remain historical records.

Continue from the existing source and fixtures. Remaining branches are combined
gain/basic-exemption allocation; mixed-income surcharge cutoff composition and
dividend attribution; rounding that would otherwise create a negative ordinary
residual; property loss allocation involving gains/interest deductions and
negative NAV; negative salary-head set-off; TY2026 HRA commission definition;
additional guided80C instruments; post-office savings exemptions; and separate
multiple-employer NPS inputs. Complete the bounded subsequent-amendment review
and expand the original acceptance matrix before removing any gate. Known
utility discrepancy B2-MR-112A-50L is explained and separately tested, not a
reason to abandon these independent branches.

Local build and current tests are evidence for the implemented candidate only.
The final current validation appendix records the precise checks and coverage.
The original completion/commit condition has not been satisfied; preserve this
tested local progress uncommitted, with professional and hosted gates outstanding.

## Next continuation work order — 2026-10-05

Preserve the24-path manifest as the prior candidate snapshot. Extend the existing
models/controller/form with policy-level life insurance, two tuition children,
qualified housing payments, NSC subscription/reinvestment details and employer-
specific NPS rows. Keep the existing singleton NPS input compatible while adding
separate employers; no new aggregate unrestricted deduction field. Bind every
new computation before code and test independent expected amounts. Then address
ordinary loss/exemption interactions, gains/surcharge branches and real-control
widget journeys. Unresolved dependent outputs remain unavailable. Use new log
and manifest names so prior validation evidence stays reproducible.

## Tested continuation and remaining gates — 2026-10-05

Preserved the original24-file manifest and checked it before editing. Continued
existing code, without a new checkout or additional AI session. Added named
guided life/tuition/housing/NSC instruments; separate employer NPS rows and salary
bases; verified TY2026 HRA turnover commission; ordinary-only salary/property
loss allocation; one individual Post Office Savings Bank exemption; and pure
company-dividend capped surcharge. Both explicit packs advance to rule revision2.

Actual form-control journeys now cover eligibility, guided instruments, distinct
employers, multiple HRA periods/cities, editing/removal, modes, years, age changes,
stale-result invalidation and reset. Expanded independent age/interaction goldens
remain separate from production. The earlier blocks remain history, not a reason
to discard tested progress. The precise current matrix and bounded amendment
review closure are appended to the source register.

Still required before a feature commit: verified combined-gain basic exemption,
mixed surcharge/cutoff construction, mixed dividend attribution, gain-related
loss allocation, non-negative special-component rounding, negative NAV, and the
remaining interest/instrument/recapture branches. Complete associated independent
fixtures and browser journeys, rerun all local checks, then make exactly one
local commit if the entire original target passes. No release-readiness claim
or scope reduction follows from passing the implemented branches.


## Finite remaining acceptance register — 2026-10-05 reviewer continuation

This register supersedes vague *current-work* labels in earlier historical
entries; it does not erase their chronology. The original two years, both
regimes, both modes and income categories remain the target. Every open row is
required before a complete V1 claim. No deferral or new exclusion is approved.
The tables enumerate calculation branches, not a promise that every named scheme
is eligible in both years. Notification continuity and statutory eligibility must
be established before offering it. A branch legally ineligible in a year needs a
sourced rejection test, not silent omission.

Common closure criterion **C**: bind official provision/notification and effective
date separately for both packs; record interpretation and independent exact
expected values; implement typed input/trace/UI behavior; pass domain boundaries
and an actual-form journey in Normal or Advanced as appropriate; prove equivalent
inputs use the one engine; pass the frozen regression/build checks. The year ×
regime × age cross-product is mandatory wherever those dimensions affect the
rule. `TaxNotYetVerified` safety tests never satisfy C. The existing source-register
matrix lists already implemented branches; these tables list unfinished ones.

### Core calculation branches (original sections5B/5C/5E/6/9)

| Stable ID / specific scenario | Remaining source or interpretation | Independent cases required | Current implementation/tests; objective closure |
| --- | --- | --- | --- |
| IT-GAINS-ALLOCATION: ordinary100000, ST250000, LT200000 | 111A/112A resident provisos versus2025 ss196/198; reconcile active utility U38→U53/W53→U60/W60 without treating FY utility as TY authority | New ST-first liability3250 versus LT-first31200 diagnostic; sole/both gains, all age basic thresholds±0.01/1/10; below/at/above125000 LT threshold | Ordinary-at-least-basic branch implemented; shortfall gated. C plus one justified allocation without double use |
| IT-SURCHARGE-MIXED: ordinary3000000, ST2000800 | F26 s2/s3 and respective PartI-A/I-B ParagraphF Tables1–2; justify cutoff composition in V294:V300/U306:V311/AA306 and dependencies | At50L diagnostic New916030 versus915950, Old1157830 versus1157750; mixtures ST/LT/ordinary at50L,1Cr,2Cr,5Cr±10 and relief crossover±10; both capped and uncapped components | Homogeneous branches pass; mixtures with gains above50L gated. C plus independent cutoff-composition trace |
| IT-DIVIDEND-SURCHARGE: ordinary21000000 plus dividends1000000 | Statutory tax attributable to dividends, F26 separate schedules; active V300 pro-rata versus marginal attribution | New8004790 versus8002800 diagnostic; ordinary+dividend, gain+dividend, loss+dividend at2Cr/5Cr and relief crossovers | Pure dividends pass; enhanced mixed attribution gated. C plus sourced attribution and reconciliation; REIT/InvIT remain explicit original exclusions |
| IT-PROPERTY-LOSS-ALLOCATION: salary500000, eligible property loss200000, ST100000/LT200000 | 1961 s71(2)/(3A), 2025 ss108/109, special-gain/deduction restrictions; beneficial ordering with interest deduction | Loss0/199990/200000/200010; ST-only, LT-only and both; savings10000, senior deposits50000; ordinary below/above basic | No-gain loss/interest interactions pass; gains gate. C plus independently minimized lawful allocation and disallowed amount |
| IT-SALARY-LOSS: salary10000, professional tax20000, ST100000/LT200000 | Same current-year inter-head provisions, salary loss distinct from property cap | Salary head0/−10/−10000; one/both gains; property gain/loss; deduction-limited income | No-gain salary losses pass; gains gate. C plus head-specific permitted allocation |
| IT-ROUND-COMPONENTS: ordinary0.01, LT800003 | 288A/288B and2025 s516; statutory TI800000 needs nonnegative attribution | Residual±0.01/1/3/5; ST-only, LT-only, both; threshold/rebate/surcharge adjacent totals and credits | Sole-component rounding and nonnegative ordinary residual pass; negative residual gated. C plus exact sum-of-components proof and trace adjustment |
| IT-PROPERTY-NEGATIVE-NAV: GAV10000, paid municipal15000, interest0 | 1961 s23 proviso/s24(a),2025 s21(3)/22(1)(a); reconcile signed annual value with active ITR2 HouseProperty K24/K59 zero clamp | NAV0/−10/−5000; diagnostic head0 versus−5000 versus−3500; add borrowed interest and self-occupied loss | No-estimate safeguard only. C plus resolved signed NAV/deduction rule and current-year loss test |

The competing numbers above are **diagnostics**, not certified goldens. Retained
B2-MR-112A-50L remains explained STATIC_FORMULA_REPRODUCTION, with separate passing
statutory results; it is not an open global gate and does not certify mixed cases.

### Named interest branches (original5B/5D; continuation ordinary-interest work)

For each row, C additionally requires gross interest, exempt amount, taxable
interest and allowed80TTA/80TTB or153 reconciliation. Tax-free amounts must not
consume an income deduction. Default status is **PENDING: no dedicated guided
branch or independent accepted fixture**; the declared special-interest safeguard
exists. Existing taxable ordinary interest and one individually held POS account
are already implemented and are not reopened here.

| Stable ID / specific scenario | Source/interpretation still needed | Independent cases required / closure extension |
| --- | --- | --- |
| IT-NSC-SENIOR-INTEREST: resident60/80, NSC accrued10000 plus bank interest50000 | 80TTB/153 meaning of deposit versus certificate; NSC notifications and reinvestment | Below60/60/80, first-four-year versus final-year interest; aggregate cap±10; decide eligible interest before C |
| IT-POS-JOINT: joint POS interest10000, taxpayer owns half | Notification32/2011 single3500/joint7000, ownership attribution; 2025 savings provision | One/two holders, unequal shares,7000±10; no double exemption across returns; C with ownership constraints |
| IT-POS-MULTIPLE: two individual accounts interest3000 each; individual plus joint account | Whether exempt limit is aggregate/person/account and interaction with joint limit | Single/single and single/joint,3500/7000±10; source-backed aggregation before C |
| IT-INTEREST-PPF: gross PPF interest10000 plus taxable savings10000 | 1961 s10(11), 2025 applicable exemption entry and notified scheme | Eligible versus nonqualifying fund; exempt interest retained in explanation, not taxable/deducted twice; C |
| IT-INTEREST-SUKANYA: qualifying account interest10000 | 1961 s10(11A), 2025 exemption mapping and scheme continuity | Holder/guardian eligibility and mixing savings; C |
| IT-INTEREST-TAXFREE-BOND: notified bond interest10000 plus ordinary bond interest10000 | 10(15) specific instrument/issue notification, 2025 exemption mapping | Qualifying issue/date versus ordinary taxable bond; cannot accept a generic tax-free checkbox; C |
| IT-INTEREST-PF-EXCESS: employee PF contribution300000 with/without employer contribution, separately certified interest | 10(11)/(12) provisos,1962 Rule9D and2026 counterpart; separate taxable/non-taxable accounts |250000/500000 contribution boundaries and already-computed taxable interest; no invented accrual engine; C with explicit scope-safe input meaning |

These are a finite inventory of the previously open “special-interest” work,
not newly asserted exemptions. Agricultural, foreign, crypto, lottery and gaming
income remain the original explicit exclusions. Additional instrument-specific
exemptions discovered later require a named row and an explicit scope assessment;
there is no catch-all allowance or automatic new feature commitment.

### Named investment instruments (original5D80C/80CCC group)

Already implemented: employee recognised PF, PPF, ELSS,80CCC annuity, guided life
premiums, two-child tuition, eligible housing principal/transfer charges, NSC and
own NPS. Remaining families below replace “other instruments.” Each is a pending
eligibility/input branch under the agreed group requirement, not certified legal
eligibility or an approved deferral. No unrestricted deduction field is proposed.

All rows currently have only the umbrella `additional80cInstruments` no-estimate
guard, **not implementation acceptance**. For each eligible branch independent
fixtures must include salary1500000 with payment100000 (Old deduction100000,
liability226200; New97500), plus eligible EPF100000 (shared deduction150000,
Old210600), eligibility failure (Old257400 absent other deductions), available
income restriction, and payment/cap/lock-in boundaries. These conditional
arithmetic checks do not establish whether a particular product qualifies.
Closure is C **and** guided proof of each row's named conditions.

| Stable ID / exact payment family | Official binding to finish; eligibility input scenario |
| --- | --- |
| IT-INVEST-BANK5 | 80C(2)(xxi), ScheduleXV1(s), Bank Term Deposit Scheme notification/continuity; scheduled-bank qualifying5-year deposit versus ordinary FD |
| IT-INVEST-POST5 | 80C(2)(xxv), XV1(v), Post Office Time Deposit scheme continuity;5-year versus1/2/3-year deposit |
| IT-INVEST-SCSS | 80C(2)(xxiii), XV1(u), current SCSS scheme eligibility and predecessor references; resident eligible depositor and deposit date |
| IT-INVEST-SUKANYA | 80C(2)(viii), XV1(h), specific account notification; eligible girl child/guardian and payment ceiling |
| IT-INVEST-SUPERANNUATION | 80C(2)(vii), XV1(g); employee contribution to approved fund, distinct from employer/perquisite calculation |
| IT-INVEST-STATUTORY-PF | 80C(2)(iv), XV1(d); employee contribution to1925 Act fund, distinct from recognised EPF input meaning |
| IT-INVEST-DEFERRED-ANNUITY | 80C(2)(ii)/(iii), XV1(b)/(c); private contract without cash option and government salary deduction subject20% base; distinguish80CCC |
| IT-INVEST-NOTIFIED-ANNUITY | 80C(2)(xii), XV1(l); named notified insurer plan, no duplicate80CCC claim |
| IT-INVEST-ULIP | 80C(2)(x)/(xi), XV1(j)/(k); UTI1971 and notified LIC Mutual Fund plans, ownership and continuation; distinguish ordinary life policy |
| IT-INVEST-NOTIFIED-PENSION | 80C(2)(xiv)/(xv), XV1(n)/(o); notified mutual-fund pension and NHB pension/deposit; plan notification and eligible holder |
| IT-INVEST-HOUSING-DEPOSIT | 80C(2)(xvi), XV1(p); notified public housing-finance company or statutory housing/development authority deposit, distinct from housing principal |
| IT-INVEST-NABARD | 80C(2)(xxii), XV1(t); notified NABARD bond issue and subscription date; ordinary bond rejected |
| IT-INVEST-NPS-TIER2 | 80C(2)(xxvii), XV1(w); Central Government employee Tier-II tax-saver scheme,3-year restriction; no transfer from own Tier-I bucket |
| IT-INVEST-LEGACY-SHARES | 80C(2)(xix)/(xx); eligible infrastructure share/debenture or qualifying fund subscription versus ordinary investment; separately establish any2025 Act continuation rather than assume1:1 mapping |

Sources for the inventory: [1961 section80C,2025 edition](https://www.incometaxindia.gov.in/w/section-80c-60)
and [2025 Act ScheduleXV](https://www.incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf),
physical pp673–678, inspected5October2026. Listed notifications remain to be
bound individually; an enabling clause alone is not a complete source gate.

### Recapture and final acceptance (original5D/7/9/10/11)

| Stable ID / scenario | Needed source / independent cases | Current status; closure |
| --- | --- | --- |
| IT-RECAPTURE-LIFE | Life contract ends before qualifying continuation period;80C(5)/XV recapture paragraph; two-year/five-year plan-specific boundaries, refunded versus ceased premiums | Pending declared-reversal guard. C plus prior allowed deduction inputs, current income and no duplicate deduction |
| IT-RECAPTURE-HOUSING | House transferred or eligible amount refunded before lock-in;80C(5)/XV conditions;5-year boundary and prior allowed amount | Same guard; C with sourced year counting and exact income-head treatment |
| IT-RECAPTURE-MARKET | Early disposal/termination of qualifying share, fund, ULIP or Tier-II instrument;80C(5)/(6), ScheduleXV and scheme-specific continuation rules; minimum period±1day and prior allowed sums | Pending umbrella reversal guard. C with instrument-specific disposition, no generic recapture override |
| IT-RECAPTURE-DEPOSIT | SCSS/5-year time deposit withdrawn early;80C recapture clauses/XV; principal/interest already taxed, death exception | Same guard; C with no double taxation and scheme-specific conditions |
| IT-ACCEPT-JOURNEYS | Each newly resolved row above entered/edited/removed via actual controls, year/mode/eligibility changes and reset | Existing general journeys pass; new branches await implementation. Closure: positive independent-value assertions, no stale results/winner,320px and large-text coverage |
| IT-ACCEPT-MATRIX | Year × regime × category × relevant interaction cross-product | Existing matrices/goldens partial. Closure: every required row maps to accepted independent values and passing tests; no no-estimate test counted as a completed computation |
| IT-ACCEPT-AMENDMENTS | Dated bounded official amendment review through verification date, preserved retrieval failures | Prior dated review retained,97 retrieval closed there. Closure for release: refresh relevant amendments, record exact instruments/effective dates and unresolved material failures; never claim exhaustive absence from search silence |
| IT-ACCEPT-LOCAL | Frozen snapshot analyzer/format/all suites/release build/docs/migration/diff | Must rerun for final implementation; passing this partial candidate does not close tax gates |
| IT-ACCEPT-COMPARATORS | Official and renowned interactive same-year synthetic comparisons | NOT_RUN; report accessibility and status honestly. Static workbook reproduction remains separate, not an executed calculator result |

**Proposed additional scope:** none is implemented or required by this update.
Purchase/sale matching, capital-loss management, return filing, foreign income,
AMT and professional commissioning remain as specified originally. An expansion
beyond the agreed named deduction/income categories, or a deferral of any required
row above, requires the user's explicit scope decision. Professional tax review
and hosted commissioning are separate outstanding release gates.

**Closed in this continuation:** IT-REVIEW-001 required-own-base validation;
finite acceptance inventory. **Still open:** all calculation rows marked pending
above. No new mixed-allocation interpretation has been certified by the reviewer
fix. Source inputs were frozen before final validation; results and manifests are
appended to the validation document.
