# SIP Calculator V1 implementation plan

Saved before source edits on 2026-10-05. Verified clean canonical `develop` and
fresh `origin/develop` both equal `fb84b288e7b72666f3a5ea16f47f3119023852e0`.
Branch: `feature/calculators-sip-v1`. Worktree:
`/home/ubuntu/moneybowl-worktrees/calculators-sip-v1`.
Delivery is exactly one local commit; no push, PR, merge or deployment.

## Architecture and scope

Explorer already opens the immutable calculator catalog. Append `sip` as the
third definition, following `loan-part-payment` and `emi`. Keep their definitions,
screens, controllers, financial engines, models and shared amortization viewer
unchanged. Update only the existing EMI test's exact catalog membership/count
assertion to include the third entry; preserve its financial assertions.

Create independent `SipInput`, `SipResult`, `SipMonth`, `SipTenureUnit`,
`SipCalculator`, `SipController` and `SipScreen`. Reuse existing Material theme,
Indian currency formatting and responsive form patterns without extracting or
changing existing calculator code. No dependency changes or generic engine.

## Inputs, limits and parsing

- Initial investment and single lump sum: finite decimal rupees, 0–1e10.
- Monthly SIP: finite decimal rupees, >0 and <=1e10.
- Expected annual ROI: finite percentage, 0–30 inclusive. This is a technical
  nonnegative-return model bound, not a promise or forecast of actual returns.
- Tenure: whole 1–600 months or 1–50 years, normalized as years × 12.
- Lump-sum date: strict real civil date `YYYY-MM-DD`, with a native Material
  date-picker alternative. Required only when lump sum >0; ignored when zero.

Follow the current 64-character plain-decimal parsing convention, allowing
surrounding whitespace but rejecting exponents, commas, symbols, NaN/Infinity,
fractions in tenure and invalid/overflowing calendar dates. Repeat numeric/date
validation in the pure domain. Do not clamp financial inputs or expose them in
error messages. Preserve text on failure. Optional amounts default to explicit
zero. Reset restores those zeros and clears all other fields, errors and results.

## Exact monthly and date convention

Capture the clock once on each Calculate. Pass that captured date explicitly
into the domain; the domain never reads the clock. Interpret civil year/month/day
components independently of time of day, time zone offsets or DST durations.

The calculation's calendar month is period 1. A tenure of n months spans that
month through the month n-1 calendar months later. The last allowed lump-sum date
is the last calendar day of period n, inclusive. The first allowed date is the
calculation/start date itself, inclusive. Example: 05 Oct 2026 + 12 periods spans
05 Oct 2026 through 30 Sep 2027. The partial starting month earns one full monthly
return, and all dates within a month share the same investment period. Disclose
this clearly; no daily prorating or anniversary-date interest calculation.

Map the lump sum by `12*(date.year-start.year) + date.month-start.month`, zero
based. Reject dates outside the start/end boundaries before running the engine.

Initialize balance and invested amount to the initial investment. For each of n
periods, in this exact order:

1. Record opening balance.
2. Add monthly SIP and, only in its mapped calendar month, the lump sum.
3. Add the same contribution to invested amount.
4. Compute monthly return as funded balance × (annualROI/12/100).
5. Add that return and carry closing balance forward.

One simulation produces immutable monthly cash-flow records and every summary.
Fund value = final closing; invested amount = accumulated contributions including
initial capital; returns = fund value - invested amount. Do not use a separate
summary formula in product code. At 0% both balances use identical additions,
so fund value equals invested amount exactly and returns are exactly zero.

Use unrounded double precision throughout and format only for display. Enforce
finite/nonnegative rows/totals and positive monthly SIP. Tests reconcile arithmetic
with a scale-relative tolerance of 1e-12 (not monthly rounding). At the extreme
supported amounts/rate/tenure, double precision is not paise-exact.

## UI, state, accessibility and privacy

