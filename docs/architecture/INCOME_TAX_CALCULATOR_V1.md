> **Current bounded V1 status (2026-10-05): local implementation and frozen automated validation complete; independent review and hosted commissioning remain outstanding.** The older status immediately below is preserved as historical evidence. See the [release contract](INCOME_TAX_CALCULATOR_V1_RELEASE_SCOPE.md) and [validation](INCOME_TAX_CALCULATOR_V1_VALIDATION.md#bounded-v1-release-validation--2026-10-05).

> Current status (2026-10-05): **PARTIAL LOCAL IMPLEMENTATION, UNCOMMITTED — NOT RELEASE READY**.
> The component-gated resumption appendices below supersede the earlier global stop.
> Historical blocked findings and evidence are intentionally retained.

# Income Tax Calculator V1 — blocked research candidate

> Current bounded release contract: [scope](INCOME_TAX_CALCULATOR_V1_RELEASE_SCOPE.md), [pending and blocked work](INCOME_TAX_CALCULATOR_V1_PENDING_AND_BLOCKED.md), and [DEV commissioning runbook](INCOME_TAX_CALCULATOR_V1_DEV_COMMISSIONING.md). This explicit revision preserves the original implementation history below. Only verified supported combinations may produce a comparison; a deferred circumstance withholds both regimes.

Status on 2026-10-05: **INCOMPLETE / BLOCKED BEFORE IMPLEMENTATION**.

Income Tax Calculator is not in the application catalog. No engine, UI,
controller, executable tax rules or feature tests have been added. The existing
Loan Part Payment, EMI and SIP calculators remain the complete working catalog.
This document records the intended boundary, not delivered support.

The requested feature would compare Old/New regimes for resident ordinarily
resident individual taxpayers for FY 2025–26 (1 April 2025–31 March 2026,
AY 2026–27, Income-tax Act 1961) and Tax Year 2026–27 (1 April 2026–31 March
2027, Income-tax Act 2025). Normal and Advanced would share one pure Dart engine.
Intended supported heads are salary/employment pension, specified ordinary
interest, domestic dividends, ordinary family pension, bounded house property,
and already-computed eligible equity STCG/LTCG, with only the requested
deductions and optional tax credits.

The [implementation plan](INCOME_TAX_CALCULATOR_V1_IMPLEMENTATION_PLAN.md)
defines architecture, intended computation stages, presentation, privacy and
acceptance gates. The [source register](INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md)
records inspected provisions and precise blocking verification gaps. The
[validation record](INCOME_TAX_CALCULATOR_V1_VALIDATION.md) distinguishes passed
baseline checks from implementation checks that have not run.

No final formulas/order, component rounding allocation or maintenance-ready
rule packs are certified. B1 (combined capital-gain shortfall), B2 (mixed-income
surcharge attribution/relief) and B3 (subsequent-amendment review) must be resolved
before implementation. The developer must then finish every remaining source
row, independently derive boundary fixtures and complete all local checks.
Rules must remain versioned by explicit income period; no automatic earlier or
future-year reuse is permitted.

The intended exclusions remain non-residents/RNOR, non-individual entities,
business/AMT, foreign income/assets/relief, agricultural integration, brought-
forward or capital losses, other special-rate categories, complex retirement/
perquisite calculations and salary-arrears relief, unimplemented deductions,
complex property situations, filing, advance-tax scheduling, fees and penalties.
The intended calculator is a bounded estimator, not an ITR preparation system.

No hosted activity, authorization change, financial-data transmission,
persistence or deployment occurred. Tax-professional signoff and hosted
commissioning remain separate, unperformed release gates. No feature commit
was made and there is no deliverable tax calculator to commission.

## Resumption evidence — 2026-10-05

The original blocked history above is preserved. Gazette 275521 was securely
available in the verified handoff and has now been reviewed. The planned
ordinary company-dividend input must explicitly reject REIT/InvIT/business-trust
distributions. The wider subsequent-amendment review is not certified complete.

Static inspection covered both the supplied AY 2026–27 ITR-2 v1.3 utility and
the v1.4 release now listed on the official site. No macros ran. A material
active surcharge-cutoff discrepancy persists in both: for only eligible equity
LTCG of 5000800, resident below 60, the New Regime static formula gives 598830
after cess/rounding, while the statutory ceiling gives 582580. The corresponding
Old amounts are 618330 and 602080. These are independent arithmetic reproductions,
not executed official-calculator outputs. See the [exact provision/formula trace](INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md#b2--active-dependency-trace-and-material-conflict-b2-mr-112a-50l).

The complete mixed-income method, component rounding reconciliation and other
unfinished register rows remain blocked/unverified. No scope reduction, tax
implementation, feature test, source change or local commit has followed.
The existing three calculators and authorization/privacy boundaries are intact.

## Current component implementation — 2026-10-05

The original global research stop was superseded by the user's component-level
verification gate. Income Tax Calculator now exists in the local catalog. The
full original scope remains the target; this candidate is not ready to publish.
No feature commit is authorized until all remaining scope and required checks
pass. Earlier blocked history above remains evidence, not the current source state.

### Architecture and computation contract

Independent code lives in `lib/features/calculators/income_tax/`:

- `models/tax_input.dart`: closed typed categories, eligibility/unsupported/pending
  cases, immutable copied amounts and HRA periods; no unrestricted deduction.
- `models/tax_result.dart`: immutable comparison, invalid, unsupported and
  not-yet-verified outcomes; immutable audit trace and deduction decisions.
- `domain/exact_amount.dart`: normalized BigInt rational rupees. Financial input
  accepts unsigned decimal rupees, at most12integer/2fractional digits, no exponent,
  commas or non-finite numbers. All products use BigInt; binary doubles do not
  determine thresholds. Formatting is separate from statutory rounding.
- `domain/tax_rules.dart`: exhaustive supported-year selector, independent version
  IDs, Act/period/source bindings and separately selected ordinary schedules.
  No future/earlier-year fallback. Shared exact computation helpers are used only
  for rules separately verified to coincide.
- `domain/income_tax_engine.dart`: one engine for both modes, atomic comparison.
  If either regime needs an unresolved rule, no regime estimate escapes.
- Dedicated `tax_deductions.dart`, `tax_exemptions.dart`, `house_property.dart`,
  `special_income.dart` own their respective formulas and component limits.
- `presentation/income_tax_controller.dart`: ephemeral form state, parsing,
  explicit calculation, stale-result invalidation, eligibility reconfirmation
  after year changes, and reset. Mode changes do not change mathematics.
- `presentation/income_tax_screen.dart`: responsive themed forms, comparison,
  expandable audit/decisions and static selectable official reference URLs.

Sequence: classify gross heads; add employer NPS only if absent from gross
salary; compute period HRA; salary standard deduction once; professional tax
Old only; family pension separately; property NAV/statutory deduction/interest,
then intra-head aggregation and permitted inter-head use; Chapter deductions
limited to eligible ordinary income; round statutory total; reconcile components;
ordinary/special-rate tax; separate rebate and rebate relief; surcharge and its
separate relief;4%cess; liability; eligible entered credits; balance/refund.
The immutable trace is ordered by typed statutory stage and records exact
fractions in addition to display amounts.

Own NPS is entered once. Allocation uses additional50000 first, then remaining
contribution subject to employee10%salary/other20%GTI and remaining150000
investment-group capacity. Employer NPS is outside that group. All Chapter
amounts are capped to remaining eligible ordinary income, never prohibited gains.
Health insurance/medical allowances fill each family/parent bucket before
preventive checks use the bucket's remaining room and shared5000limit. No
unused checkup allowance is consumed by a full bucket. Eligibility confirmations
cover approved insurance, payment mode, taxable-income funding, annual premium
apportionment and uninsured-resident-senior conditions. Insurance and medical
within a bucket must concern different people if both are claimed.

For ordinary or sole-gain surcharge, cutoff composition is the same sole tax
category as actual income. The cutoff calculation retains the basic exemption,
LTCG annual threshold and applicable previous-band surcharge. Cap nominal tax
plus surcharge at cutoff tax plus surcharge plus excess income; apply cess after
relief. Mixed counterfactuals are explicitly gated, never pro-rated by assumption.

Rounding uses288A/288B or516: ignore paise then round rupees to nearest10, digit5
upward. Ordinary-only rounding affects ordinary income. Sole-gain rounding
changes the sole gain component with ordinary fixed at zero. In admitted mixed
cases, ordinary residual=roundedtotal−rawST−rawLT; show its adjustment. Negative
residual or combined-gain unused-basic-exemption cases return no estimate.
LTCG annual125000 is a tax-base threshold and stays in statutory total income
for rebate/surcharge testing. The final payable/refund is independently rounded
from **exact liability minus entered credits**, not the already-rounded headline.

### Presentation, privacy and limitations

Normal handles salary, savings/deposit interest, named investment/NPS and health
inputs. Advanced adds detailed salary/HRA, other sources, property, education,
gains and credits. When advanced financial data exists, switching to Normal
keeps its sections visible with a retention notice. Year changes retain amounts
and factual choices, invalidate results and clear eligibility attestations for
reconfirmation. Dates/periods are revalidated. Reset clears all form state.

No PAN/Aadhaar, identity, employer name, bank/policy number or documents are
requested. There are no network/storage/logging dependencies in the feature.
Static URLs are selectable for the user's explicit copy/open action; automatic
opening is absent. The view owns and disposes the controller; navigating away
discards entries. Existing account authorization and service code are untouched.

Original exclusions remain: nonresident/RNOR/nonindividual; business/AMT;
foreign/agriculture; brought-forward/capital losses; other special-rate income;
complex salary/retirement; unimplemented deduction categories; complex property;
return filing, instalment planning, late interest/fees/penalties. REIT/InvIT/pass-
through distributions have a dedicated unsupported selection. Additional80C
instruments have a pending selection, which suppresses estimates rather than
being silently absorbed into another field. Professional/hosted signoff has not
occurred. The [coverage matrix](INCOME_TAX_CALCULATOR_V1_VALIDATION.md) identifies
which target interactions are still gated.

### Maintenance

For every change, identify affected income period/regime and stable rule IDs;
read enacted amendments and notified rules; append effective dates, verification
dates, source location/hash and interpretation; derive independent exact fixtures
before changing that component. Bump the affected rule-pack version when behavior
changes. Run component, boundary, privacy, UI, existing-calculator and full-suite
checks plus the release build. Never roll a pack forward by date or remove a gate
without evidence. Keep historical comparator discrepancies and professional review
separate from production expectations. No database-driven rule editor is used.

### Additional pending inputs

Post-office savings/special interest exemptions and multiple-employer NPS each
have explicit pending selections. The former still requires the applicable
notification and two-year savings-clause binding; the latter needs separate
employer contributions and salary bases. Either selection suppresses the entire
comparison. They must not be entered as ordinary taxable interest or a single
aggregated employer solely to obtain a result. This retains the original scope
as unfinished work, alongside the other interaction gates in the source register.

## Continued candidate — 2026-10-05, rule revision2

This append-only update supersedes pending statements for the components closed
in the [current source matrix](INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md#current-rule-to-test-closure-matrix-local-rule-pack-revision2).
Normal and Advanced still share one pure engine. The form now guides life
insurance (issue date/assured amount/beneficiary), two children's tuition,
qualifying housing principal/transfer payments and NSC subscriptions/accruals.
The investment group remains150000, with no unrestricted deduction override.
NSC interest is included once; senior-interest classification remains gated.

Each employer has its own contribution, statutory salary base, government/other
category and salary-inclusion choice. Separate percentage caps cannot transfer
unused capacity between employers. The combined bases and already-included NPS
cannot exceed gross salary. Computed taxable perquisites must already be supplied.
Contractual turnover-percentage commission is included in the verified HRA salary
base in both years, with the year-specific city groups.

For ordinary-only cases, current salary loss is applied before capped Old
property loss; positive ordinary income without an interest deduction absorbs
loss first, preserving the permitted interest deduction. The trace shows loss
use, unabsorbed loss and allocation into eligible interest. No negative head is
silently discarded. One individually held Post Office Savings Bank account has
its3500 exemption applied before the residual eligible interest deduction.
Pure company-dividend income uses ordinary slabs and the15% surcharge ceiling,
with independent cutoff relief. Other positive-income mixtures needing dividend
attribution remain gated.

All old financial entries remain local and visible across mode changes. New
repeated rows, account eligibility and per-employer salary bases also invalidate
stale results. Reset removes every row. No network, storage, logs, provider,
identity or authorization integration was introduced.

The complete original target remains **INCOMPLETE / NOT RELEASE READY**. Remaining
branches are specified in the source matrix; safety tests that confirm a blocked
result do not count as completed tax requirements. The dated bounded amendment
review now includes the securely retrieved Notification97/2026 and inspected
Circular7/2026; it is not a claim that search proves an exhaustive absence of
later amendments. The B2 utility discrepancy remains static reproduction only.
Professional signoff, hosted commissioning and interactive comparator execution
have not occurred. Progress remains uncommitted pending the full scope.


## Reviewer correction: required own-NPS salary base

On5October2026, IT-REVIEW-001 corrected missing-input handling in both packs.
Employees must enter the own-NPS statutory salary base when a contribution can
still use the percentage-limited investment group after the additional deduction.
Blank is unknown, not zero. Explicit0 is permitted only as a declaration that the
specified qualifying salary components actually total zero; existing eligibility,
nonnegative and gross-salary consistency checks apply. Gross salary and employer
bases are never substituted. Additional-only contributions, exhausted eligible
budgets and supported nonemployee calculations do not require this independent
base. Invalid inputs suppress both regimes and any winner. Editing or clearing
an input invalidates prior results immediately.

The implementation plan now contains a finite acceptance register with named
income interactions, interest exemptions, investment instruments and recapture
branches. Those pending requirements have not become exclusions. This remains
an uncommitted, incomplete local candidate, not ready for publication.

## Bounded local V1 release contract — 2026-10-05

The user explicitly replaced the earlier all-37-entry completion gate with the
[bounded release contract](INCOME_TAX_CALCULATOR_V1_RELEASE_SCOPE.md). The
[pending and blocked document](INCOME_TAX_CALCULATOR_V1_PENDING_AND_BLOCKED.md)
maps each historical ID without deleting the original analysis. Rule packs are
now revision3 for FY2025–26/AY2026–27 and TY2026–27, because named guided bank
five-year, post-office five-year, SCSS and Sukanya contributions were added to
the shared Old-Regime ₹1.5 lakh investment budget. The distinct enactments and
scheme notifications are in the [source register](INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md#scoped-v1-investment-source-gate--2026-10-05-before-code).

The group is capped once at ₹1,50,000 after instrument-level eligibility and
available-income limits. The deduction trace allocates that shared budget in
the form's fixed instrument order solely to explain entered, allowed and
disallowed rows. The total allowable deduction and tax are invariant to that
display allocation; no statutory priority between eligible instruments is
claimed. Interest is entered separately as income where supported.

`IncomeTaxEngine.calculate` is the sole supported-case authority. Direct callers
and the UI receive one typed outcome: invalid input, explicitly excluded case,
deferred verification, unexpected calculation failure, or a complete two-regime
comparison. The presentation renders that outcome and never calculates tax or
decides a regime independently. Deferred checks inspect amounts, year, age,
income mix and both regime calculations; declarations cover facts amounts cannot
reveal. No partial regime, savings, winner or credit balance escapes if either
regime is unavailable. Actual-control and direct-engine tests cover the boundary.

Normal remains a practical salary/pension, interest and guided-deduction path;
Advanced retains detailed HRA periods, employer NPS, property, supported equity
gains, dividends and credits. The category names do not promise every mixture.
For example, simultaneous eligible STCG and LTCG with unused basic exemption,
mixed special-income surcharge above ₹50 lakh, gain-related property/salary loss,
negative NAV and enhanced-band mixed dividend attribution still return no
estimate. The independent positive fixtures for sole and currently verified
ordinary/gain branches remain in force. The rules view reports actual Act,
period, rule version, verification date and official source URLs.

All financial inputs and traces remain in screen memory only. Changing year,
mode, age, eligibility or any value invalidates stale results; Advanced values
remain visible after switching to Normal. Reset and route disposal clear them.
There is no database, telemetry, URL encoding, browser storage or automatic
financial-data request. Independent professional review and [controlled DEV
commissioning](INCOME_TAX_CALCULATOR_V1_DEV_COMMISSIONING.md) remain separate
release gates. This architecture note does not claim those checks occurred.
