> **Current bounded V1 status (2026-10-05): local implementation and frozen automated validation complete; independent review and hosted commissioning remain outstanding.** The older status immediately below is preserved as historical evidence. See the [release contract](INCOME_TAX_CALCULATOR_V1_RELEASE_SCOPE.md) and [final checks](#bounded-v1-release-validation--2026-10-05).

> Current status (2026-10-05): **PARTIAL LOCAL IMPLEMENTATION, UNCOMMITTED — NOT RELEASE READY**.
> The component-gated resumption appendices below supersede the earlier global stop.
> Historical blocked findings and evidence are intentionally retained.

# Income Tax Calculator V1 validation record

Date: 2026-10-05. **INCOMPLETE / BLOCKED at the research gate.**
No product implementation exists; none of the results below establishes
feature acceptance. See the [blocking verification gaps](INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md#blocking-verification-gaps).

## Repository and baseline evidence

Canonical checkout: `/home/ubuntu/moneybowl`, clean `develop` at
`85ccebf87721b5e52c62b209095ce7ebf474bd61`, equal to freshly fetched
`origin/develop`. The first sandboxed Git fetch failed DNS resolution; the
authorized fetch succeeded. No reset, rebase, repair or canonical code change.

New branch: `feature/calculators-income-tax-v1`.
New worktree: `/home/ubuntu/moneybowl-worktrees/calculators-income-tax-v1`.
Both were verified absent before creation. HEAD remains the base; no local
feature commit has been made. Only documentation is uncommitted.
Base tree: `a7368aaf3792ae955222424d2b2945763e45619e`.
Final canonical readback again found clean `develop` at the expected SHA.

Flutter SDK: `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter`.
Dependency resolution: `flutter pub get --offline`, PASS without tracked
dependency changes. Baseline command, before any product source edits:

```sh
flutter test --no-pub --reporter expanded test/calculators test/authentication/explorer_entry_test.dart
```

Result: **316 passed**, 92 seconds. The initial sandboxed runner could not bind
its local test socket; rerun with loopback permission passed. Runner and source
evidence is outside Git in `/tmp/moneybowl-income-tax-v1-evidence/`.

## Independent arithmetic checks of requested examples

The following hand calculations agree with the requested numbers and the
inspected slab/standard-deduction/rebate provisions. They do not close the
incomplete source gate and are **not locked production fixtures**. No production
engine was used or exists. No external website was supplied financial inputs.

| Synthetic input, resident below 60 | Derivation in rupees | Result |
| --- | --- | --- |
| Gross salary 1500000, Old | Taxable 1450000; 12500 + 100000 + 450000 × 30% = 247500; cess 9900 | 257400 |
| Gross salary 1500000, New | Taxable 1425000; 20000 + 40000 + 225000 × 15% = 93750; cess 3750 | 97500 |
| Gross salary 1275000, New | Taxable 1200000; slab tax 60000; rebate 60000 | 0 |
| Gross salary 1285000, New | Taxable 1210000; slab tax 61500; rebate marginal relief 51500; remaining tax 10000; cess 400 | 10400 |
| Ordinary taxable 1100000 + qualifying STCG 100000, New | Total income 1200000; ordinary tax 50000; special tax 20000; rebate limited to ordinary tax 50000; cess 800 | 20800 |

These arithmetic checks use the same displayed rates for each requested year,
but no shared/implicit year pack has been created. Relevant inspected sources:
[1961 Act departmental treatment table, section 16(ia)](https://www.incometaxindia.gov.in/w/treatment-of-income-from-different-sources-1),
[Finance Act 2025 section 20](https://incometaxindia.gov.in/Documents/Act/Finance-Act-2025.pdf),
[Finance Act 2026 First Schedule](https://www.incometaxindia.gov.in/documents/d/guest/finance-act-2026-pdf-1),
and [2025 Act sections 19, 156, 196 and 202](https://www.incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf).
No arithmetic discrepancy was found in these examples. Comprehensive enacted-
law coverage, boundaries, mixed-income interactions and subsequent amendments
remain unverified; this is not a claim that all golden requirements passed.

## External comparisons

| Comparator | Date | Inputs submitted / outputs obtained | Status |
| --- | --- | --- | --- |
| Official public calculator | 2026-10-05 | None; user manual inspected only | NOT_RUN — stopped at research gate |
| ClearTax / Groww / Tax2win | 2026-10-05 | None | NOT_RUN — stopped at research gate |

There is no same-year interactive comparison evidence and no claim that an
interactive calculator was unavailable. No competitor constants/code were used.

## Required implementation checks

| Check | Status |
| --- | --- |
| Before-edit existing calculator and Explorer baseline | PASS: 316 tests |
| Complete two-year official-source register | BLOCKED: B1/B2/B3; other unfinished rows explicitly identified |
| New domain/controller/widget/golden/boundary tests | NOT_RUN: not implemented |
| Format and scoped analyzer | NOT_RUN: no Dart changes |
| Post-implementation calculator/Explorer regressions | NOT_RUN: implementation not reached |
| Full Flutter suite | NOT_RUN: research gate blocked |
| Local release web build with synthetic/loopback configuration | NOT_RUN: research gate blocked |
| Documentation/link validation | PASS: 51 Markdown files checked; repository validator covers relative links, not remote HTTP availability |
| Migration-history validation | PASS: 27 frozen files through 20260801000000; no migration changes |
| Commit-message validation and validator tests | PASS: requested message format and 5 validator tests; no commit created |
| Diff/scope/whitespace checks | PASS: git diff --check; only six documentation files added/modified; no lib/test/backend/dependency changes |
| Tax-professional review | NOT_PERFORMED |
| Hosted commissioning | NOT_PERFORMED |

No build ran, so no new Wasm/font warning observation is claimed. The historical
Wasm `dart:js` and Cupertino font warnings are documented in the existing
[SIP delivery](SIP_CALCULATOR_V1.md); they are not blockers observed in this run.

## Downloaded evidence

| File outside Git | Bytes | SHA-256 |
| --- | --- | --- |
| `rules2026.pdf` | 10019228 | `30bc85bf9d3ff23f378d5ddd2ca1d2e3d223134471fc8163aa5e2feecacb7e51` |
| `itr2-validation-ay2026.pdf` | 740989 | `2321c5ba2469d3c9eaeee40d906b99abe56176782d547e6d0ec09ffdb529550b` |

Text extraction is retained beside these files. Act URLs accessible in the web
reader were not successfully downloaded locally; do not infer PDF hashes for
those failed downloads. Gazette retrieval errors and rejected wrong-year source
are documented in the source register.

## Safety record

```text
SUPABASE_MIGRATIONS=NO
HOSTED_DEV_MUTATED=NO
PRODUCTION_OR_MAIN_TOUCHED=NO
CALCULATOR_DATA_TRANSMITTED_OR_PERSISTED=NO
PUSH_PERFORMED=NO
PR_CREATED=NO
DEPLOYMENT_PERFORMED=NO
TAX_PROFESSIONAL_SIGNOFF=NOT_PERFORMED
HOSTED_COMMISSIONING=NOT_PERFORMED
```

No additional AI sessions were started. All existing calculator and
authorization source files remain unchanged. The only scope deviation is the
required fail-closed stop before implementation; the incomplete calculator is
not represented as a working catalog entry or a completed release.

## Files added or modified

Added four documentation files under `docs/architecture/`:

- `INCOME_TAX_CALCULATOR_V1_IMPLEMENTATION_PLAN.md`
- `INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md`
- `INCOME_TAX_CALCULATOR_V1.md`
- `INCOME_TAX_CALCULATOR_V1_VALIDATION.md`

Modified `docs/architecture/CALCULATORS_V1.md` and `docs/CHANGELOG.md` only to
record the blocked research status. These six files are uncommitted. No new
tax input, output, rule pack, source fixture or calculator test was added.

## Resumption validation — 2026-10-05

Fresh canonical fetch/readback: clean develop, HEAD and origin/develop still
`85ccebf87721b5e52c62b209095ce7ebf474bd61`. Existing feature branch/worktree
retained at that base with zero feature commits. No app/test/auth/backend/
dependency source changes were found. The six documentation changes and the
pre-existing `.github/scripts/__pycache__/` were preserved; no bytecode staged.

The independent handoff SHA-256 matched the user's value and every entry of
its `evidence.sha256` passed. Its v1.3 ZIP, formula inspection, retained Gazette
PDF and extracted text were inspected. The official index now lists v1.4,
released 13 August 2026; a separate verified-TLS download and static inspection
were performed. Both versions remain outside Git. No macros were executed and
cached workbook numbers were excluded from validation evidence.

Independent Fraction-arithmetic checks for `B2-LTCG-50L-NEW` and
`B2-LTCG-50L-OLD-BELOW60` **PASS as conflict reproductions**. They are not
passing feature tests. The active formula versions agree but exceed the enacted
tax-plus-surcharge ceiling by 15625, or 16250 after cess/rounding, for the
synthetic pure-LTCG input 5000800. Full inputs, intermediate cells, provisions
and outcomes are in the [source-register conflict](INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md#b2--active-dependency-trace-and-material-conflict-b2-mr-112a-50l).

| New retained artifact under `/tmp/moneybowl-income-tax-v1-evidence/` | SHA-256 |
| --- | --- |
| `itr2-2026-v1.4.zip` | `77ad3dcc84f138ac74c1f9f2ed871ee0ca20ba301fc8d8c81d326e2fa3c830f7` |
| `downloads-index-20261005.html` | `118d35288e7e9a2c7bdb47ff39ddcd6db96cd9e21a71a50eff986a265cf6cbe6` |
| `v1.4-active-formulas.json` | `c4b014a77c6cc30bbf72e99e452c0b430d77764a3996cd37cd4d035478d1d09c` |
| `reproduce_b2_conflict.py` | `f2e8d6b17ec5e6d868eabde944583892a7155b3a2f5a74df4ad7b3a832b557ca` |
| `b2-conflict-vectors.json` | `765059879d4a90d27d7207d77d9082762ee0a008d5b695054e028b9765efb3e0` |

The complete new evidence manifest is `resumption-evidence.sha256`; the
original handoff manifest remains unchanged. Static extraction used an isolated
research Python environment outside Git; application dependencies did not change.

The previously recorded 316-test baseline remains the before-source-edit
baseline; no implementation source edit occurred. New tax/golden/controller/
widget tests, full Flutter suite, analyzer and release build remain **NOT_RUN**
because the required research gate has not passed. No new Wasm/font warning
claim is made. External interactive official/renowned calculator comparisons
remain **NOT_RUN**, distinct from performed static utility inspection and local
independent arithmetic. Tax-professional signoff and hosted commissioning remain
**NOT_PERFORMED**. All safety flags above remain unchanged.

Resumption documentation validation passed for all **51 Markdown files**
(repository structure/relative links/anchor rules; not a remote-link availability
certificate). Migration-history validation passed for **27 frozen files** through
`20260801000000`. Commit-validator regressions passed **5 tests**; the requested
commit title remains valid, but no feature commit exists. Evidence-manifest,
diff/whitespace, empty-index and documentation-only scope checks passed.
Final canonical readback is clean at the expected HEAD/origin/develop; the
feature worktree is intentionally unclean with the same six documentation paths
and pre-existing untracked bytecode. HEAD/tree remain the base values above.

## Current component-gated candidate validation — 2026-10-05

**INCOMPLETE, tested local progress, uncommitted.** This appendix supersedes the
historical documentation-only/global-stop status above. Neither passing local
tests nor the resolved pure-LTCG comparator discrepancy certifies the full V1.
All original income categories and interaction requirements remain the target.

### Source verification and independent expected results

The [component source register](INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md#component-certification-register--2026-10-05)
binds enacted provisions separately for FY2025–26 / AY2026–27 (1961 Act) and
Tax Year2026–27 (2025 Act), with effective dates, interpretations and executable
test mapping. Rates shared by the two packs were checked separately. Notified
2026 rules, the retained seven-page Gazette and later identified instruments
are distinguished from utility behavior and search leads. The bounded amendment
review remains unfinished, including the exact Notification97 PDF retrieval gap.

Independent Python Fraction arithmetic generated360 ordinary/sole-LTCG golden
rows before production implementation, using closed-form schedule expressions.
The Dart engine evaluates them for each year, giving720 golden test executions.
Hand-derived salary, gains, deduction, property and HRA examples supplement
these rows. Expected results were not generated by invoking the tax engine.
The fixture contains sources, date, rule input and every expected tax stage.

| Required synthetic example, below60, both year packs | Old liability | New liability | Current result |
| --- | --- | --- | --- |
| Gross salary1500000; no other entries | 257400 | 97500 | PASS |
| Gross salary1275000; no other entries | Not a requested Old golden | 0 | PASS |
| Gross salary1285000; New taxable1210000 | Not a requested Old golden | 10400 | PASS |
| Ordinary taxable1100000 + eligible equity STCG100000 | Not a requested Old golden | 20800 | PASS, special tax survives rebate |

Pure-LTCG boundary expectations (below60, no other income/deductions/credits):

| Entered eligible LTCG | Old rounded liability | New rounded liability |
| --- | --- | --- |
| 4999990 | 601250 | 581750 |
| 5000000 | 601250 | 581750 |
| 5000010 | 601260 | 581760 |
| 5000800 | 602080 | 582580 |
| 5100000 | 675680 | 654230 |

Both year packs pass these independent fixtures. TY2026 bindings use2025
section198/516 and Finance Act2026 section3/PartI-B, not the AY utility as law.
For FY2025 at5000800, exact New/Old income tax559475/578225; cutoff
tax559375/578125; tax-plus-surcharge ceiling560175/578925; after
cess582582/602082. Final liability582580/602080 agrees with the user's
independent disposition. The general formula retains the125000 threshold at
the cutoff; no fixed16250 correction exists in production code.

Separate comparator test: retained active v1.3/v1.4 formulas produce
New598830/Old618330. Status is **STATIC_FORMULA_REPRODUCTION**, not
EXECUTED_OFFICIAL_UTILITY_RESULT. This known explained discrepancy is preserved,
with no workbook patch, downloaded macro execution or cached-value assertion.
It is not departmental confirmation of a defect. Professional review is pending.

### Coverage matrix

`V` means the described bounded behavior is implemented and has targeted passing
tests. `G` means an entered dependency returns typed `TaxNotYetVerified` and
withholds **both** regime estimates. `D` means the selected regime disallows the
deduction and the tested result explicitly shows that decision. `P` means further
acceptance coverage or guided input work remains. Each V is limited to its row;
it is not a complete-category certification for every possible interaction.

| Income category / relevant interaction | FY25 Old | FY25 New | TY26 Old | TY26 New | Boundary of current coverage |
| --- | --- | --- | --- | --- | --- |
| Salary/employment pension, one capped standard deduction | V | V | V | V | Gross salary definition and employer inclusion confirmation required |
| Ordinary slabs, rebate, rebate marginal relief, cess | V | V | V | V | Golden boundaries below60; all age bands have targeted examples; exhaustive age-specific matrix still P |
| Ordinary-only surcharge and marginal relief | V | V | V | V | Below/at/above each applicable surcharge band and paise/rounding boundaries |
| HRA periods, city groups, no commission | V | D | V | D | Non-overlap, selected-period dates, gross inclusion, Hyderabad/Mumbai/other test examples |
| HRA commission | V/P | D | G | D/G | Legacy salary definition implemented; TY26 interpretive binding missing, atomic comparison withheld |
| Professional tax within salary; negative salary head | V/G | D/G | V/G | D/G | Negative Old head requires separate set-off verification |
| Family pension distinct from employment pension | V | V | V | V | One-third deduction with separate regime limits |
| Bank savings/deposit interest; other taxable interest | V | V | V | V | Automatic eligible TTA/TTB Old only; other-interest exclusion tested |
| Post-office savings/special interest exemption | G | G | G | G | Notification and two-year applicability pending; explicit pending selection |
| Ordinary domestic company dividends | V/G | V/G | V/G | V/G | Included in ordinary income; above2crore attribution G; REIT/InvIT/pass-through unsupported |
| EPF/PPF/ELSS/80CCC investment group | V | D | V | D | Shared150000 and available ordinary-income cap; other instruments P/G |
| Own NPS, additional/group split | V | D | V | D | Contribution used once, employee/nonemployee percentages; employer/employee guard |
| One government/private employer NPS | V | V | V | V | Salary inclusion once and regime/employer-specific limit; multiple employers G |
| Health insurance, medical and preventive checks | V | D | V | D | Two buckets, conditions, shared5000, no bucket overclaim |
| Eligible education-loan interest | V | D | V | D | Principal excluded, qualifying facts, repayment years8/9 tested |
| One completed fully owned self-occupied property | V | D | V | D | Purpose/date/completion/certificate distinguish30000/200000 limits |
| One completed fully owned let-out property | V | V | V | V | GAV attestation, paid municipal taxes,30%NAV, eligible interest |
| Property intra-head/current inter-head loss with salary | V | V/D | V | V/D | Old200000 ceiling; New no inter-head use; unused/disallowed loss disclosed |
| Property loss with gains or interest-deduction income | G | G | G | G | Old allocation unresolved, so atomic comparison withheld |
| Municipal taxes exceeding GAV | G | G | G | G | Signed NAV and statutory deduction interaction pending |
| Sole qualifying equity STCG | V/P | V/P | V/P | V/P | Basic shortfall/rate/rebate tested; complete pure-ST surcharge golden matrix P |
| Sole qualifying equity LTCG | V | V | V | V | Annual threshold, basic shortfall, all surcharge bands, statutory rounding |
| Ordinary plus gains below surcharge range, sufficient ordinary basic exemption | V | V | V | V | Special rebate restrictions and deduction limits tested |
| Combined gains needing unused basic exemption | G | G | G | G | Active utility ST-first evidence not certified as two-year legal allocation |
| Mixed special-income surcharge above50lakh | G | G | G | G | General cutoff composition and component caps/relief pending |
| Mixed-income rounding with negative ordinary residual | G | G | G | G | No negative income, clipping or double exemption allocation |
| Optional entered TDS/TCS/advance/self-assessment credits | V | V | V | V | Exact liability less credits then statutory rounding; payable/zero/refund |
| Normal/Advanced shared engine, state and privacy | V | V | V | V | Equivalent entries, retained advanced fields, year/input invalidation, reset, route disposal |

The full original tax acceptance matrix is **not complete**. Remaining fixtures
must cover the gated branches, every relevant mixed cutoff, broader eligibility
and age/city combinations, and the guided inputs still pending. Core implemented
tax assertions pass; no failing assertion is skipped or declared acceptable.

### Automated checks and local build

Commands use SDK `/home/ubuntu/.local/share/flutter-moneybowl/bin/` and run from
the feature worktree. Logs are retained in
`/tmp/moneybowl-income-tax-v1-evidence/`. Local test socket permissions were
required; no hosted service was accessed.

| Check | Result / evidence |
| --- | --- |
| Fresh before-source calculator + Explorer baseline | PASS316,91s; `component-baseline.log` |
| Feature domain/golden/controller/widget plus unchanged calculator privacy test | PASS755 (754 new feature tests +1 privacy),12s; `component-feature.log` |
| Existing/new calculator + Explorer regression run before final two guards | PASS1068,103s; `component-regressions.log`; final full-suite run below includes those guards |
| Final full Flutter suite, `flutter test --no-pub --reporter expanded` | PASS1536,203s; `component-full-suite.log` |
| Scoped analyzer, calculator feature and calculator tests | PASS, no issues; `component-analyzer.log` |
| Format check, all17 changed/new Dart files | PASS,0 changes; `component-format.log` |
| Release web build, `flutter build web --release --no-pub` | PASS93.9s; `component-release-build.log`; output `build/web` remains ignored local build output |
| Documentation and relative-link/structure validation | PASS51 Markdown files; `component-docs.log`; not a remote-link availability certificate |
| Frozen migration-history validation | PASS27 files through20260801000000; `component-migrations.log`; no migration created |
| Commit-validator regression checks and requested title | PASS5 tests and valid requested title; `component-commit-validator.log`, `component-commit-subject.log`; no commit created |

Release configuration used only
`SUPABASE_URL=http://127.0.0.1:54321` and
`SUPABASE_ANON_KEY=synthetic-local-build-key`. The build did not connect to a
hosted database or deploy output. Pre-existing warnings remain: Wasm dry-run
finds `dart:js` in `screens/admin_dashboard.dart` and `utils/excel_updater.dart`;
font check cannot find the referenced CupertinoIcons family. JavaScript release
build succeeds. No claim of Wasm compatibility or warning remediation is made.

Widget checks include320px at2× text, light/dark and desktop layouts, Calculate
semantics, keyboard traversal, route entry/disposal and an HTTP-client override
that rejects requests. Existing static privacy assertions were not weakened.
Manual assistive-technology commissioning and real browser interaction are not
claimed. All test amounts are synthetic; calculator entries/traces remain local
ephemeral state with no service, storage or logging dependencies.

### External numerical comparison status

| Comparator, accessed2026-10-05 | Exact-year/input evidence | Status |
| --- | --- | --- |
| [Official public calculator](https://eportal.incometax.gov.in/iec/foservices/#/TaxCalc/calculator) and [manual](https://www.incometax.gov.in/iec/foportal/help/all-topics/e-filing-services/income-tax-calculator-um) | Manual distinguishes Acts/years and Basic/Advanced; calculator reader exposes only a JavaScript shell; no vector submitted or calculated output observed | NOT_RUN, interactive comparison |
| [ClearTax calculator](https://cleartax.in/paytax/TaxCalculator) | Current page identifiesFY2026–27; reader access does not execute the form for a synthetic vector. Default zero values are not evidence | NOT_RUN, interactive comparison |
| Retained official AY2026–27 ITR2 v1.3/v1.4 workbooks | Active formulas/dependencies statically inspected; independent exact arithmetic reproduces known B2 discrepancy | STATIC_FORMULA_REPRODUCTION, performed; no macros executed |

No entered financial data was sent to these services. No comparison was made
against a different income year. Independent enacted-law vectors are passing
for implemented components; unresolved interpretations are distinct from the
known explained utility discrepancy.

### Delivery state and exact changed-file inventory

Expected base and feature HEAD remain
`85ccebf87721b5e52c62b209095ce7ebf474bd61`; committed tree remains
`a7368aaf3792ae955222424d2b2945763e45619e`. There is no candidate commit or
committed candidate tree. Branch `feature/calculators-income-tax-v1`, worktree
`/home/ubuntu/moneybowl-worktrees/calculators-income-tax-v1`, zero feature commits.
The index is empty; the worktree intentionally contains uncommitted progress.
Canonical develop is clean at the expected base. Research artifacts/manifests
and original blocked history are preserved. Generated Python bytecode remains
untracked and is not part of this candidate.

Modified tracked files (5):

- `docs/CHANGELOG.md`
- `docs/architecture/CALCULATORS_V1.md`
- `lib/features/calculators/presentation/calculator_catalog.dart`
- `test/calculators/emi_widgets_test.dart` — catalog IDs/count only
- `test/calculators/sip_widgets_test.dart` — catalog IDs/count only

Added documentation files (4, retained from the original six-document state):

- `docs/architecture/INCOME_TAX_CALCULATOR_V1_IMPLEMENTATION_PLAN.md`
- `docs/architecture/INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md`
- `docs/architecture/INCOME_TAX_CALCULATOR_V1.md`
- `docs/architecture/INCOME_TAX_CALCULATOR_V1_VALIDATION.md`

Added feature files (11):

- `lib/features/calculators/income_tax/domain/exact_amount.dart`
- `lib/features/calculators/income_tax/domain/house_property.dart`
- `lib/features/calculators/income_tax/domain/income_tax_engine.dart`
- `lib/features/calculators/income_tax/domain/special_income.dart`
- `lib/features/calculators/income_tax/domain/tax_deductions.dart`
- `lib/features/calculators/income_tax/domain/tax_exemptions.dart`
- `lib/features/calculators/income_tax/domain/tax_rules.dart`
- `lib/features/calculators/income_tax/models/tax_input.dart`
- `lib/features/calculators/income_tax/models/tax_result.dart`
- `lib/features/calculators/income_tax/presentation/income_tax_controller.dart`
- `lib/features/calculators/income_tax/presentation/income_tax_screen.dart`

Added tests/fixtures (4):

- `test/calculators/income_tax/fixtures/statutory_goldens.json`
- `test/calculators/income_tax/income_tax_engine_test.dart`
- `test/calculators/income_tax/income_tax_state_test.dart`
- `test/calculators/income_tax/income_tax_widgets_test.dart`

Existing Loan Part Payment, EMI and SIP mathematics/source are unchanged. Only
the shared catalog and necessary catalog-count assertions changed. Authorization,
dependencies, backend, secrets and migration source are unchanged. No feature
commit is made because complete scope/acceptance conditions are unmet. Source
verification gaps, pending implementation/coverage, independent tax-professional
review and hosted commissioning remain separate gates; this is not publishable.

Final fresh `git fetch origin develop` and asserted readback passed: canonical
clean, expected HEAD/origin/develop, original feature branch at the base, zero
feature commits and empty index. Scope and whitespace checks passed for all24
candidate paths, including untracked source/fixtures. Existing two bytecode files
were preserved and excluded. Both original research manifests still verify;
independent generator/fixture hashes still match the source register. Final state
is retained as `component-final-state.json`; `component-candidate.sha256` lists
the24 candidate file contents and `component-evidence.sha256` records current
validation artifacts, outside Git. These are evidence manifests, not a Git
candidate tree or runtime dependency.

```text
SUPABASE_MIGRATIONS=NO
HOSTED_DEV_MUTATED=NO
PRODUCTION_OR_MAIN_TOUCHED=NO
CALCULATOR_DATA_TRANSMITTED_OR_PERSISTED=NO
PUSH_PERFORMED=NO
PR_CREATED=NO
DEPLOYMENT_PERFORMED=NO
TAX_PROFESSIONAL_SIGNOFF=NOT_PERFORMED
HOSTED_COMMISSIONING=NOT_PERFORMED
```

## Continuation validation — 2026-10-05 (revision2)

This append-only record supersedes the preceding24-file candidate state. The
original24-file manifest was verified before edits; original evidence/manifests,
blocked history and generated bytecode were preserved. No branch/worktree was
recreated and no additional AI session was started. Fresh canonical fetch still
matches the expected clean develop base. No candidate commit has been made.

New implemented gates and source→interpretation→fixture→implementation→test
bindings appear in the [current source matrix](INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md#current-rule-to-test-closure-matrix-local-rule-pack-revision2).
Coverage below explicitly distinguishes completed branches from typed safety
coverage. `PASS` means implemented and tested within the named condition, not
certification of every possible combination. Both modes invoke the same engine;
actual controls now exercise Advanced rows and their retention in Normal.

| Category / interaction | FY25 Old | FY25 New | TY26 Old | TY26 New | Evidence / remaining condition |
| --- | --- | --- | --- | --- | --- |
| Salary/pension, standard deduction, ordinary slabs, rebate/relief, cess |PASS|PASS|PASS|PASS|Original acceptance vectors retained; expanded all-age boundaries |
| Ordinary surcharge and relief |PASS|PASS|PASS|PASS|All ages,50L/1Cr/2Cr/5Cr just below/at/above |
| Guided life/tuition/housing/NSC subscription + salary + shared cap |PASS|PASS(disallowed)|PASS|PASS(disallowed)|All ages; issue dates, assured-sum caps, child/lender eligibility |
| NSC interest reinvestment/final-year income + investment cap |PASS below60|PASS below60|PASS below60|PASS below60|Senior80TTB/153 classification PENDING; atomic comparison withheld |
| Multiple employer NPS with distinct contribution/base/type |PASS|PASS|PASS|PASS|All ages; mixed government/private; included/excluded salary; no own-base fallback |
| HRA commission, changing periods and city groups |PASS|PASS(disallowed)|PASS|PASS(disallowed)|Nine cities, both years; actual2-period add/edit/remove form journeys |
| Interest deductions + ordinary property/salary losses |PASS|PASS(regime restrictions)|PASS|PASS(regime restrictions)|Preserve eligible interest, then reduce deduction if loss spills into it; all ages |
| Individual Post Office Savings Bank exemption + interest deduction |PASS|PASS(exemption only)|PASS|PASS(exemption only)|3499.99/3500/3500.01 and3504.99/3505/3505.01; all ages |
| Joint/multiple post-office attribution, other special-interest exemptions |PENDING|PENDING|PENDING|PENDING|Typed safety gate only |
| Positive NAV, bounded SO/let-out combination |PASS|PASS|PASS|PASS|Original limits/set-off tests and ordinary-loss continuation |
| Negative NAV / loss allocation involving gains |PENDING|PENDING comparison|PENDING|PENDING comparison|Precise statutory/static conflict recorded; no apparent full estimate |
| Sole qualifying STCG/LTCG, basic shortfall, rebate and capped surcharge |PASS|PASS|PASS|PASS|Expanded all-age boundary goldens; B2 statutory and utility-discrepancy tests separate |
| Both gains with ordinary income exhausting basic exemption, total≤50L |PASS|PASS|PASS|PASS|Independent ordinary1100000+ST100000+LT around125000 and200000 |
| Both gains requiring unused basic exemption |PENDING|PENDING|PENDING|PENDING|No guessed priority; typed safety coverage only |
| Mixed ordinary/gain surcharge and cutoff composition |PENDING|PENDING|PENDING|PENDING|Income above50L; no pro-rata or fixed-amount correction |
| Pure company dividends, all surcharge bands |PASS|PASS|PASS|PASS|Whole tax attributable to dividends,15% cap; all ages and cutoffs |
| Mixed dividend attribution at enhanced surcharge bands |PENDING|PENDING|PENDING|PENDING|No allocation assumption; business-trust distributions remain excluded |
| Ordinary residual becomes negative after total-income rounding |PENDING|PENDING|PENDING|PENDING|No silent clipping or duplicate exemption allocation |
| Health/education/own NPS/credits |PASS bounded branches|PASS regime restrictions|PASS bounded branches|PASS regime restrictions|Original tests retained; broader unresolved combinations not certified |
| Extra instruments beyond named guided set / recapture |PENDING|PENDING comparison|PENDING|PENDING comparison|Separate from originally excluded donations/disability etc. |

Added independent fixture:645 synthetic vectors in
`test/calculators/income_tax/fixtures/age_interaction_goldens.json`, executed once
per explicit year pack (1290 tests). The retained Python Fraction derivation never
calls the production engine. The original360-vector fixture and B2 discrepancy
fixture/assertions remain unchanged. Browser-style journeys now fill actual text
fields, checkboxes and dropdowns; they do not set controller financial values.
Existing responsive/privacy tests remain intact.

Intermediate validation history is retained:770 domain/controller tests passed;
71 ordinary/widget tests passed;1885 feature tests passed before pure-dividend
expansion;1290 expanded age goldens passed. The first full continuation run
started before the final explicit-employer-base guard; its compiler retained the
old model while loading two new guard tests. Its results are not final acceptance.
Final checks below run against the frozen post-guard source; no failing tax
assertion is skipped, relaxed or accepted.

External comparison status remains **NOT_RUN** for official interactive and
renowned interactive calculators. Available tools provide page reading, not a
browser; no Chromium/Chrome/Firefox/Playwright executable was installed. No default
page values are represented as computed outputs. B2 remains
**STATIC_FORMULA_REPRODUCTION**, not EXECUTED_OFFICIAL_UTILITY_RESULT, with no
claim of department defect confirmation. New negative-NAV evidence is static
formula inspection only. Tax-professional review and hosted commissioning are
separate unperformed release gates.

### Exact candidate inventory and Git state after continuation

There are29 candidate paths relative to the feature worktree. They include
all24 original candidate paths and five additions. Generated bytecode is not
included. The29-path inventory is:

- `docs/CHANGELOG.md`
- `docs/architecture/CALCULATORS_V1.md`
- `docs/architecture/INCOME_TAX_CALCULATOR_V1.md`
- `docs/architecture/INCOME_TAX_CALCULATOR_V1_IMPLEMENTATION_PLAN.md`
- `docs/architecture/INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md`
- `docs/architecture/INCOME_TAX_CALCULATOR_V1_VALIDATION.md`
- `lib/features/calculators/income_tax/domain/exact_amount.dart`
- `lib/features/calculators/income_tax/domain/house_property.dart`
- `lib/features/calculators/income_tax/domain/income_tax_engine.dart`
- `lib/features/calculators/income_tax/domain/special_income.dart`
- `lib/features/calculators/income_tax/domain/tax_deductions.dart`
- `lib/features/calculators/income_tax/domain/tax_exemptions.dart`
- `lib/features/calculators/income_tax/domain/tax_rules.dart`
- `lib/features/calculators/income_tax/models/guided_deductions.dart`
- `lib/features/calculators/income_tax/models/tax_input.dart`
- `lib/features/calculators/income_tax/models/tax_result.dart`
- `lib/features/calculators/income_tax/presentation/income_tax_controller.dart`
- `lib/features/calculators/income_tax/presentation/income_tax_screen.dart`
- `lib/features/calculators/presentation/calculator_catalog.dart`
- `test/calculators/emi_widgets_test.dart`
- `test/calculators/income_tax/fixtures/age_interaction_goldens.json`
- `test/calculators/income_tax/fixtures/statutory_goldens.json`
- `test/calculators/income_tax/income_tax_age_goldens_test.dart`
- `test/calculators/income_tax/income_tax_engine_test.dart`
- `test/calculators/income_tax/income_tax_guided_test.dart`
- `test/calculators/income_tax/income_tax_ordinary_test.dart`
- `test/calculators/income_tax/income_tax_state_test.dart`
- `test/calculators/income_tax/income_tax_widgets_test.dart`
- `test/calculators/sip_widgets_test.dart`

Fresh canonical fetch and asserted readback: develop and origin/develop equal
`85ccebf87721b5e52c62b209095ce7ebf474bd61`, canonical clean. Feature branch
`feature/calculators-income-tax-v1` remains at that base in
`/home/ubuntu/moneybowl-worktrees/calculators-income-tax-v1`. Committed tree remains
`a7368aaf3792ae955222424d2b2945763e45619e`; zero feature commits and empty index.
There is no committed candidate tree. Candidate progress is intentionally dirty
and uncommitted. No commit is made while the full agreed scope remains pending.

Existing calculator mathematics/source and authorization remain unchanged. The
only existing application source change is the catalog; existing EMI/SIP widget
changes are catalog IDs/counts only. The unchanged privacy boundary test still
scans all calculator imports, storage and logging. No dependency, secret, backend,
migration, main or Production source change is present.

Independent fixture provenance: `continue_goldens.py` SHA256
`b6d209b5ce4de332bf78dbf76674e6cc68676e7645afdae11ccc10658d0c22cf`;
`age_interaction_goldens.json` SHA256
`72c9eddc9c00be00cf1120cb03c19e8b1f8931f10da85f9527d81d08c8c6afb7`.
The original two research manifests verify again. New evidence and a final
candidate manifest are retained outside Git under the existing evidence directory
with `continue-` filenames; they do not replace the original manifests.

### Final frozen-source checks for this continuation

| Check | Result and retained evidence |
| --- | --- |
| Full Flutter suite after explicit employer-base guard |**PASS2915**,237s; `continue-final-full-suite.log`; no failures/skips accepted |
| Income-tax domain/controller/widget/independent goldens |**PASS2133** within final full suite;645 new independent vectors×2 packs, original goldens and separate static B2 discrepancy assertions retained |
| All calculators + Explorer navigation + unchanged privacy regression |**PASS**,2449 test-start entries within final full suite; Explorer8; no existing calculator math/auth assertion weakened |
| Scoped analyzer, all calculators/tests and Explorer |**PASS**, no issues,5.1s; `continue-final-analyzer.log` |
| Format check |**PASS**,21 Dart files,0 changes; `continue-format-check.log` |
| Final local release web build after full-suite pass |**PASS**,95.5s; `continue-final-release-build.log`; synthetic loopback configuration only |
| Documentation/link/structure validator |**PASS**,51 Markdown files; `continue-docs.log`; validates local documentation, not legal correctness or live remote-link availability |
| Frozen migration history |**PASS**,27 files through20260801000000; `continue-migrations.log` |
| Commit validator tests / requested title |**PASS5** and valid title; `continue-commit-validator.log`, `continue-commit-subject.log`; no commit created |
| Candidate diff/scope/whitespace, including untracked additions |**PASS29** paths; `continue-diff-check.log`; empty index and unchanged base/source scope |
| Retained original research manifests |**PASS**, `continue-original-research-check.log` and `continue-resumption-check.log` |

The build used `SUPABASE_URL=http://127.0.0.1:54321` and
`SUPABASE_ANON_KEY=synthetic-local-build-key`; it did not deploy or connect to a
hosted database. Pre-existing Wasm dry-run warnings still name `dart:js` in
`admin_dashboard.dart` and `excel_updater.dart`; the existing CupertinoIcons
font-family warning remains. JavaScript release output built successfully.

The prior concurrent validation run is retained as `continue-full-suite.log`:
2913 passed and two new missing-employer-base assertions failed against its
already-compiled old model. A fresh run after source freeze passes all2915,
including those unchanged assertions. The prior155.2s build is historical;
the final95.5s build is the accepted local build for this source. No final failing
tax assertion is waived. These passes establish tested partial progress, not
completion of the still-gated original tax requirements.

The complete defined implementation is **INCOMPLETE** and remains uncommitted.
Remaining gates: combined-gain shortfall allocation; mixed gain surcharge/cutoff
composition; mixed dividend attribution; gain-related head-loss allocation;
negative NAV; special-component rounding where ordinary residual would become
negative; senior NSC interest, joint/multiple post-office attribution, other
special-interest exemptions, extra instruments and recapture. Their concrete
provisions, inspected formulas and diagnostic conflicting outcomes are retained
in the source register. Professional review and hosted commissioning are still
separate release gates, not substitutes for unfinished implementation.

```text
SUPABASE_MIGRATIONS=NO
HOSTED_DEV_MUTATED=NO
PRODUCTION_OR_MAIN_TOUCHED=NO
CALCULATOR_DATA_TRANSMITTED_OR_PERSISTED=NO
PUSH_PERFORMED=NO
PR_CREATED=NO
DEPLOYMENT_PERFORMED=NO
TAX_PROFESSIONAL_SIGNOFF=NOT_PERFORMED
HOSTED_COMMISSIONING=NOT_PERFORMED
```


## IT-REVIEW-001 continuation — 2026-10-05

Pre-edit `continue-candidate.sha256` verified all29 paths. Fresh canonical fetch
and readback retain clean develop at the expected base; feature has zero commits.
Reviewer artifacts and prior research/history remain outside Git unchanged.
No generated bytecode is staged. The new logs use `review001-` prefixes and do
not overwrite accepted `continue-` evidence.

Test-first evidence: `review001-red.log` records the sandbox's loopback-socket
restriction, not a tax test result. Rerun with the local test-server permission,
`review001-red-executed.log`, executed16 tests:12 passed and4 failed on the missing
base defect (domain and actual-form assertions for both years). No source fix
preceded this failure. `review001-green.log` then passed those16 tests after the
correction. Reverse employer-base fallback tests were subsequently added without
changing the pre-existing employer-base regressions. Final frozen-source runs
include all18 new tests. The widget cases exercise omission, whitespace, explicit
zero,800000, clearing after success, employee/nonemployee toggles, additional-only
and exhausted-cap contributions using actual controls.

Independent reviewer/hand arithmetic before and after:

| Salary / own NPS / employee base | Previous outcome | Corrected outcome in each year |
| --- | --- | --- |
|1500000 /200000 / omitted or blank | Full comparison; Old TI1400000, liability241800 | TaxInvalidInput naming Own-NPS salary base; no winner |
|1500000 /200000 / explicit0 | Old TI1400000, liability241800 | Same numeric result for explicitly declared zero components |
|1500000 /200000 /800000 | Old TI1320000, liability216840 | Same independently verified result |
|1500000 /50000 / omitted | Additional-only deduction | Comparison remains available |
|1500000 /200000 / omitted, EPF150000 | Exhausted group, additional50000 | Comparison remains available; Old195000 |
|1500000 /200000 / omitted, nonemployee |20%-GTI calculation | Comparison remains available; Old195000 |

The source/interpretation/test binding is IT-NPS-BASE-REQUIRED in the source
register. The finite acceptance register in the implementation plan defines exact
remaining scenarios and closure criteria. This correction closes no unresolved
mixed-income legal rule. B2 remains STATIC_FORMULA_REPRODUCTION with separate
statutory goldens; interactive official/renowned comparisons remain NOT_RUN.


### Frozen-source results for IT-REVIEW-001

`review001-frozen-source.sha256` was written after the final test/source edit,
before calculator regressions, the full suite, analyzer and build. Its post-build
check passes. No application or test source was edited while any final check ran.
Documentation was appended separately and revalidated after this results entry.

| Check | Result / retained evidence under `/tmp/moneybowl-income-tax-v1-evidence/` |
| --- | --- |
| Reviewer regressions and original probe | PASS18 new tests in final scoped run; `review001-probe-after.jsonl` reproduces the before/after distinction using the untouched independent probe |
| Income-tax domain/controller/widgets/goldens | PASS2151 test entries; both year packs, unchanged independent fixtures and separate B2 statutory/static assertions |
| All calculators plus Explorer | PASS2467,140s; `review001-calculator-explorer.log`; includes8 Explorer tests and unchanged privacy coverage |
| Full Flutter suite | PASS2933,326s; `review001-full-suite.log`; no failed tax assertion waived |
| Scoped analyzer | PASS no issues,4.4s; `review001-analyzer.log` |
| Format | PASS21 Dart files,0 changes; `review001-format.log` |
| Synthetic local release web build | PASS152.3s; `review001-release-build.log`; loopback URL and synthetic key, no hosted access/deployment |
| Documentation/links | PASS51 Markdown files; `review001-docs.log`; local link/structure validation, not an assertion that all external sites are accessible |
| Frozen migration history | PASS27; `review001-migrations.log` |
| Commit validator tests/title | PASS5 and requested subject valid; `review001-commit-tests.log`, `review001-commit-subject.log`; no commit created |
| Scope/diff/whitespace | PASS29 candidate paths, empty index, bytecode untouched; `review001-diff-check.log` |
| Research preservation | PASS retained continue/resumption/handoff manifests; `review001-retained-evidence-check.log`, `review001-resumption-evidence-check.log`, `review001-handoff-evidence-check.log`; reviewer artifacts separately hashed |

Pre-existing build warnings: `dart:js` in `admin_dashboard.dart` and
`excel_updater.dart` is not Wasm compatible; missing CupertinoIcons font-family
warning persists. Successful JavaScript output is in local `build/web` only.

Nine existing candidate files changed in this run:

- `lib/features/calculators/income_tax/domain/tax_deductions.dart`
- `lib/features/calculators/income_tax/domain/income_tax_engine.dart`
- `lib/features/calculators/income_tax/presentation/income_tax_screen.dart`
- `test/calculators/income_tax/income_tax_guided_test.dart`
- `test/calculators/income_tax/income_tax_widgets_test.dart`
- `docs/architecture/INCOME_TAX_CALCULATOR_V1.md`
- `docs/architecture/INCOME_TAX_CALCULATOR_V1_IMPLEMENTATION_PLAN.md`
- `docs/architecture/INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md`
- `docs/architecture/INCOME_TAX_CALCULATOR_V1_VALIDATION.md`

All29 original candidate paths remain, with no added candidate files. The old
`continue-candidate.sha256` is preserved as historical input evidence; the new
`review001-candidate.sha256` binds this updated candidate. Changed-path detail,
final Git state and new evidence hashes are retained under `review001-` filenames.
Canonical develop/origin and feature HEAD remain
`85ccebf87721b5e52c62b209095ce7ebf474bd61`; committed tree
`a7368aaf3792ae955222424d2b2945763e45619e`. Feature branch remains
`feature/calculators-income-tax-v1` in the requested existing worktree. Canonical
is clean; feature is intentionally dirty, with empty index and zero feature
commits. There is no committed candidate tree.

**INCOMPLETE:** only IT-REVIEW-001 and the finite acceptance inventory closed in
this run. The37 entries in the plan distinguish32 pending calculation branches
from5 acceptance activities. No new mixed-income algorithm or legal conclusion
was implemented. The pure-LTCG utility discrepancy remains explained static
reproduction, not an executed official result or Department-confirmed defect.
Interactive external comparisons remain NOT_RUN. No additional scope is proposed.
Professional review and hosted commissioning have not occurred. Existing loan,
EMI and SIP mathematics, authorization and privacy boundaries remain unchanged.

```text
SUPABASE_MIGRATIONS=NO
HOSTED_DEV_MUTATED=NO
PRODUCTION_OR_MAIN_TOUCHED=NO
CALCULATOR_DATA_TRANSMITTED_OR_PERSISTED=NO
PUSH_PERFORMED=NO
PR_CREATED=NO
DEPLOYMENT_PERFORMED=NO
TAX_PROFESSIONAL_SIGNOFF=NOT_PERFORMED
HOSTED_COMMISSIONING=NOT_PERFORMED
```

## Bounded V1 release validation — 2026-10-05

The [explicit release-scope decision](INCOME_TAX_CALCULATOR_V1_RELEASE_SCOPE.md)
supersedes the historical all-37-entries-before-commit gate recorded above.
The [pending/blocked register](INCOME_TAX_CALCULATOR_V1_PENDING_AND_BLOCKED.md)
retains every original ID. A positive supported calculation and a typed
no-comparison check are separate forms of evidence. The source register binds
each shipped rule to its applicable Act, scheme notification, effective date,
interpretation and independent fixture.

| Coverage slice and relevant interaction | FY2025–26 Old | FY2025–26 New | TY2026–27 Old | TY2026–27 New | Positive computation and blocked neighbor |
| --- | --- | --- | --- | --- | --- |
| Salary/pension, ordinary interest, standard deduction, slabs, rebate, surcharge/relief, cess and rounding | Tested | Tested | Tested | Tested | Independent age/golden suites, all slab/rebate/surcharge boundaries, paise and statutory tens; special-rate tax does not disappear under rebate |
| HRA periods/commission, family pension, employer/own NPS and guided life/tuition/housing/NSC | Tested | Tested | Tested | Tested | Domain/guided tests plus actual-control HRA add/edit/remove and IT-REVIEW-001 missing-base journeys; senior NSC interest returns no comparison |
| Ordinary property and eligible current-year loss, single post-office savings exemption, bank/deposit/ordinary interest, pure company dividend | Tested | Tested | Tested | Tested | Positive ordinary-only and pure-dividend vectors; negative NAV, joint/multiple savings, enhanced-band mixed dividend and gain-related loss are blocked |
| Sole eligible equity STCG, sole eligible equity LTCG and currently verified ordinary/gain mixes | Tested | Tested | Tested | Tested | Statute-derived B2 LTCG result separate from static utility reproduction; combined gains with exemption shortfall and mixed surcharge cutoff return no comparison |
| Bank five-year tax-saving contribution | Tested | Tested | Tested | Tested | Salary1500000 + contribution100000: Old226200/New97500; EPF100000 too: Old210600/New97500; scheme bounds, ineligible declaration, income ceiling and separate taxable interest checked |
| Post-office five-year Time Deposit contribution | Tested | Tested | Tested | Tested | Same100000 fixture; five-year/current-year/single-holder declaration and scheme deposit bounds; shorter term not accepted |
| SCSS current-year deposit for person at least60 on opening date | Tested | Tested | Tested | Tested | Salary1500000 + contribution100000: age60–79 Old223600/New97500; below60 exception and invalid amount withhold comparison |
| Sukanya current-year contribution to one or two distinct eligible girl-child accounts | Tested | Tested | Tested | Tested | Same100000 fixture Old226200/New97500; two-child distinctness, ownership declaration, scheme bounds and shared cap checked |
| Optional entered tax credits, no persistence/network, mode/year/age/eligibility/reset transitions | Tested | Tested | Tested | Tested | Balance/refund/zero vectors and browser-style widget controls; blocked case shows no stale winner or payable/refund |

The four required investment IDs were source-gated before production edits.
The new direct-guided tests include at least 14 positive supported-result entries
for individual instruments, group cap, ordinary interest and available-income
conditions across both years, separately from invalid/deferred assertions.
Additional widget journeys exercise actual controls at 390px and large text.
Historical salary/gain/property/age goldens remain independent of the engine.
The test totals and frozen-source check results are recorded below after all
commands complete; this table itself is not a claim of professional review.

The candidate's final Dart source/test snapshot is listed in
`/tmp/moneybowl-income-tax-v1-evidence/release-frozen-source.sha256`
(21 exact paths; manifest SHA-256
`b64e3e50339047d40dfedc2847e351da98c69e87c20c6197e458e1b55a42175c`).
Earlier frozen manifests are retained to show why viewport, actual-gain-control
and final user-facing copy changes required new acceptance runs. No source was
edited while a frozen test/build command was running.

No Chromium, Chrome or Firefox executable or Playwright browser cache was
available in this local environment on 5 October 2026. Therefore local
release-build **browser smoke = NOT_RUN**. The official interactive public
calculator and renowned same-year interactive comparator were likewise
**NOT_RUN**: no synthetic inputs were submitted and no interactive output was
observed. Static official ITR-2 formula reproduction remains explicitly
`STATIC_FORMULA_REPRODUCTION`, not an executed utility result. The
[DEV runbook](INCOME_TAX_CALCULATOR_V1_DEV_COMMISSIONING.md) carries the
phone/browser, external-comparator, independent-review and controlled-hosted
checks forward as separate release gates. Neither hosted DEV nor Production
was touched by this task.

### Frozen automated checks on the final Dart snapshot

| Check | Result and evidence under `/tmp/moneybowl-income-tax-v1-evidence/` |
| --- | --- |
| Existing calculator/Explorer baseline before release edits | PASS788 scoped tests; `release-scope-baseline.log` |
| New scheme red/green development evidence | PASS16 newly added eligibility/fixture tests after production implementation; `release-investments-red.log` records the intentional test-first failures, `release-investments-green1.log` their resolution |
| Income-tax domain/controller/widget/independent goldens | PASS2205; `release-final-tax.log`; includes 2 actual-control gain journeys and 320/390/768/1440px coverage |
| All calculators plus Explorer | PASS2521; `release-final-calculator-explorer.log`; existing loan, EMI and SIP arithmetic source remains untouched |
| Scoped analyzer | PASS no issues; `release-final-analyzer.log` |
| Format | PASS21 Dart files, zero changes; `release-final-format-check.log` |
| Full Flutter suite | PASS2987; `release-final-full-suite.log`; no failing tax assertions waived |
| Synthetic local release web build | PASS98.5s; `release-final-build.log`; `--dart-define=SUPABASE_URL=http://127.0.0.1:54321` and synthetic public key, no hosted request or deployment |
| Source-hash readback after build | PASS21/21 exact Dart paths; `release-final-source-hash-check.log`; manifest hash above |
| Migration history | PASS27 frozen files; `release-final-migrations.log`; no migrations changed |
| Commit-validator regression tests | PASS5; `release-final-commit-validator-tests.log`; proposed subject validated separately |
| Documentation and relative links | PASS54 Markdown files; `release-final-docs.log`; validates local links/structure, not remote HTTP availability |
| 37-ID release and pending register | PASS equal sets of 37 unique IDs; `release-final-register-check.log` |
| Exact staged scope and whitespace | PASS32 intended paths, no bytecode/build/migrations/old-calculator mathematics/auth source; `release-final-diff-check.log`, `release-candidate.sha256`; staged `git diff --check` clean |

The successful JavaScript web build reports pre-existing Wasm dry-run
incompatibilities from `dart:js` in unchanged `admin_dashboard.dart` and
`excel_updater.dart`, plus the existing CupertinoIcons font-family warning.
These warnings are separate from income-tax correctness. `build/web` is ignored
local output and is not part of the candidate commit. The executable browser
smoke remains NOT_RUN because no browser binary/cache was available.

### Bounded V1 local acceptance and remaining release gates

All four `REQUIRED_FOR_V1` investment IDs are implemented against the two
explicit rule packs and pass positive, eligibility, cap, interest-separation and
actual-control checks. IT-REVIEW-001's omitted own-NPS salary base remains a
field-level input error; the 18 reviewer regressions and employer-base
separation tests remain in the passing suite. Supported results reconcile both
regimes through credits. Deferred input combinations produce no result, winner
or balance; the 37-ID release/pending registers preserve exact reopening work.
There is **no known unresolved defect in the declared supported V1 cases** and
no new unexplained numerical discrepancy in the accepted fixtures. This does
not claim the deferred original scope is implemented or that every legal tax
situation can be estimated.

The explained B2-MR-112A-50L finding remains a statute-derived acceptance
branch plus a separate `STATIC_FORMULA_REPRODUCTION` comparator branch. Neither
downloaded macros nor the department's calculator were executed; no
department-confirmed defect is claimed. The predecessor-scheme references,
official scheme-guide continuity inference, intermittent NSI PDF retrieval and
the 2023 premature-closure Gazette timeout remain visible in the source
register for independent review. Early closure and disputed account ownership
are outside the supported branch and withhold results.

| Remaining check | Status and disposition |
| --- | --- |
| Local browser build smoke, including phone-like Normal/Advanced journeys | NOT_RUN: no browser executable/cache; controlled DEV runbook names exact synthetic journeys |
| Official public calculator, same-year interactive comparison | NOT_RUN: no interactive browser; no synthetic submission/output observed |
| Renowned same-year interactive comparator | NOT_RUN: no interactive browser; no synthetic submission/output observed |
| Independent tax-professional signoff | NOT_PERFORMED: required before public financial use |
| Independent release review and hosted DEV commissioning | NOT_PERFORMED: approved workflow and exact deployed SHA verification required |
| Merge, push, PR, deployment, public financial use and Production readiness | NO: not authorised by this local candidate |

The local candidate is eligible for its one requested feature commit after
documentation/link and exact staged-diff checks pass. The commit is not merge
approval or permission for public financial reliance.
