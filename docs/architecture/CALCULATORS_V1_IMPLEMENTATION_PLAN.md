# Calculators V1 implementation plan

Saved before application implementation. Local candidate only, based exactly on
`d31c40058f2e542ff302234a8b92404437753647` in
`feature/calculators-loan-part-payment-v1`.

## Existing navigation and scope

`ExplorerHomeScreen` in `onboarding_screens.dart` maps six module records to
generic `ExplorerModuleScreen` routes. Change only the Calculators destination
to a reusable hub. Preserve linking, MFD application, sign out, role gates and
all five other module destinations. Investor/Advisor navigation is excluded.

## Architecture and intended files

- `lib/features/calculators/models/loan_part_payment.dart`: immutable typed
  input, result and scenario values; no Flutter or service dependencies.
- `lib/features/calculators/domain/loan_part_payment_calculator.dart`: validation
  and deterministic amortization, directly unit testable.
- `lib/features/calculators/presentation/calculator_catalog.dart`: small typed
  definition with stable ID, title, description, icon and screen builder.
- `lib/features/calculators/presentation/calculators_home_screen.dart`: catalog
  driven hub with one functional entry; future calculators register here through
  the catalog without changing hub logic.
- `lib/features/calculators/presentation/loan_part_payment_controller.dart`:
  local form parsing, validation, typed result and explicit calculate/reset state.
- `lib/features/calculators/presentation/loan_part_payment_screen.dart`: form and
  result cards using existing MoneyBowl Material theme and `intl`.
- `test/calculators/`: domain, controller, widget, privacy and navigation tests.
- Existing Explorer test file: navigation regressions.
- `docs/architecture/CALCULATORS_V1.md` and `docs/CHANGELOG.md`: contract,
  extension instructions and validation evidence.

No expression engine, dynamic plugins or database-driven catalog.

## Calculation contract and precision

Inputs are current principal P, integer remaining months n, annual percentage a
and immediate principal part payment A. Monthly rate r = a / 12 / 100.
For r > 0, EMI = P*r/(1-(1+r)^(-n)); a stable equivalent geometric discount
sum is permitted to avoid cancellation at tiny positive rates. For r = 0,
EMI = P/n. Remaining principal P2 = P-A. Same-tenure EMI uses P2, r and n;
monthly reduction is original EMI minus revised EMI.

Same-EMI tenure uses the original unrounded EMI. Each month calculate interest
= balance*r, due = balance+interest, payment = min(EMI,due), and balance =
due-payment. Return a whole payment count and final payment. Bound simulation
by the original tenure; handle floating point residue with a documented,
scale-aware numerical tolerance, never whole-rupee balance rounding. Zero
payment reproduces the baseline. Full prepayment returns zero EMI, zero months
and zero final payment immediately without simulation. At zero interest the
same monthly simulation supports a smaller final instalment.

Use double precision internally and round only display values to two decimals
with `NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)`.
Document and explicitly validate technical input limits protecting precision
and bounded runtime; do not clamp user entries. Domain errors must contain no
entered values.

## UI, validation and accessibility

Scrollable, centered content: title and explanation, four labelled inputs,
Calculate/Reset, current calculated EMI and remaining principal, then Reduce
EMI / Keep tenure same and Reduce tenure / Keep EMI same cards. Clearly explain
EMI derivation and lender estimate assumptions. Show a full repayment message.
Use responsive single/two column layouts with natural height and a text-scale
aware breakpoint, no fixed-height financial cards. Support 320px, phones,
tablet, desktop, light/dark and large text. Preserve ordinary keyboard focus,
paste and numeric keyboard hints, with visible units and accessible labels.
Avoid live comma insertion. Buttons have at least 48px targets.

Required inputs reject empty/malformed/nonfinite numbers, principal <= 0,
fractional or <1 months, negative rate/payment and payment > principal. Allow
decimal principal/rate/payment, zero rate and zero payment. Preserve fields
on failure. Clear old results on edits and failed calculation so they cannot
be mistaken for estimates for new inputs. Reset explicitly clears fields and
results. All state lives only in the mounted screen/controller.

## Privacy and exclusions

No Supabase, repositories, external APIs, browser storage, URL parameters,
input logging, analytics or error telemetry. No migration or backend change.
Exclude other calculators, saved scenarios/history, date/daily-interest models,
fees/penalties, lender integration, share/export, deployment, push, PR and merge.

## Test and delivery matrix

Before editing existing source, run existing authentication tests (including
Explorer entry, onboarding services, route guard, session and email signup)
and MFD application tests. Capture the baseline outside tracked source.

New deterministic tests: supplied 8.5% and 0% numeric examples; zero/full
payment; one month; decimal inputs; malformed/nonfinite/negative/over-limit
inputs; payment above principal; large values; tiny rates. Grid/property-style
tests check finite nonnegative outputs, bounds, termination, baseline identity,
full payoff, and monotonic EMI/tenure as part payment increases.

Widget/navigation tests: Explorer catalog route and unchanged destinations,
hub entry/back, field labels/units, calculation scenarios and currency grouping,
zero interest/payment and full payoff, reset/recalculate/failure, paste/focus,
320px and large text layouts, tablet/desktop and light/dark themes. Run standalone
without Supabase initialization; inspect feature imports for privacy boundaries.

After implementation: format changed Dart files; analyze changed/relevant files;
run new tests, existing auth/Explorer/MFD regressions, full Flutter suite, local
release web build, docs validator and migration-history validator. Record any
pre-existing warning separately. Preserve this plan and append Implementation
Deviations if necessary. Create exactly one local Conventional Commit after all
required checks pass. Verify final tree, worktree status and unchanged canonical
checkout. Do not push, create a PR, merge or deploy.
