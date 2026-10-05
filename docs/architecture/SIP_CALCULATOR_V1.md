# SIP Calculator V1

Local candidate based on verified fresh `origin/develop`
`fb84b288e7b72666f3a5ea16f47f3119023852e0`. Canonical `develop` was clean at
that SHA before creating `feature/calculators-sip-v1` in
`/home/ubuntu/moneybowl-worktrees/calculators-sip-v1`.
The [implementation plan](SIP_CALCULATOR_V1_IMPLEMENTATION_PLAN.md) was saved
before source edits. Delivery is one local commit, without push, PR, merge or
deployment.

## Catalog and independent ownership

The existing Explorer → Calculators hub now lists:

1. Loan Part Payment Calculator (`loan-part-payment`)
2. EMI Calculator (`emi`)
3. SIP Calculator (`sip`, `Icons.trending_up_outlined`)

SIP has its own typed input/result, pure engine, controller and screen. Neither
loan calculator's financial source, model, controller, screen nor shared schedule
viewer changes. The existing EMI widget test updates only its exact catalog
membership/count assertion to include SIP; every financial assertion remains.
No hub/navigation replacement, generic engine or shared-domain extraction occurs.

| File under `lib/features/calculators/` | Responsibility |
| --- | --- |
| `models/sip.dart` | `SipInput`, `SipTenureUnit`, immutable `SipMonth`/`SipResult`, civil calendar helpers |
| `domain/sip_calculator.dart` | Validation and one authoritative monthly contribution/return simulation |
| `presentation/sip_controller.dart` | Plain input/date parsing, safe errors, Calculate/Reset, invalidation and injected clock |
| `presentation/sip_screen.dart` | Themed input form, Material date picker, summaries and explanatory copy |
| `presentation/calculator_catalog.dart` | Appends the working SIP definition without changing either existing entry |

