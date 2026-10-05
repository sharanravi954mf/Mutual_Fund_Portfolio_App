# EMI Calculator V1 implementation plan

Saved before implementation on 2026-10-05. This is historical planning evidence.
Base: `b9edc2f0bd2bde3540a10c191012c2063a28533e`, verified against a fresh
`origin/develop` with clean canonical `develop`. Work is isolated on
`feature/calculators-emi-v1` in `/home/ubuntu/moneybowl-worktrees/calculators-emi-v1`.
Delivery is one local commit; no push, PR, merge, deployment or hosted testing.

## Current architecture and reuse decision

Explorer already opens `CalculatorsHomeScreen`. Its immutable
`calculatorCatalog` contains one definition with a stable ID, title, description,
Material icon and screen builder. Append `emi` as calculator #2; preserve
`loan-part-payment` and the existing hub/navigation.

Keep Loan Part Payment's financial engine, controller and screen unchanged.
Move only the immutable `AmortizationRow` to `models/amortization_row.dart`,
re-exporting it from the old model for source compatibility. Extract the existing
row rendering/paging into `AmortizationSchedulePager`, accepting rows and a
calculation timestamp. The original `LoanAmortizationSchedule` remains the
scenario/title/notes wrapper and retains its keys and behavior. EMI supplies its
own title and notes. Do not extract a shared financial engine: preserving the
established part-payment outputs outweighs the small formula duplication.

## Independent financial contract

`EmiInput`: principal (double rupees), tenure (integer), `TenureUnit` (months or
years), annual percentage (double). `normalizedMonths` converts years × 12.
Months accept 1–600; years accept 1–50. Fractions and exponent syntax are rejected.
Switching units clears tenure text, tenure errors, result, timestamp and schedule;
no value is reinterpreted. Reset returns to empty fields and Months.

`EmiResult`: original input, monthly EMI, normalized months, total interest,
total repayment and one immutable schedule. No calendar dependency in domain.
Each row has month number, opening, payment, interest, principal and closing.

For `r = annualRatePercent / 12 / 100`, `EMI = P*r / (1-(1+r)^(-n))`.
At zero interest, `EMI = P/n`. For tiny positive rates use an equivalent
discounted geometric sum, avoiding subtraction of nearly equal numbers.

The monthly model is `interest = opening*r`, `due = opening+interest`,
`payment = min(EMI,due)`, `principal = payment-interest`, `closing = due-payment`.
Use the algebraically equivalent geometric principal progression to evaluate
balances robustly: `S = S*(1+r)+1` repeated n times, initial principal step P/S,
and multiply the step by (1+r) each month. This is the same technique already
validated by V1.1. A pre-implementation local numerical experiment at P=1e10,
n=600, annual=30 found a naive repeated balance recurrence perturbs the final
payment by approximately ₹78.55, exceeding the ₹0.01 reconciliation tolerance.
The stable evaluation avoids amplifying early subtraction errors. Every emitted
row must reconcile with the monthly model, not merely with the progression.

Use full double precision without monthly rounding. Check finite, nonnegative
values and row identities within `max(P, EMI)*1e-12`; final closure is permitted
only within that roundoff tolerance. Pay the smaller remaining due on the final
row; never overpay, append a dust month, or discard a material residual. Reject
unrepresentable tiny amounts safely. The schedule must have at most n rows.
Total interest and repayment are sums of their row components; principal sums
back to P within tolerance. Formatting never feeds back into mathematics.

## Input, state and privacy

Own `EmiController` with explicit Calculate/Reset, safe field errors, injected
clock and ephemeral result. Capture time once per Calculate, retain it through
paging/rebuild, and invalidate it with every input edit. Principal is finite,
>0 and <=₹10,00,00,00,000; annual rate is finite, 0–30. Reuse existing plain
decimal convention, whitespace trimming and 64-character bound. Reject NaN,
Infinity, exponents, currency symbols and commas. Retain text on failure;
never clamp or include supplied values in exceptions/logs.

No services, repositories, persistence, restoration, storage, network, URLs,
analytics or logging. Extend the static import/privacy boundary and exercise
EMI with network construction blocked and debug output captured.

## Presentation, calendar and accessibility

