# Loan Part Payment V1.1 implementation plan

Saved before implementation on the verified fresh base
`d5b61381485eea5a267c2ae25db73fc19455d006`. Work is isolated in
`feature/calculators-loan-part-payment-schedule-v1`. The historical V1 plan is
unchanged. One local commit only; no push, PR, merge or deployment.

## Existing contract

V1 has immutable loan inputs/results, two scenario result types, a pure Dart
calculator, a screen-local controller and an independent catalog/hub. Current
EMI is derived from four existing inputs using the monthly reducing-balance
formula. The tenure simulator returns a count and final payment but no rows.
Keep the EMI formula, four inputs, validation limits (₹1,000 crore, 600 months,
30% p.a.), currency formatting, routes and catalog unchanged.

## Domain extension

Add a pure immutable amortization row with relative month number, opening
outstanding, payment, interest component, principal component and closing
outstanding. Expose immutable schedules and total interest through the scenario
models; expose baseline schedule/remaining interest through the aggregate result
to make reconciliation directly testable.

Refactor the existing private simulation into one authoritative bounded engine.
For each month, compute interest = opening * monthlyRate; due = opening +
interest; payment = min(scheduledPayment, due); principal = payment - interest;
closing = due - payment. Sum the actual row interest, never total payments or
principal, to calculate interest payable. Revised tenure and final payment come
from those same rows. Investigate long-tenure/high-rate numerical conditioning;
only negligible roundoff may be normalized, never a material accounting error.

Generate three schedules with this engine:

1. Baseline: original P, calculated EMI and original n.
2. Reduce EMI: P2 = P - partPayment, revised EMI and original n.
3. Reduce tenure: P2 and original EMI, ending at payoff within n months.

Zero payment reuses the baseline for exact scenario identity. Full repayment
has empty scenario schedules, zero future interest and full baseline interest
savings. At 0%, every interest component and savings value is zero. The immediate
part payment is excluded from the monthly rows. Fixed-tenure schedules have n
rows except full repayment. The final payment may be smaller than regular EMI;
no dust-payment month may be added. Use full double precision and display-only
rounding. Document tolerances for row reconciliation, payoff and interest savings;
materially negative savings or failed reconciliation must raise a safe invariant
failure rather than silently hiding the defect.

Interest saved = baseline schedule interest sum - scenario schedule interest
sum. Principal and the part-payment amount never enter this difference as
interest. Normalize only tiny negative floating-point differences to zero.

## Calendar and controller strategy

The financial domain has no clock. Inject `DateTime Function()` into the local
controller (default `DateTime.now`). Capture it once per explicit Calculate,
associate the timestamp only with a successful result, and clear it on edit,
reset or failed calculation. The screen can inject the clock for widget tests.
Month 1 labels the next calendar month after calculation; month k advances k
calendar months, preserving relative monthNumber. Display `Month 1 · Nov 2026`,
never an invented day/due date. Date rollover and later rebuilds must be tested
with a frozen clock. State explicitly that the payment is assumed applied now,
before the next EMI, and calendar months are illustrative.

## UI and pagination

Extend the existing current EMI summary with baseline remaining interest and
each scenario card with interest payable and prominent but secondary savings.
Add a focused schedule presentation component below the scenario cards. Use
accessible Material choices for Reduced EMI / Reduced tenure, defaulting to
Reduced EMI to match scenario order. Only the selected scenario is rendered.

Page in groups of 12 rows, showing Previous, Next and `Months X–Y of Z`. Reset
to page one on scenario switch, calculation replacement and reset. Remove the
entire schedule on input edit/failure. Wide screens show a compact table; narrow
screens or large text show vertically stacked monthly cards with all six fields.
No page-level horizontal scrolling or unbounded 600-row widget tree. Use existing
theme, Indian currency to two decimals, semantic labels and >=48px targets.
Full payoff displays the requested no-future-schedule message.

## Privacy and files

All rows, totals, selected scenario, page and timestamp remain ephemeral local
state. No services, database, Supabase, RPC, HTTP, analytics, storage, URL values,
logs or error telemetry. Preserve the import-boundary test. No dependency change.

Modify only calculator models/domain/controller/screen and their tests, plus
`docs/architecture/CALCULATORS_V1.md` and `docs/CHANGELOG.md`. Add the schedule
presentation file and focused schedule tests if separating them improves clarity.
Do not edit hub/catalog, onboarding source, old implementation plan, migrations,
dependencies or other modules.

## Validation and review matrix

Before source changes: run existing `test/calculators/`, Explorer entry tests,
route guards and MFD application regressions. Retain baseline evidence externally.

Retain all existing numeric tests and 800 invariant combinations. Add locked
interest totals and first/last row examples; row identities/continuity, nonnegative
finite values, final payoff/payment cap, sum-to-summary reconciliation, schedule
length, zero/full payment, zero rate and 600-month bounds. Test immutable schedules
and safe invariant failure handling. Freeze October 5, 2026: month 1 November,
month 2 December, month 13 November 2027; also year rollover and rebuild stability.

Paging coverage: 1, 11, 12, 13, 25, 120 and 600 months; first/next/previous/last
partial pages, selector reset, recalculation reset, input edit/failure/reset
removal. Extend current 320/390/768/1440px normal/2x light/dark tests to both
schedule presentations and controls. Validate selectors/pagers/row semantics.

Run format, scoped analyzer, calculator/domain/controller/widgets/privacy tests,
Explorer and relevant existing regressions, full Flutter suite, local release web
build, docs/migration-history/commit validators. Report existing Wasm/font warnings
separately. Manually inspect all 15 requested consistency/privacy checks before
the single local commit; verify canonical source and candidate cleanliness.

Append Implementation Deviations here if implementation materially changes this
plan; do not rewrite this planning record.

## Implementation Deviations

The engine uses an algebraically equivalent principal-component recurrence to
avoid amplifying cancellation in `EMI - interest` across long schedules. A direct
forward double simulation at the existing synthetic ₹1,000 crore / 600-month /
0.1% boundary leaves approximately ₹0.0127 after the contractual final payment,
which exceeds the selected ₹0.01 reconciliation tolerance for that principal.
Discarding an arbitrary residual, as the V1 count-only simulator could do at its
bound, is insufficient for a row-level accounting contract.

For a reference principal P, compute the geometric growth sum
`S = sum((1+r)^j, j=0..n-1)` iteratively, then first principal component `P/S`.
For a part payment A while retaining EMI, add `A*r`. Each subsequent regular
principal component multiplies by `(1+r)`. Payment still uses
`min(scheduledEMI, opening + interest)` and interest still uses `opening*r`.
Validate both row accounting identities within `max(P, EMI)*1e-12`; normalize
only payoff dust within that tolerance. Final payments differ from regular EMI
when materially smaller. Fixed contractual last payments differing only by dust
retain their scheduled value, preserving V1's exact zero-payment identity.
At zero rate, principal component equals payment exactly. A material residual
or failed row identity raises a value-free invariant exception and a safe UI
message; it never produces a misleading schedule. No input limit changed.

English calendar labels use intl's bundled `en_US` date symbols, avoiding a
locale-initialization dependency discovered by standalone widget tests. Money
continues to use `en_IN`. This does not change the specified month labels.