The existing [catalog extension steps](CALCULATORS_V1.md#purpose-and-extension-point)
apply to future calculators. SIP cash-flow records remain domain audit evidence;
this V1 does not introduce a displayed investment schedule or export.

## Input and validation contract

| Input | Accepted values |
| --- | --- |
| Initial Investment Amount | Finite decimal rupees, 0–10,000,000,000 |
| Monthly SIP Amount | Finite decimal rupees, >0 and <=10,000,000,000 |
| SIP Tenure, Months | Whole integer 1–600 |
| SIP Tenure, Years | Whole integer 1–50; normalized months = years × 12 |
| Expected ROI (% p.a.) | Finite annual percentage, 0–30 inclusive |
| Lump Sum Amount | Finite decimal rupees, 0–10,000,000,000 |
| Lump Sum Investment Date | A real date within the plan; required only for a positive lump sum |

Amount limits reuse the loan calculators' ₹1,000-crore technical bound. ROI
bounds define a nonnegative constant-return estimate and bounded floating-point
execution, not a forecast, guarantee or description of available investments.
Negative ROI, step-up SIPs and variable returns are outside this V1 model.

The five numeric fields follow the existing plain-number convention: surrounding
whitespace and decimal amount/ROI values are accepted; tenure is digits only.
Reject exponent notation, grouping commas, currency symbols, NaN/Infinity,
fractional tenure, malformed text and entries longer than 64 characters. Values
are never silently clamped. Pure-domain validation protects direct callers too.

Date text is strict `YYYY-MM-DD` with a real civil year 0001–9999, month and day.
Validate components after constructing a DateTime so overflow such as 31 April
or a non-leap 29 February is rejected rather than normalized. Native Material
date selection is also available. With lump sum zero, date text is ignored and
the controller passes no date; changing the amount to positive requires a valid
date again. The UI states this rule. Invalid entry text is retained.

Initial investment and lump sum default to explicit zero. Reset restores those
zeros, empties the other fields, restores Months and clears errors/results.
Switching units clears tenure and its error, result and timestamp; it does not
reinterpret existing digits. Clicking the already selected unit changes nothing.
Any field edit, including a date-picker selection, clears the previous result.

## Calendar convention

Each explicit Calculate or keyboard Done action captures the injected clock
once. The screen retains that timestamp only with a successful result. The pure
domain receives the captured start date; it never calls a clock or service.
Rebuilding preserves the captured date. A later calculation captures a new date
and revalidates any entered lump sum, including a date that has since become past.
Opening a date picker does not start the plan or capture a calculation timestamp.

Calendar interpretation is intentionally explicit:

- Month 1 is the calculation/start date's calendar month.
- An n-month tenure includes n calendar buckets, ending in month n-1 after the
  start month. Its final allowed date is the last day of that final month.
- A positive lump sum must be dated on/after the start date and on/before that
  final date, inclusive. An earlier day in the start month is still invalid.
- Map the selected date to zero-based period
  `12*(date.year-start.year) + date.month-start.month`.
- The initial partial calendar month receives one full monthly return. Every
  valid date within a given month has the same effect: add the lump sum before
  that month's return. No daily accrual or proration occurs.

For a start of **05 Oct 2026**, 12 months end **30 Sep 2027**, and 120 months end
**30 Sep 2036**. A lump sum on 30 Sep 2036 earns one monthly return; 01 Oct 2036
is rejected. October 2031 is period 61 in the 120-month example and earns 60
monthly returns, including its contribution month. Calendar helpers preserve
civil year/month/day components and use UTC DateTime construction for arithmetic,
without converting civil dates through time-zone offsets or elapsed day counts.
Leap days, varying month lengths and year boundaries have deterministic tests.

## Single monthly calculation

Let r = annualROI / 12 / 100. Initialize balance and invested amount to the
initial investment. For each period, exactly once:

```text
opening = previous closing (initial investment for period 1)
lump = lump sum if this is its mapped month, otherwise zero
contribution = monthly SIP + lump
invested += contribution
funded = opening + contribution
monthlyReturn = funded * r
closing = funded + monthlyReturn
```

The initial investment is never added twice. All n SIP payments occur at the
beginning of their respective periods; the last SIP also earns one return. A
lump sum occurs exactly once and only earns from its mapped month onward.

Each immutable `SipMonth` records month number, opening value, SIP contribution,
lump contribution, monthly return and closing value. `SipResult` snapshots these
rows in an unmodifiable list. **Total Fund Value** is the final closing value;
**Amount Invested** is the contribution accumulator, including initial capital;
**Estimated Returns** is fund value minus invested amount. Product summaries use
no separate annuity approximation or independent formula.

All internal arithmetic uses unrounded doubles. At 0% the fund and investment
accumulators use identical additions, so fund value equals invested amount
exactly and returns equal zero. Runtime checks require finite/nonnegative
balances, contributions and growth. Tests check every row's accounting,
continuity, single lump sum, total investment and returns with a scale-relative
1e-12 tolerance. Money is formatted only at the UI boundary using existing
`intl` en_IN rupees and two decimal places. Extreme supported combinations are
not paise-exact, and separately rounded figures may not reconcile to the paisa.

## Independently locked example

| Input | Value |
| --- | --- |
| Captured start | 05 Oct 2026 |
| Initial investment | ₹1,00,000 |
| Monthly SIP | ₹10,000 |
| Tenure | 120 months / 10 years |
| Annual expected ROI | 12% (monthly 1%) |
| Lump sum | ₹2,00,000 on 20 Oct 2031 |
| Plan end | 30 Sep 2036 |

| Output | Unrounded approximate value | Display |
| --- | --- | --- |
| Total Fund Value | 3016768.792689586 | ₹30,16,768.79 |
| Amount Invested | 1500000 | ₹15,00,000.00 |
| Estimated Returns | 1516768.792689586 | ₹15,16,768.79 |

The test derives its oracle independently using BigInt rational arithmetic,
compounding each dated contribution directly with q=101/100:

```text
FV = 100000*q^120 + sum(10000*q^k, k=1..120) + 200000*q^60
```

It shares neither the engine's recurrence nor a product helper. Exact rational
rounding produces 301,676,879 paise, which is also asserted as a fixed value.
The first period closes at ₹1,11,100. The lump sum is absent through period 60
and added once in period 61. Equivalent years/months and same-month dates produce
identical financial results. A zero-initial/zero-lump 12-month SIP of ₹10,000 at
0% produces fund/invested amount ₹1,20,000 and returns ₹0.

## UI, accessibility and privacy

The independent SIP screen displays Investment Details and prominent Total Fund
Value, Amount Invested and Estimated Returns, with original/normalized tenure and
the captured plan range. The form explains full monthly returns, contribution
ordering and date limits; the result note excludes taxes, exit load and fees and
states that actual returns vary, are not guaranteed and are not investment advice.

Reuse MoneyBowl's Material theme, natural-height responsive fields/cards, tabular
monetary figures, accessible native choices and date picker. Controls have at
least 48px targets, visible labels, keyboard support and selected-unit semantics.
Tests cover 320/390/768/1440px × light/dark × normal/2x text, including the date
picker, results and validation states, with no Flutter overflow exceptions.

All financial inputs/results are ephemeral, disposed with the route. There is
no Supabase, service/repository dependency, financial API, HTTP call, database,
browser storage, restoration, logging, analytics or URL encoding. The static
privacy boundary now explicitly includes SIP, and a standalone widget test
calculates, opens the picker, switches units and resets with HTTP construction
blocked and debug output captured. No dependency changes were required.

## Local validation and exclusions

Toolchain: Flutter 3.44.6 / Dart 3.12.2, dependencies resolved offline. Evidence
logs live outside the repository at `/tmp/moneybowl-sip-v1-evidence/`.
Baseline before source changes: **200 tests passed** (192 calculators + 8 Explorer)
in 67 seconds. The initial SIP run found two test-harness assertions needing
correction: unchanged text is not an edit, and date helper text merges into
semantics. Tests now perform real edits and inspect the complete semantic label;
no product behavior or checks were weakened.

Commands, with the existing Flutter SDK on PATH:

```sh
flutter test --no-pub --reporter expanded test/calculators test/authentication/explorer_entry_test.dart
flutter analyze --no-pub lib/features/calculators test/calculators test/authentication/explorer_entry_test.dart
flutter test --no-pub --reporter expanded
flutter build web --release --no-pub
python3 .github/scripts/validate_docs.py
python3 .github/scripts/validate_migration_history.py
python3 -B -m unittest discover -s .github/scripts -p 'test_validate_commits.py'
python3 .github/scripts/validate_commits.py 'feat(calculators): add SIP calculator'
git diff --check
```

No saved scenarios, schedule UI/export, PDFs/CSV, daily returns, multiple lump
sums, negative ROI, variable returns, step-up SIP, tax/fee/exit-load estimation,
hosted testing or manual device/screen-reader certification. Existing financial
engines, auth, portfolio, MFD, NSE, CAMS, backend and dependency files are unchanged.

### Validation evidence

| Check | Result |
| --- | --- |
| Baseline before source edits | PASS: 200 tests (192 calculators + 8 Explorer), 67 seconds |
| SIP pure domain | PASS: 43 tests, including exact-rational locked example and 576 boundary combinations |
| SIP controller | PASS: 46 tests |
| SIP widgets | PASS: 27 tests, including all 16 width/theme/scale combinations and native date picker |
| Calculator privacy | PASS: static boundary and blocked-network/no-debug-output SIP widget |
| All calculator tests | PASS: 308 tests, retaining all 192 existing regressions |
| Explorer navigation | PASS: 8 tests; combined run 316 tests in 91 seconds |
| Existing source preservation | PASS: all 12 pre-existing source files other than the catalog are byte-for-byte unchanged |
| Full Flutter suite | PASS: 782 tests in 267 seconds |
| Formatting | PASS: 10 changed Dart files; zero remaining formatting changes |
| Scoped analyzer | PASS: zero issues |
| Local release web build | PASS: JavaScript output in `build/web`, 148.1 seconds |
| Documentation quality/link audit | PASS: 47 Markdown files |
| Migration history | PASS: 27 frozen files through 20260801000000; no migration or manifest changes |
| Commit validator | PASS: Conventional Commit message and 5 validator unit tests |
| Scope/whitespace audit | PASS: 9 added / 5 modified files, only calculators source/tests and requested docs |

The preserved regression tests retain Loan Part Payment's locked EMI, reduced EMI,
103-month tenure, interest savings, first/final rows, calendar labels and paging.
They also retain EMI's 120-month/10-year equivalence, locked totals, zero-interest
payoff, calendar and pagination coverage. No financial test expectations changed.

The release build reports the known pre-existing Wasm/font warnings: `dart:js`
in `admin_dashboard.dart` and `excel_updater.dart` prevents the Wasm dry run, and
the Cupertino font family is not bundled. The JavaScript release build succeeds.
These warnings were already documented in [EMI V1](EMI_CALCULATOR_V1.md#validation-evidence);
no Wasm support or unrelated fixes are claimed.

All required local automated checks ran and passed. Hosted tests, manual device/
screen-reader sessions, financial API calls and deployment were not performed.
The calculator performed no network calls; the required origin fetch was a Git
precheck, not a calculator runtime operation. No migrations, hosted DEV or
Production/main changes, persistence, push, PR or merge are part of this candidate.
