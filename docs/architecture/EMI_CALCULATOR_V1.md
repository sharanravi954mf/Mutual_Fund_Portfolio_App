# EMI Calculator V1

Local candidate based exactly on verified fresh `origin/develop`
`b9edc2f0bd2bde3540a10c191012c2063a28533e`. The
[implementation plan](EMI_CALCULATOR_V1_IMPLEMENTATION_PLAN.md) was saved before
source edits. Branch: `feature/calculators-emi-v1`; worktree:
`/home/ubuntu/moneybowl-worktrees/calculators-emi-v1`.

## Catalog and ownership

The existing Explorer → Calculators route and hub are unchanged. The immutable
catalog retains `loan-part-payment` first and appends `emi`, titled **EMI
Calculator**, with `Icons.calculate_outlined` and the description “Calculate your
monthly EMI, total interest and complete repayment schedule.” Back returns to the
same hub. No placeholder entries or new hub are added.

| Layer | File and responsibility |
| --- | --- |
| Input/result | `models/emi.dart`: `EmiInput`, `TenureUnit`, immutable `EmiResult` |
| Financial domain | `domain/emi_calculator.dart`: validation, formula and authoritative schedule |
| Ephemeral state | `presentation/emi_controller.dart`: parsing, Calculate/Reset, unit switching and injected clock |
| Screen | `presentation/emi_screen.dart`: form, summary, schedule and disclaimers |
| Shared record | `models/amortization_row.dart`: six immutable fields; no dates |
| Shared viewer | `presentation/amortization_schedule_pager.dart`: bounded page, month labels, cards/table |

EMI has no dependency on the Loan Part Payment input/result or controller. The
old model re-exports the moved row type for source compatibility. Only row and
viewer infrastructure is shared. `LoanAmortizationSchedule` still owns Reduced
EMI / Reduced tenure selection, its explanatory text and full-payoff state.
Changing or reselecting a scenario resets to the first page. Loan Part Payment's
financial engine, controller and screen remain byte-for-byte unchanged.