Own EMI Calculator screen: loan amount, loan tenure, accessible native Months /
Years choice chips, rate, Calculate and Reset. Use the existing MoneyBowl theme,
`intl` Indian currency formatting and tabular monetary figures. Summaries show
monthly EMI, total interest, total repayment and normalized months, also showing
original years when selected. Include the specified constant-rate monthly
reducing-balance disclaimer and nonbinding/lender-advice disclaimer.

Month 1 is next calendar month after captured calculation time, computed using
calendar year/month arithmetic, never a guessed EMI day. Use existing English
`MMM yyyy` symbols. Explain that calendar months are illustrative and the
lender's actual EMI date may differ.

Mount at most 12 rows. Previous/Next controls show `Months 1–12 of 120`, disable
at bounds and reset to page one for new results/scenarios. Stacked labelled cards
on narrow layouts; a table on sufficiently wide layouts accounting for text
scale, with local overflow containment. No page-level horizontal scrolling.
Natural-height wrapping layouts at 320/390/768/1440px, 1x/2x text, light/dark.
Inputs/buttons/choices have at least 48px targets and semantic labels/state.
Errors and schedule content remain understandable without color or hover.

## Intended files

- Add `models/emi.dart`, `models/amortization_row.dart`, `domain/emi_calculator.dart`.
- Add `presentation/emi_controller.dart`, `presentation/emi_screen.dart`,
  `presentation/amortization_schedule_pager.dart`.
- Modify catalog, old row model (compatibility export) and old schedule wrapper.
- Add EMI domain, controller, screen and pager tests under `test/calculators/`;
  extend privacy coverage and preserve every existing part-payment regression.
- Add `EMI_CALCULATOR_V1.md`; update `CALCULATORS_V1.md` and `docs/CHANGELOG.md`.
- No dependencies, auth, MFD, NSE, CAMS, portfolio or backend changes.

## Test matrix and delivery gates

Before source edits: all existing `test/calculators` plus
`test/authentication/explorer_entry_test.dart`, with exact counts recorded below.

Domain: locked 1,000,000 / 120 / 8.5 and identical 10 years; first/final rows;
zero interest; one month; decimals; max amount/600 months/50 years/30%; tiny
positive rates; malformed/invalid ranges; immutable schedule. Run accounting,
continuity, finiteness, positivity, totals and payment-count invariants across a
deterministic boundary grid. Unit values: months 1/12/120/600, years 1/10/50 and
rejected zero/negative/fraction/over-limit values in both parsing and domain.

Controller/widgets: explicit calculation, retained text/errors, reset/edit/unit
switch invalidation, units/equality, formatting, privacy, catalog IDs/navigation.
Frozen 05 Oct 2026 labels Nov/Dec 2026, Jan/Nov 2027; clock read once, new
calculation recaptures time. Pager lengths 1/11/12/13/25/120/600, first/final
controls, partial pages, replacement/reset with no stale rows. Responsive/theme/
scale matrix and semantic/touch-target checks.

Preserve Loan Part Payment locked EMI/revised EMI, 103-month tenure, savings,
first/last schedule rows, calendar labels and paging. Run all calculator tests,
Explorer regression, full Flutter suite, changed-file format/analyze, local
release web build, docs/migration-history/commit validators and diff/scope audit.
Report existing Wasm/font warnings separately. Commit once after passing gates.

## Explicit exclusions

No prepayment in EMI, fees, taxes, insurance, daily-interest model, fractional
years, floating-rate forecasts, lender comparisons/APIs, saved scenarios, export,
PDF, CSV or new calculator placeholders. No migration, RPC, Edge Function,
hosted DEV/Production access, main/canonical source mutation or remote delivery.

## Baseline result before source edits

Flutter 3.44.6 / Dart 3.12.2. Offline dependency resolution succeeded.
`flutter test --no-pub --reporter expanded test/calculators test/authentication/explorer_entry_test.dart`
passed **98 tests** in 37 seconds (90 calculator tests, 8 Explorer tests).
The first attempt could not bind Flutter's localhost test socket under the
sandbox and loaded no tests; rerunning with local socket permission passed.
Logs: `/tmp/moneybowl-emi-v1-evidence/baseline-retry.log`. No source edits
preceded this successful baseline.

## Implementation Deviations

None in architecture or feature scope. The geometric principal evaluation and
row/pager-only extraction were chosen in this plan before source edits. The
existing financial engine/controller/screen and original regression tests remain
unchanged. Test harness scrolling and semantics cleanup were corrected during
validation; no product requirements or assertions were weakened.