Screen title: SIP Calculator. Investment Details contains initial investment,
monthly SIP, tenure, Months/Years choices, expected ROI, lump sum and its date.
Use labelled natural-height fields and 48px action/choice/date controls. Stack
on narrow layouts; use existing responsive pairs on wide layouts. Respect theme
and text scaling; tabular monetary figures and `intl` en_IN rupees.

Calculate is explicit, focuses validation errors or scrolls to results. Show
Total Fund Value, Amount Invested, Estimated Returns, normalized/original tenure
and captured plan date range. Explain beginning-of-period contributions, the
calendar-month lump-sum mapping, full monthly return/no daily prorating, no fees,
tax or exit load, and that expected returns are not guaranteed or advice.

Any edit clears the result/timestamp. Unit changes also clear tenure and its
validation without reinterpreting the value. New calculations capture a new
start date and revalidate the chosen lump-sum date. Date-picker convenience does
not set the plan's calculation date. State is disposed with the route.

No displayed cash-flow schedule is requested; the internal immutable rows allow
auditing/test assertions. No Supabase, network, repositories, logging, analytics,
storage, restoration or URL encoding of values. Extend static privacy checks and
run SIP widgets with HTTP construction blocked and debug output captured.

## Intended files and tests

Add `models/sip.dart`, `domain/sip_calculator.dart`,
`presentation/sip_controller.dart`, `presentation/sip_screen.dart`, plus three
SIP test files under `test/calculators/`. Modify catalog and privacy coverage,
and minimally update EMI's catalog assertion. Create `SIP_CALCULATOR_V1.md`,
update `CALCULATORS_V1.md` and `docs/CHANGELOG.md`, and retain this plan.

Before source edits, run all current calculator and Explorer navigation tests.
Then cover zero initial/lump sum/ROI; equivalent months/years; lump sums at
start/middle/end; before-start/after-end rejection; same-month dates; month/year,
leap-year and month-end boundaries; strict malformed/negative/over-limit inputs;
decimal ROI; maximum tenure; immutable rows; invested/returns accounting and
finite/nonnegative values across a deterministic boundary grid.

Lock an injected 05 Oct 2026 example and derive the expected future value
independently in the test using exact rational BigInt compounding of individually
dated contributions (not a copy of the monthly engine). Check fixed expected
currency values too. Controller tests cover clock capture, date parsing, unit
switching, stale-result invalidation, recalculation and reset. Widgets cover
catalog/back, validation, date entry/picker, summaries, semantics/keyboard,
320/390/768/1440px × light/dark × normal/2x text, and privacy.

Delivery gates: changed-Dart format; scoped Flutter analyze; SIP tests; every
calculator regression; Explorer regression; full Flutter suite; local release
web build; docs, migration-history and commit validators; scope/whitespace audit;
exactly one commit `feat(calculators): add SIP calculator`. Record actual results
and pre-existing Wasm/font warnings separately.

## Exclusions

No existing-calculator financial changes, negative ROI model, daily returns,
multiple/recurring lump sums, step-up SIPs, irregular returns, fees/taxes/exit-load
calculation, saving, exports, PDF/CSV, analytics or financial network APIs.
No auth, MFD, portfolio, NSE, CAMS, backend, migrations or dependencies change.
No canonical/main mutation, hosted DEV/Production access or remote delivery.

## Baseline before source edits

`flutter test --no-pub --reporter expanded test/calculators test/authentication/explorer_entry_test.dart`
passed **200 tests** (192 calculator tests + 8 Explorer tests) in 67 seconds.
Dependencies resolved offline. Logs: `/tmp/moneybowl-sip-v1-evidence/baseline.log`.
No implementation source had changed before this passing baseline.

## Implementation Deviations

None in architecture or financial convention. Both prior calculators remain
unchanged; only catalog metadata and its exact membership test changed. The
initial widget run required test-harness corrections for real edit events and
combined date-field semantics. No product requirements or assertions were weakened.