Future catalog entries follow the extension steps in
[Calculators architecture](CALCULATORS_V1.md#purpose-and-extension-point).

## Input contract and state transitions

| Input | Accepted values |
| --- | --- |
| Loan amount | Finite decimal rupees, >0 and <=10,000,000,000 (₹1,000 crore) |
| Loan tenure, Months | Whole integer 1–600 |
| Loan tenure, Years | Whole integer 1–50; normalized months = years × 12 |
| Interest | Finite decimal annual percentage, 0–30 inclusive |

The normalized month count belongs to the domain input and is exposed by the
result. 10 years and 120 months execute identical mathematics and return
identical row fields and totals. The summary preserves the original unit, e.g.
`10 years · 120 months`. Use Months and enter 126 for 10 years 6 months.

The parser follows the existing plain-decimal convention: surrounding whitespace
is allowed; amount/rate decimals are allowed; tenure is digits only. No commas,
currency symbols, exponent notation, NaN, Infinity, fractional tenure or strings
longer than 64 characters. Values are never clamped or rounded into range. Domain
validation also protects direct callers. Unrepresentable EMI underflow fails
with a safe amount error; errors contain no supplied financial values.

Calculate (or the explicit keyboard Done action) validates and captures time
once. Successful calculation exposes one new result and scrolls to it; validation
failure preserves entered text and focuses the first invalid field. Edits clear
the prior result, timestamp and schedule immediately. Changing units clears the
tenure text and its error without reinterpreting the number, and removes all
prior results. Choosing the current unit leaves the entry unchanged. Reset
clears fields/errors/results and restores Months. Route disposal releases all
screen text controllers, focus nodes and calculation state.

## Formula and one authoritative schedule

Let P be principal, n normalized months and r = annualRatePercent / 12 / 100.

```text
if r == 0: EMI = P / n
otherwise: EMI = P * r / (1 - (1+r)^(-n))
```

For `r*n < 0.001`, compute the equivalent discounted annuity factor with
`q=1/(1+r)` and `factor=(factor+1)*q` repeated n times, then EMI=P/factor. This
avoids cancellation for tiny positive rates. All calculations use unrounded
double precision; the displayed two-decimal EMI is never used as a payment input.

The monthly financial recurrence is:

```text
interest = openingOutstanding * r
amountDue = openingOutstanding + interest
payment = min(EMI, amountDue)
principalComponent = payment - interest
closingOutstanding = amountDue - payment
```

The engine evaluates principal/balance through the equivalent geometric
progression, preventing early subtraction error from amplifying over 600 months:

```text
S = 0
repeat n times: S = S*(1+r) + 1
principalStep = P/S
each month: principalPaid = min(principalStep, opening)
            closing = opening - principalPaid
            principalStep *= (1+r)
```

Payment and interest still use the monthly recurrence. Check every emitted row
against both accounting identities and require all five monetary values finite
and nonnegative, with positive sequential month numbers. The check/payoff
tolerance is `max(P, EMI)*1e-12` (approximately ₹0.01 at maximum principal).
Only a balance within that tolerance becomes zero. The final principal component
then uses the opening balance, and the final payment is always
`min(EMI, amountDue)`, so there is no overpayment. The row reconciles within the
documented tolerance. Zero-rate rows explicitly use principal=payment and
interest=0. A material residual causes a safe calculation error; it is never
discarded or turned into a 601st row.

This stable evaluation was planned before source edits. A naive recurrence at
P=1e10, n=600, annual=30 perturbed the last payment by approximately ₹78.55. The
geometric recurrence removes that amplification and checks closure against the
same monthly accounting model. No shared financial engine refactor was needed.

`EmiResult` copies rows into an unmodifiable list. **Total interest** is the sum
of row interest components; **total repayment** is the sum of row payments. These
are calculated from the same rows displayed by the viewer. The tests require
principal components to sum to P within row tolerance and repayment to equal
P+interest within `max(P,totalRepayment)*1e-12`. Totals are never computed by
multiplying a rounded EMI or displayed values.

## Locked examples

| Input | Monthly EMI | Total interest | Total repayment | Rows |
| --- | --- | --- | --- | --- |
| ₹10,00,000 / 120 months / 8.5% | ₹12,398.57 | ₹4,87,828.27 | ₹14,87,828.27 | 120 |
| ₹10,00,000 / 10 years / 8.5% | ₹12,398.57 | ₹4,87,828.27 | ₹14,87,828.27 | 120 |
| ₹1,00,000 / 12 months / 0% | ₹8,333.33 | ₹0.00 | ₹1,00,000.00 | 12 |
| ₹1,00,000 / 1 month / 12% | ₹1,01,000.00 | ₹1,000.00 | ₹1,01,000.00 | 1 |

| Month (locked 120-month example) | Opening | Payment | Interest | Principal | Closing |
| --- | --- | --- | --- | --- | --- |
| 1 | ₹10,00,000.00 | ₹12,398.57 | ₹7,083.33 | ₹5,315.24 | ₹9,94,684.76 |
| 120 | ₹12,311.36 | ₹12,398.57 | ₹87.21 | ₹12,311.36 | ₹0.00 |

Values in these tables are display-rounded; internal acceptance uses tolerance.
At zero interest every row has zero interest and the final closing is zero.

## Calendar, pagination and accessible presentation

The domain has no clock. The controller accepts a `DateTime Function()` defaulting
to `DateTime.now`, called once per Calculate. The viewer uses captured year/month
plus the row's month number: month 1 is the next calendar month, without a day or
invented lender due date. With 05 Oct 2026, labels are Nov 2026, Dec 2026,
Jan 2027 and (month 13) Nov 2027. Paging and rebuilding retain this timestamp;
editing removes it and a new calculation captures a new one.

Only 12 rows are mounted at once. `Previous` / `Next` disable at bounds, with a
live range such as `Months 1–12 of 120`. New results start on the first page.
Narrow views use monthly cards labelling all five amounts; sufficiently wide
views (available width >=900×text scale) use a table with local horizontal
overflow containment for exceptionally wide amounts. No horizontal scrolling
is introduced at page level. The viewer contains no part-payment assumptions.

The MoneyBowl Material theme, `intl` Indian currency grouping and English
`MMM yyyy` symbols are reused without dependencies. Inputs and action/choice/
page controls have at least 48px touch targets, visible text labels, keyboard
support and semantic state. Forms/cards wrap naturally at 320/390/768/1440px,
normal/2x text, in both themes. Information does not depend on color or hover.
The two disclaimers explain the constant-rate monthly model and differences from
actual payment dates, daily interest, resets, fees, insurance, taxes and rounding;
the estimate is neither lender advice nor a binding repayment schedule.

## Privacy and exclusions

All financial values live only in ephemeral screen/controller/result objects.
There is no service/repository import, Supabase call, HTTP client, storage,
restoration identifier, logging, telemetry, analytics or URL encoding of input.
The static feature boundary covers both calculators and shared files; the EMI
widget test calculates, pages, switches units and resets with network creation
blocked and debug output captured. There is no auth/provider/backend prerequisite.

No saved scenarios, exports, PDF/CSV, prepayments in EMI, lender comparisons,
financial APIs, fractional years, fees/taxes/insurance estimates or floating-rate
forecasting. Double precision and two-decimal display are estimates, not paise-exact
lender accounting. Tiny amounts below display precision can display as ₹0.00.
No manual device/screen-reader certification or hosted testing is claimed.

## Local validation

Toolchain: Flutter 3.44.6, Dart 3.12.2; dependencies resolved offline using the
existing cache. Runner logs are outside the source tree at
`/tmp/moneybowl-emi-v1-evidence/`.

Before implementation: **98 tests passed** (90 existing calculators and 8
Explorer navigation tests). An initial sandbox attempt could not bind the local
Flutter test socket and loaded no tests; the authorized local-socket rerun passed.

Initial EMI test work found only harness scrolling/semantics-cleanup issues and
deprecated semantic test APIs; these were corrected without weakening checks.
The completed check results are recorded below.

Reproducible validation commands, with the existing Flutter SDK on PATH:

```sh
flutter test --no-pub --reporter expanded test/calculators test/authentication/explorer_entry_test.dart
flutter analyze --no-pub lib/features/calculators test/calculators test/authentication/explorer_entry_test.dart
flutter test --no-pub --reporter expanded
flutter build web --release --no-pub
python3 .github/scripts/validate_docs.py
python3 .github/scripts/validate_migration_history.py
python3 -m unittest discover -s .github/scripts -p 'test_validate_commits.py'
python3 .github/scripts/validate_commits.py 'feat(calculators): add EMI calculator and amortization schedule'
git diff --check
```

### Validation evidence

| Check | Result |
| --- | --- |
| Baseline before source edits | PASS: 98 tests (90 calculators + 8 Explorer), 37 seconds |
| EMI pure domain | PASS: 32 tests, including 180 boundary combinations and exact 10-year equivalence |
| EMI controller | PASS: 37 tests |
| EMI schedule/calendar/paging | PASS: 9 tests, including lengths 1/11/12/13/25/120/600 |
| EMI screen/navigation/accessibility/privacy | PASS: 24 tests, including all 16 width/theme/scale combinations |
| Calculator static privacy boundary | PASS: 1 test spanning both calculators and shared primitives |
| All calculator tests | PASS: 192 tests, including all 90 established regressions |
| Explorer navigation | PASS: 8 tests; combined calculator/Explorer run 200 tests in 64 seconds |
| Exact Loan Part Payment comparison | PASS: 800 cases, all summaries and every schedule field equal to verified base |
| Full Flutter suite | PASS: 666 tests in 232 seconds |
| Dart formatting | PASS: 14 changed Dart files, zero remaining formatting changes |
| Documentation quality/link audit | PASS: 45 Markdown files |
| Migration-history validation | PASS: 27 frozen files through 20260801000000; no migration/manifest diff |
| Commit validation | PASS: Conventional Commit message and all 5 validator unit tests |
| Scoped analyzer | PASS: no issues |
| Local release web build | PASS: JavaScript output in `build/web`, 151.5 seconds |
| Scope and whitespace audit | PASS: 12 added / 6 modified files, all in calculators or requested docs |

The exact base comparison extracts the two original pure-Dart files via
`git show` into the external evidence directory, runs the same 800 boundary
cases through the base and candidate, and compares serialized summaries and all
three schedules without numeric tolerance. The unchanged existing tests also
retain the locked ₹10,00,000 / 120 / 8.5% / ₹1,00,000 part-payment case:
current EMI ₹12,398.57, reduced EMI ₹11,158.71, 103-month reduced tenure,
interest savings ₹48,782.83 / ₹1,19,743.74, and final reduced-tenure payment
₹3,430.50 (interest ₹24.13, principal ₹3,406.37, closing ₹0.00). Calendar
labels, scenario switching and paging pass unchanged. Shared card/table row
renderers were also compared to the base, differing only in formatting.

Known pre-existing build warnings are reported separately from the passing build:
`dart:js` in `admin_dashboard.dart` and `excel_updater.dart` prevents the Wasm dry
run, and the Cupertino font family is not bundled. These warnings were already
recorded in [Calculators V1 validation](CALCULATORS_V1.md#test-coverage-and-local-validation).
This candidate does not claim Wasm support. No backend/dependency files changed.

All requested local automated checks ran. Hosted tests, lender/financial network
calls, manual device or screen-reader testing and deployment were not performed.
No migrations, hosted DEV changes, Production/main changes, financial data
persistence, push, PR or merge are part of this candidate. One local Conventional
Commit is the delivery boundary.
