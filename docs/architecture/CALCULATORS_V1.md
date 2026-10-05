# Calculators V1 — Loan Part Payment

Local candidate based on `d31c40058f2e542ff302234a8b92404437753647`.
The [original implementation plan](CALCULATORS_V1_IMPLEMENTATION_PLAN.md) was
saved before implementation. No hosted commissioning is part of this feature.

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
