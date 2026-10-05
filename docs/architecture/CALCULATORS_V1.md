# Calculators V1 — Loan Part Payment

Historical V1 candidate based on `d31c40058f2e542ff302234a8b92404437753647`.
The [original implementation plan](CALCULATORS_V1_IMPLEMENTATION_PLAN.md) was
saved before implementation. No hosted commissioning is part of this feature.

The sections below retain the V1 delivery record. The [V1.1 contract](#v11-interest-savings-and-month-wise-schedules)
extends it from merged base `d5b61381485eea5a267c2ae25db73fc19455d006`,
superseding the count-only simulation and result presentation described in V1.

## Purpose and extension point

`lib/features/calculators/` provides a reusable Calculators hub and independent,
typed calculation domains. The V1 catalog has one working calculator and no
placeholder destinations.

| Layer | Responsibility |
| --- | --- |
| `models/loan_part_payment.dart` | Immutable input, aggregate result and two scenario results |
| `domain/loan_part_payment_calculator.dart` | Pure Dart validation and deterministic monthly loan mathematics |
| `presentation/calculator_catalog.dart` | Immutable catalog of definitions: stable ID, display title, description, icon and `WidgetBuilder` |
| `presentation/calculators_home_screen.dart` | Renders catalog entries and opens their screens |
| `presentation/loan_part_payment_controller.dart` | Ephemeral parsing, safe field errors, explicit calculation/reset and result invalidation |
| `presentation/loan_part_payment_screen.dart` | Accessible form, formatted results and explanatory copy |

The catalog is deliberately presentation metadata, so icons and builders never
enter the financial domain. There is no formula DSL, expression engine,
database-driven catalog, shared calculator repository or plugin infrastructure.

To add calculator #2:

1. Add its independent pure Dart input/result models and calculation service.
2. Add deterministic contract and invariant tests for its own financial model.
3. Add a themed screen and screen-local controller if needed, with validation,
   privacy and responsive tests.
4. Add one `CalculatorDefinition` with a unique stable ID and screen builder to
   `calculatorCatalog`. The hub and Explorer need no changes.
5. Document its assumptions, precision and limits. Do not reuse this loan model
   for unrelated financial formulas.

## Inputs and validation contract

| Input | Interpretation | Accepted range |
| --- | --- | --- |
| Loan outstanding amount (P) | Principal immediately before payment, in rupees | Finite, > 0, <= 10,000,000,000 (₹1,000 crore) |
| Loan outstanding months (n) | Remaining contractual monthly instalments | Integer, 1–600 |
| Annual interest rate (a) | Annual percentage; 8.5 means 8.5% p.a. | Finite, 0–30 |
| Part payment (A) | Immediate principal reduction, in rupees | Finite, 0–P |

Upper bounds are technical limits for bounded execution and double-precision
conditioning, not claims about available lending products. They produce visible
field errors and are never silently clamped. Domain calls repeat validation;
presentation validation is not the only protection.

The screen accepts plain decimal amounts/rates with a decimal point, including
paste and surrounding whitespace. Months require digits only. It rejects empty
fields, nonfinite values, exponent notation, grouping commas, currency symbols,
malformed numbers and entries longer than 64 characters. Commas are not inserted
while typing. Negative decimals reach domain validation and receive clear field
errors. Values so tiny that their calculated EMI underflows to zero are rejected
with a safe “too small” error. Error objects never embed supplied input values.

## Locked financial model

Monthly rate:

```text
r = a / 12 / 100
P2 = P - A
```

For positive interest, the standard reducing-balance EMI is:

```text
EMI(P, r, n) = P*r*(1+r)^n / ((1+r)^n - 1)
            = P / factor
factor = (1 - (1+r)^(-n)) / r
```

When `r*n < 0.001`, the equivalent discounted geometric sum avoids subtraction
of nearly equal floating point numbers:

```text
q = 1 / (1+r)
factor = 0
repeat n times: factor = (factor + 1) * q
```

At exactly zero interest, `factor = n` and `EMI = P/n`. This also gives a
continuous, numerically stable result for tiny positive rates.

The current EMI is derived from the three original loan inputs. There is no
fifth input for a lender's current EMI; the screen states this explicitly.

### Reduce EMI, keep tenure same

```text
currentEmi = P / factor
revisedEmi = P2 / factor
monthlyReduction = currentEmi - revisedEmi
```

The card shows revised EMI, original calculated EMI, monthly reduction and
original remaining tenure. On full repayment it instead shows zero remaining
tenure, because no instalments remain.

### Reduce tenure, keep EMI same

Keep the original unrounded `currentEmi`. Start the balance at P2 and simulate
whole monthly instalments:

```text
interest = balance * r
amountDue = balance + interest
payment = min(currentEmi, amountDue)
balance = amountDue - payment
```

Stop once the balance is zero within a dust tolerance of `currentEmi * 1e-13`.
The returned tenure is an integer payment count, never a logarithmic fractional
month. Return the actual final simulated payment and `n - revisedMonths`.
Display the final payment as a secondary value when it differs from normal EMI
by at least ₹0.01.

The loop performs at most n iterations (at most 600). Since the original EMI
amortizes P in n months, a balance no larger than P cannot require more than n
payments. Any accumulated floating point residue at that upper bound is
absorbed; it never creates a fictitious extra month. No balance is rounded to
rupees, paise or display precision during the loop.

At zero part payment, return the exact original baseline directly: same EMI,
same n, zero reductions and the original EMI as final payment. At full
prepayment, return zero remaining principal, revised EMI, revised months and
final payment without running the loop. At zero interest, partial prepayment
uses the same simulation and can have a smaller final instalment.

## Precision, display and limitations

All domain amounts and rates use Dart double precision. Only the presentation
formats money, using the existing `intl` dependency:
`NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)`.
For example, ₹12,34,567.89. No new dependencies or lockfile changes are required.
Tabular figures support visual comparison; displayed amounts are never fed back
into calculations. Separately rounded displayed values may differ by one paisa
from arithmetic performed on those displayed values.

This is an estimate of a constant-rate reducing-balance loan with monthly
interest and immediate principal reduction. It excludes dates, daily interest,
rate resets, fees, penalties, arrears and lender-specific rounding or rules.
Extreme combinations of a high rate, long tenure and very small part payment
amplify floating point error in the simulated final payment; results are not a
paise-exact lender schedule. The documented limits and contractual payment-count
bound protect execution and avoid spurious additional instalments.

## Navigation, UI and accessibility

Explorer's existing Calculators card opens `CalculatorsHomeScreen`, then the
catalog entry opens `LoanPartPaymentScreen` using ordinary Material navigation.
Back returns through this stack. All other Explorer module destinations, MFD
application eligibility, linking, sign out and auth routing remain unchanged.
The same hub can later be used by Investor or Advisor navigation without
duplicating financial logic; their dashboards are unchanged in V1.

The screen uses the existing MoneyBowl Material theme. A centered scrollable
layout supports light/dark mode and 320px through desktop widths. Fields and
scenario cards share a two-column layout only when available width is at least
`720 * textScale`; otherwise they stack and use natural heights. Labels wrap
above inputs instead of being squeezed into floating labels. Units, semantic
field labels, ordinary tab order, numeric keyboard hints and 48px action targets
support accessible entry. Validation is expressed in text, not only color.

Calculate explicitly validates and produces results. On success, the view
scrolls to the result heading; on failure, focus goes to the first invalid field.
Editing any field removes the old estimate immediately. Failed recalculation
preserves all entered text and cannot leave stale results. Reset clears all
fields, errors and results. Navigating away disposes the screen-owned state.

The result hierarchy is current EMI/remaining principal, Reduce EMI, Reduce
tenure, then a readable estimate note explaining lender differences and that
this is not lender advice or a binding repayment schedule.

## Privacy

Financial values exist only in screen text controllers and its calculation
controller/result objects. There is no repository/service dependency, Supabase
initialization, RPC, HTTP call, browser storage, database write, URL value,
analytics, logging or error reporting path in this feature. Controllers and
focus nodes are disposed when the route is removed. No persistence or restoration
identifier is configured. Ordinary OS keyboard/clipboard behavior is unchanged.

An import-boundary test restricts the feature to its own files, Dart math,
Flutter presentation and `intl`, checks that models/domain stay pure Dart, and
rejects logging calls. A standalone widget test calculates successfully with
network construction blocked, no auth/service provider or Supabase initialization,
and no debug output.

## Test coverage and local validation

Before editing existing source, the authentication directory (Explorer entry,
auth session, email signup, onboarding services and route guards) plus MFD
application tests passed: **72 tests**. Flutter's first sandboxed attempt could
not bind its loopback test socket; the authorized local rerun passed. This was a
runner permission issue, not a baseline product failure.

New tests cover:

- Locked ₹10,00,000 / 120 months / 8.5% / ₹1,00,000 example: EMI ₹12,398.57,
  revised EMI ₹11,158.71, reduction ₹1,239.86, 103 payments, 17 months saved,
  final payment approximately ₹3,430.50.
- ₹1,00,000 / 12 months / 0% / ₹10,000: EMI approximately ₹8,333.33,
  revised EMI ₹7,500, 11 payments, final payment approximately ₹6,666.67.
- Zero/full prepayment, one month, decimal amounts/rates, exact payoff dust,
  tiny rates, negative/nonfinite/over-limit inputs and EMI underflow.
- 800 deterministic combinations across amounts, rates, tenures and payment
  fractions: finite/nonnegative values, principal/EMI/tenure bounds, termination,
  monotonic reductions, zero-payment identity and full-payoff identity.
- Parsing, paste, validation, reset and stale-result invalidation; hub/Explorer
  navigation and unchanged modules/sign out; field units, result formatting,
  keyboard focus, semantic labels and touch targets.
- Hub, form, result and error layouts at 320/390/768/1440px with normal/2x text,
  in both actual MoneyBowl themes. Tests require no live financial services.

Validation commands (run from the candidate worktree):

```sh
dart format lib/features/calculators lib/features/authentication/presentation/onboarding_screens.dart test/calculators test/authentication/explorer_entry_test.dart
flutter analyze --no-pub lib/features/calculators lib/features/authentication/presentation/onboarding_screens.dart test/calculators test/authentication/explorer_entry_test.dart
flutter test --no-pub test/calculators test/authentication test/mfd_application_test.dart
flutter test --no-pub
flutter build web --release --no-pub
python3 .github/scripts/validate_docs.py
python3 .github/scripts/validate_migration_history.py
python3 .github/scripts/validate_commits.py 'feat(calculators): add loan part payment calculator'
```

Final local validation (Flutter 3.44.6, Dart 3.12.2):

| Check | Outcome |
| --- | --- |
| Existing baseline before source changes | PASS: 72 authentication/Explorer/MFD tests |
| New pure-domain tests | PASS: 26 tests, including the 800-scenario invariant grid |
| New controller tests | PASS: 21 tests |
| New calculator widgets/navigation | PASS: 24 tests, including 16 width/theme/text-scale combinations |
| Feature privacy boundary | PASS: 1 test; blocked-network/no-service calculation also covered by widget tests |
| Explorer navigation regression file | PASS: 8 tests (7 added, original linking test retained) |
| Combined calculator/authentication/MFD regressions | PASS: 151 tests, including 25 MFD tests |
| Full Flutter suite | PASS: 546 tests |
| Formatting | PASS: all 12 changed Dart files, zero remaining changes |
| Scoped Flutter analyzer | PASS: zero issues |
| Local web release build | PASS: JavaScript output in `build/web`, 93.0 seconds |
| Documentation validator | PASS: 42 Markdown files checked |
| Migration-history validator | PASS: 27 frozen files through `20260801000000`; no migration or manifest diff |
| Commit message / validator regression tests | PASS: Conventional Commit format and 5 validator tests |
| Whitespace / scope review | PASS: `git diff --check`; no backend or dependency changes |

Build warnings are pre-existing: `dart:js` prevents the Wasm dry run in
`admin_dashboard.dart` and `excel_updater.dart`, and the Cupertino font family
is not bundled. Both warnings were already recorded in the
[baseline MFA architecture](PLATFORM_MFA_STEP_UP_V1.md) and
[Platform Admin validation](PLATFORM_ADMIN_AUTHORITY_V1.md). The requested
JavaScript release build succeeds; this candidate does not claim Wasm support.

Local runner logs are retained outside the source tree at
`/tmp/moneybowl-calculators-v1-evidence/`. Initial widget-harness scrolling and
teardown failures were corrected before the passing runs; no checks were
weakened. All requested automated checks ran. Hosted tests, provider calls,
manual device/screen-reader testing and deployment were not performed; device
accessibility behavior is covered here by deterministic widget tests, not a
claim of manual assistive-technology certification.

## Exclusions and release boundary

No additional calculators, amortization export, PDF, email/share, saved
scenarios/history, real account/lender integration, floating-rate predictions,
date inputs, fees or foreclosure charges. No migration, hosted test, deployment,
DEV/Production mutation, push, PR or merge. This is one reviewable local candidate.

## V1.1 interest savings and month-wise schedules

The [V1.1 implementation plan](CALCULATORS_LOAN_PART_PAYMENT_V1_1_IMPLEMENTATION_PLAN.md)
was saved before source edits. V1's four financial inputs, limits, EMI formula,
Indian currency formatting, catalog/hub, Explorer routes and client-only privacy
contract remain intact. No dependencies or backend files change.

### Typed schedules and interest comparison

`AmortizationRow` is an immutable pure-Dart record of `monthNumber`,
`openingOutstanding`, `payment`, `interestComponent`, `principalComponent` and
`closingOutstanding`. It contains relative months only, with no date or clock.
Each scenario exposes an immutable `schedule`, `totalInterest` and `interestSaved`
in addition to its V1 summary fields. The aggregate result additionally exposes
`baselineSchedule` and `baselineRemainingInterest`. UI code formats these values;
it does not calculate financial totals or reproduce amortization logic.

One private `_amortize` engine generates all three schedules:

| Schedule | Opening balance | Regular payment | Duration |
| --- | --- | --- | --- |
| Baseline | Original principal P | Original calculated EMI | Original n months |
| Reduced EMI | P2 = P - A | Revised calculated EMI | Original n months unless fully repaid |
| Reduced tenure | P2 = P - A | Original calculated EMI | Until payoff, no more than n months |

Baseline remaining interest is the sum of the baseline rows' interest components.
Each scenario's payable interest is the sum of its own rows' interest components.
**Interest saved = baseline remaining interest - scenario total interest.**
Neither principal repayment nor the immediate part payment is interest. The
part payment is not an extra EMI row; both future schedules begin at P2.

The current EMI card identifies baseline interest as the comparison. Both
scenario cards preserve their original outputs and additionally show payable
interest and emphasized savings. Tenure and final payment derive from the same
rows used in the schedule, not a second simulation or fractional-month formula.

### Single engine, numerical stability and reconciliation

The financial recurrence is unchanged:

```text
interest = opening * r
amountDue = opening + interest
payment = min(scheduledEMI, amountDue)
principalComponent = payment - interest
closing = opening - principalComponent
```

To avoid cancellation in a very small early principal component, the engine
evaluates the equivalent principal progression in full double precision:

```text
S = 0
repeat n times: S = S*(1+r) + 1
firstPrincipalComponent = referencePrincipal / S + partPayment*r
nextPrincipalComponent = previousPrincipalComponent * (1+r)
```

For the baseline, reference principal is P and part payment is zero. For Reduced
EMI, reference principal is P2 and part payment is zero. For Reduced tenure,
reference principal is P and part payment is A. This equivalence follows by
subtracting consecutive monthly balance equations; it is the same loan model,
not a different summary formula. The [plan's deviation record](CALCULATORS_LOAN_PART_PAYMENT_V1_1_IMPLEMENTATION_PLAN.md#implementation-deviations)
records the conditioning evidence and decision.

Payment and interest still use the monthly formulas above. Principal repaid is
bounded by opening balance and the final balance becomes zero only within the
documented tolerance. Every emitted row is checked for finite, nonnegative
values and both accounting identities:

```text
payment = interestComponent + principalComponent
closing = opening + interestComponent - payment
```

The row/payoff tolerance is `max(referencePrincipal, scheduledEMI) * 1e-12`.
At the maximum principal this is approximately one paisa, and it scales down
with loan size. It is a roundoff check, not monthly monetary rounding. No EMI,
monthly interest or balance is rounded for calculation. Last payments use the
smaller amount due. At the contractual final month, a difference from scheduled
EMI within this tolerance is treated as dust, retaining the scheduled EMI and
zero closing balance; this preserves exact zero-part-payment baseline behavior.

No schedule can exceed n rows (600 maximum). Unlike V1's count-only fallback,
a material balance remaining at that bound raises `LoanCalculationException`.
A row failing either identity also raises that value-free exception. The
controller clears results/timestamp and displays a safe reconciliation error
without printing, transmitting or persisting values.

Savings tolerance is `max(baselineInterest, scenarioInterest) * 1e-12`. A negative
difference within this tolerance becomes zero; a materially negative difference
or nonfinite savings raises the same invariant exception. Scenario summaries
are sums of the exact schedule row objects, without separate rounding or formulas.

Special cases:

- Zero part payment reuses the baseline rows in both scenarios. Both savings
  values are exactly zero and schedule lengths reproduce original tenure.
- Full part payment bypasses future-schedule loops: both lists are empty, both
  future interest values are zero and each saving equals baseline interest.
  The baseline is still generated to measure the interest avoided.
- At 0%, interest and savings are zero throughout. Principal repaid equals payment
  exactly, and the last reduced-tenure instalment can be smaller than regular EMI.

### Calendar labels and ephemeral calculation time

`LoanPartPaymentController` accepts an optional `DateTime Function()` clock,
defaulting to `DateTime.now`. It reads this once per Calculate invocation and
retains `calculatedAt` only for a successful result. Edit, reset, validation failure
or invariant failure clears the timestamp together with the result. The screen
also exposes an optional clock for deterministic widget tests. The pure domain
has no clock access.

Row k is labelled using the year/month of the captured calculation timestamp
plus k calendar months. Month 1 is the **next** calendar month; there is no
duration-based day arithmetic or displayed day of month. For October 5, 2026,
rows 1, 2 and 13 display `Month 1 · Nov 2026`, `Month 2 · Dec 2026` and
`Month 13 · Nov 2027`. Labels stay fixed through rebuilds, theme/layout changes,
scenario switches and page changes. Recalculation captures a new timestamp.
English month names use bundled `en_US` date symbols; rupee amounts retain
`en_IN` formatting to two decimals. No asynchronous locale setup is required.

The UI explains: the part payment is applied now, before the next EMI; calendar
months are illustrative and the lender's actual EMI date may differ. The estimate
note now covers interest savings, schedules, daily interest, rate resets, fees,
penalties and rounding, and retains the non-advice/nonbinding disclaimer.

### Bounded, responsive schedule presentation

`presentation/loan_amortization_schedule.dart` presents one selected scenario.
Reduced EMI is selected initially, matching the summary order. Accessible Material
choice chips switch to Reduced tenure. Only 12 rows are mounted at a time;
Previous/Next controls show `Months X–Y of Z` and disable at page boundaries.
At most three bounded domain lists are calculated, never two 600-row widget trees.

Wide layouts (at least `900 * textScale` logical pixels) use a compact six-column
table. A local horizontal viewport protects unusually wide formatted values;
the calculator page itself never scrolls horizontally. Narrow layouts and large
text use monthly cards with explicit labels for all fields. Selectors and paging
buttons have at least 48px targets, semantic labels and no hover dependency.
Current row-range announcements use a semantic live region.

Scenario changes and replacement results reset to page one. Editing any input,
reset or failed calculation removes the entire previous schedule. Component
identity is tied to the result and replacement is also handled explicitly inside
the schedule widget. Full prepayment displays:

> No future EMI schedule — the entered part payment fully repays the outstanding principal.

### Numeric acceptance and privacy

For P = ₹10,00,000, n = 120, a = 8.5%, A = ₹1,00,000:

| Metric | Value displayed |
| --- | --- |
| Current EMI | ₹12,398.57 |
| Reduced EMI / monthly reduction | ₹11,158.71 / ₹1,239.86 |
| Reduced tenure / reduction | 103 / 17 months |
| Final reduced-tenure payment | ₹3,430.50 |
| Baseline remaining interest | ₹4,87,828.27 |
| Reduced EMI interest / savings | ₹4,39,045.44 / ₹48,782.83 |
| Reduced tenure interest / savings | ₹3,68,084.53 / ₹1,19,743.74 |

| Row | Opening | Payment | Interest | Principal | Closing |
| --- | --- | --- | --- | --- | --- |
| Reduced EMI 1 | ₹9,00,000.00 | ₹11,158.71 | ₹6,375.00 | ₹4,783.71 | ₹8,95,216.29 |
| Reduced tenure 1 | ₹9,00,000.00 | ₹12,398.57 | ₹6,375.00 | ₹6,023.57 | ₹8,93,976.43 |
| Reduced tenure 103 | ₹3,406.37 | ₹3,430.50 | ₹24.13 | ₹3,406.37 | ₹0.00 |

No month 104 exists in the reduced-tenure schedule. Currency is display-rounded
only; arithmetic on separately rounded visible values may differ by one paisa.

Rows, totals, timestamp, selected scenario and page remain local ephemeral state.
There is no database, RPC, Supabase, network, browser storage, logging, URL or
analytics path. The privacy import test still restricts dependencies and now
explicitly checks clock independence. The blocked-network widget test covers
schedule selection and paging as well as calculation. No new dependency is used.

### V1.1 validation and manual review

Before source changes, the existing calculator, Explorer, route-guard and MFD
tests passed: **122 tests**. The original 800 invariant combinations remain and
now validate every row, continuity, principal repayment, final payoff, payment
cap, schedule length, sums, interest savings and special cases. Locked first/last
row and interest values have deterministic numeric and UI assertions. A separate
maximum-principal/rate 600-month case checks numerical reconciliation.

Schedule tests cover 1/11/12/13/25/120/600 months, every forward page through the
600-month schedule, previous/last partial pages, 120-vs-103 scenario lengths,
replacement/reset and frozen calendar/year rollover. Existing 320/390/768/1440px
normal/2x light/dark tests now exercise schedule rows, selector, both paging
directions and target sizes. Standalone controller tests cover single clock reads,
timestamp invalidation and safe invariant failures.

Manual source review completed before the local commit:

| Requested check | Evidence / result |
| --- | --- |
| 1. One engine for summaries and tables | All three lists use `_amortize`; totals fold those rows and tenure/final payment read the same list |
| 2. Savings exclude principal | `_savings` subtracts only summed `interestComponent` values |
| 3. Part payment is not an EMI | Initial balance is reduced before month 1; no payment row for A |
| 4. Smaller final payment | `min(emi, amountDue)`; locked month 103 payment verified |
| 5. No extra dust month | Scale-aware payoff tolerance and strict n-row bound; no month 104 in acceptance case |
| 6. Correct starting balance | Both first openings equal P2; grid and first-row assertions |
| 7. No invented lender date | Relative month plus `MMM yyyy` only; captured clock and calendar-rollover tests |
| 8. Full prepayment | Empty post-payment lists and explicit no-future-schedule message |
| 9. Zero part payment | Baseline rows reused; exact zero savings and original n |
| 10. Zero rate | Every row has zero interest and principal equals payment |
| 11. 600-month bound | Fixed maximum, boundary test and all 50 schedule pages exercised |
| 12. No stale page | Scenario changes/replacement reset page; result-keyed widget lifecycle |
| 13. Input edits clear schedules | Controller clears result/timestamp; old schedule is removed immediately |
| 14. No network/persistence/logging | Restricted import test and blocked-network calculation/selector/paging test |
| 15. No database code | Scope review shows no Supabase, migration, dependency or backend changes |

Final V1.1 local validation (Flutter 3.44.6 / Dart 3.12.2):

| Check | Result |
| --- | --- |
| Existing baseline before source edits | PASS: 122 tests |
| Domain tests | PASS: 30 tests, retaining and extending all 800 invariant scenarios |
| Controller tests | PASS: 23 tests, including injected clock and safe invariant error |
| Calculator widget/navigation/responsive tests | PASS: 24 tests |
| Schedule pagination/calendar tests | PASS: 12 tests |
| Privacy boundary | PASS: 1 test; blocked-network widget test also covers paging |
| All calculator tests | PASS: 90 tests |
| Explorer / route guard / MFD regressions | PASS: 50 tests (8 / 17 / 25) |
| Full Flutter suite | PASS: 564 tests |
| Changed-file formatting | PASS: 10 Dart files, no remaining formatting changes |
| Scoped analyzer | PASS: no issues in calculator source or tests |
| Local release web build | PASS: JavaScript `build/web`, 93.7 seconds |
| Documentation validation | PASS: 43 Markdown files |
| Migration-history validation | PASS: 27 frozen files through `20260801000000`; no migration changes |
| Commit validation | PASS: Conventional Commit message and 5 validator regressions |
| Whitespace/scope review | PASS: no changes to hub/catalog, onboarding, old plan, dependencies or backend |

The existing Wasm dry-run warnings for `dart:js` in admin/excel code and the
Cupertino font-reference warning remain unchanged. They do not prevent the
JavaScript web release build. The earlier standalone locale failure was corrected
using bundled date symbols; all final checks pass without locale setup or network.
No tests were deleted or disabled. Logs are outside the repository at
`/tmp/moneybowl-calculators-v1-1-evidence/`.

All requested automated checks ran. Hosted/provider tests and deployment were
excluded by scope; manual device/browser/screen-reader testing was not performed.
The responsive/accessibility evidence is deterministic widget coverage. Remaining
limitations are the existing input bounds and monthly constant-rate estimate:
calendar months are illustrative, money uses double precision, and lender dates,
daily interest, rate resets, charges and rounding may differ. No export, exact
due-date input, persistence, tax calculation or backend functionality is added.
