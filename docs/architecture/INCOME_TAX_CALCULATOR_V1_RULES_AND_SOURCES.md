> Current status (2026-10-05): **PARTIAL LOCAL IMPLEMENTATION, UNCOMMITTED — NOT RELEASE READY**.
> The component-gated resumption appendices below supersede the earlier global stop.
> Historical blocked findings and evidence are intentionally retained.

# Income Tax Calculator V1 rules and sources

Research date: 2026-10-05. Status: BLOCKED, NOT VERIFIED FOR IMPLEMENTATION.
No tax engine or executable rule pack has been written. Listed test IDs are
planned coverage, not passing tests. Complete this register before tax code.

## Primary evidence

- [2025 Act amended by Finance Act 2026](https://www.incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf): official PDF accessible through public web research; direct download returned HTTP 403.
- [Finance Act 2026](https://www.incometaxindia.gov.in/documents/d/guest/finance-act-2026-pdf-1): enacted Act, official PDF accessible through public web research; direct download returned HTTP 403.
- [Notified Income-tax Rules 2026, official e-filing copy](https://www.incometax.gov.in/iec/foportal/sites/default/files/2026-03/En-Notified-IT-Rules-2026-20-03-2026.pdf): downloaded outside Git, SHA-256 `30bc85bf9d3ff23f378d5ddd2ca1d2e3d223134471fc8163aa5e2feecacb7e51` (10,019,228 bytes).
- [1961 Act amended by Finance Act 2026](https://www.incometaxindia.gov.in/documents/d/guest/income_tax_act_1961_as_amended_by_fa_act_2026-1-pdf): located official publication; relevant text/effective dates still require inspection.
- [Finance Act 2025](https://incometaxindia.gov.in/Documents/Act/Finance-Act-2025.pdf): located enacted official publication; direct download returned HTTP 403.
- [AY 2026–27 departmental guidance](https://www.incometax.gov.in/iec/foportal/help/individual/return-applicable-1).
- [Deductions guidance](https://www.incometaxindia.gov.in/w/deductions).
- [Treatment of income under the 1961 Act](https://www.incometaxindia.gov.in/w/treatment-of-income-from-different-sources-1).
- [Official calculator manual](https://www.incometax.gov.in/iec/foportal/help/all-topics/e-filing-services/income-tax-calculator-um).
- [Official ITR-2 validation rules AY 2026–27, version 1.0, 26 May 2026](https://www.incometax.gov.in/iec/foportal/sites/default/files/2026-05/CBDT__e-Filing_ITR%202_Validation%20Rules_AY%202026-27_V1.0.pdf): computation cross-check, not a substitute for enacted law.

Evidence directory: `/tmp/moneybowl-income-tax-v1-evidence/`. Do not commit
whole Acts or downloaded binaries. Document dates denote verification activity;
they do not establish that every subsequent amendment has been reviewed.

## Rule coverage checklist (research pending)

Every row needs a separate year applicability record, exact official provision,
effective date and source-linked independent tests before implementation.

| Stable rule ID | Scope | Located provisions / pending work | Planned tests |
| --- | --- | --- | --- |
| IT-PERIOD | Both regimes, both years | 2025 Act sections 1, 3, 536; 1961 year/residency rules pending | period_eligibility |
| IT-SLAB-OLD | Old, both years | Finance Act 2026 First Schedule Part I-A / Part III Paragraph A, age during year | old_slab_boundaries |
| IT-SLAB-NEW | New, both years | 1961 section 115BAC(1A)(iii); 2025 section 202(1), PDF pp.264–265 | new_slab_boundaries |
| IT-SALARY | Both | 1961 sections 15–17; 2025 sections 15–19; detailed checks pending | salary_standard_once |
| IT-HRA | Old, both years; disallowed New | 1962 Rule 2A pending; 2026 Rule 279, PDF p.244, 2025 Schedule III item 11 | hra_period_city_salary |
| IT-NPS | Both | 1961 80CCD; 2025 section 124; detailed checks pending | nps_employer_own_caps |
| IT-OTHER | Both | Interest/dividends/family pension provisions pending | other_sources |
| IT-PROPERTY | Both | 1961 22–24, 70–71; 2025 20–22, set-offs pending | property_limits_setoffs |
| IT-INVEST | Old | 1961 80C/80CCC/80CCD(1)/80CCE; 2025 mapping pending | investment_caps |
| IT-HEALTH | Old | 1961 80D; 2025 mapping pending | health_bucket_checkup |
| IT-EDUCATION | Old | 1961 80E; 2025 mapping pending | education_eligibility_period |
| IT-INTEREST-DEDUCTION | Old | 1961 80TTA/80TTB; 2025 section 153, detailed checks pending | interest_age_eligibility |
| IT-STCG | Both | 1961 111A; 2025 196; eligibility and exemption allocation pending | gains_stcg |
| IT-LTCG | Both | 1961 112A; 2025 198; threshold and exemption allocation pending | gains_ltcg_mixed |
| IT-REBATE | Both separately | 1961 87A / Finance Act 2025 section 20; 2025 156, PDF pp.216–217 | rebate_special_marginal |
| IT-SURCHARGE | Both | Finance Act 2026 schedules/sections; mixed allocation and marginal relief pending | surcharge_mixed_boundaries |
| IT-CESS | Both | Finance Act 2026 section 3(15)/(16), 1961-year charge pending | cess |
| IT-ROUND | Both | 1961 288A/288B pending; 2025 516 PDF p.576 | rounding_paise_components |
| IT-CREDITS | Both | Applicable credit/payable/refund provisions pending | credits_payable_refund |

## Current confirmed observations (not full rule certification)

2025 Act section 202(1) contains the 4/8/12/16/20/24 lakh slab boundaries.
Section 156(2)–(3) has the 12 lakh rebate ceiling, 60000 maximum, marginal relief
and ordinary-rate tax limitation. Section 516 first ignores paise, then rounds
to the nearest ten rupees, with a final rupee digit of five rounding upward.

Notified 2026 Rule 279 expands the 50% HRA city list to Mumbai, Kolkata, Delhi,
Chennai, Hyderabad, Pune, Ahmedabad and Bengaluru, with 40% elsewhere, and uses
the least of actual HRA, rent minus one tenth of relevant-period salary and
the location-based salary percentage. Salary definition and year transition
must be verified alongside the older Rule 2A before implementation.

Subsequent amendments and mixed-income interactions remain a mandatory gate.
No competitor-derived tax constants or silently assumed section mapping allowed.

## Additional inspected provisions

These are observations from the official publications, verified on 2026-10-05;
they are not a certification of complete rule coverage or of later amendments.
PDF page numbers below are one-based physical pages.

| Rule ID | Applicable year/regime | Official provision | Observed rule / effective applicability | Corresponding tests |
| --- | --- | --- | --- | --- |
| IT-SALARY-2026 | Tax Year 2026–27, both | 2025 Act section 19(1), table items 1–2, p.46 | Standard deduction capped at salary: 75000 New, 50000 Old; employment tax paid listed separately; Act commencement 2026-04-01 | NOT_IMPLEMENTED: salary_standard_once |
| IT-NPS-2026 | Tax Year 2026–27, both | 2025 Act section 124(1)–(3), (10), (13), pp.185–187 | Government employer 14%; other employer 10% Old/14% New; own additional 50000; no duplicate section 123 deduction; commencement 2026-04-01 | NOT_IMPLEMENTED: nps_employer_own_caps |
| IT-INVEST-2026 | Tax Year 2026–27, Old | 2025 Act section 123, p.185, Schedule XV | 150000 cap; Schedule XV item-level eligibility review unfinished; commencement 2026-04-01 | NOT_IMPLEMENTED: investment_caps |
| IT-HEALTH-2026 | Tax Year 2026–27, Old | 2025 Act section 126(1)–(11), pp.187–188 | Separate family/parent buckets; 5000 shared preventive-checkup ceiling; noncash except checkup; uninsured-senior conditions; multi-year premium apportionment; commencement 2026-04-01 | NOT_IMPLEMENTED: health_bucket_checkup |
| IT-EDUCATION-2026 | Tax Year 2026–27, Old | 2025 Act section 129, pp.191–192 | Eligible interest paid, initial year plus seven following years or earlier full repayment; commencement 2026-04-01 | NOT_IMPLEMENTED: education_eligibility_period |
| IT-FAMILY-PENSION-2026 | Tax Year 2026–27, both | 2025 Act section 93(1)(d), p.163 | One third of ordinary family pension, capped at 25000 New/15000 Old; commencement 2026-04-01 | NOT_IMPLEMENTED: family_pension |
| IT-DIVIDEND-2026 | Tax Year 2026–27, both | 2025 Act section 93(2), p.164, as substituted by Finance Act 2026 | No expense deduction for dividend income; effective 2026-04-01. Do not reuse the legacy 20% interest-expense rule | NOT_IMPLEMENTED: dividend_year_rules |
| IT-STCG-2026 | Tax Year 2026–27, both | 2025 Act section 196, pp.257–258 | Qualifying STCG 20%; resident shortfall and Chapter VIII restriction; commencement 2026-04-01; combined-gain allocation unresolved | NOT_IMPLEMENTED: gains_stcg |
| IT-LTCG-2026 | Tax Year 2026–27, both | 2025 Act section 198, pp.259–260 | Qualifying LTCG 12.5% above 125000; STT conditions; resident shortfall; Chapter VIII/rebate restrictions; commencement 2026-04-01 | NOT_IMPLEMENTED: gains_ltcg_mixed |
| IT-SURCHARGE-2025 | FY 2025–26, Old | Finance Act 2026 First Schedule Part I-A Paragraph F, pp.82–84 | Bands distinguish income including/excluding dividends and specified gains; component cap 15%; marginal-relief ceiling Wo = Uo + Vo; AY commencement 2026-04-01 | NOT_IMPLEMENTED: surcharge_mixed_boundaries |

The 2025 Act rows link to the [official amended Act](https://www.incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf);
the surcharge row links to the [enacted Finance Act](https://www.incometaxindia.gov.in/documents/d/guest/finance-act-2026-pdf-1).
The effective date here describes the located provision's application, not a
claim to have completed subsequent-amendment review.

## Blocking verification gaps

### B1 — Combined special-rate income and unused basic exemption

Required scope: ordinary income plus both qualifying equity STCG and LTCG,
Old/New, both year packs. The inspected 2025 Act sections 196(2) and 198(3)
each state a resident shortfall adjustment by reference to total income reduced
by that section's gains; section 198(2) also has the separate 125000 threshold.
The corresponding legacy rules are 111A and 112A. I did not establish an
officially supported computation/allocation order for their combined use,
including income-rounding reconciliation. Merely applying a chosen STCG-first
or LTCG-first algorithm would be an unverified material assumption.

Example requiring resolution: New Regime ordinary taxable income 100000,
qualifying STCG 250000, and LTCG 200000 before the annual threshold. There is
no engine or locked expected result for this vector. This is an unresolved
verification gap in this work, not an assertion that enacted law has no answer.

### B2 — Mixed-income surcharge attribution and marginal relief

Required scope: domestic dividends, ordinary income and both gain categories,
especially around 50 lakh, 1 crore, 2 crore and (Old) 5 crore. The enacted
Finance Act verifies rates, component caps and the total-tax ceiling. A
source-supported method is still needed for attributing slab tax to dividends
after deductions/set-offs and constructing the mixed-income counterfactual at
the surcharge cutoff, for each of the two requested income years.

The [official ITR-2 AY 2021–22 instructions](https://www.incometax.gov.in/iec/foportal/sites/default/files/2021-05/Instructions_ITR2_AY2021_22.pdf),
Annexure 5 (physical pp.123–125), contain dividend-priority guidance. They were
inspected only as a lead, not adopted as current-year authority. The downloaded
AY 2026–27 ITR-2 validation rules do not resolve the complete allocation method
in the reviewed text. No same-year independent mixed-income golden has been
locked. Copying the old instructions or a competitor algorithm would not meet
the requested verification gate.

### B3 — Subsequent 2026 amendment could not be inspected

Official Gazette index entry CG-DL-E-17082026-275521 was located during the
subsequent-amendment search. The target is
[Gazette PDF 275521](https://egazette.gov.in/WriteReadData/2026/275521.pdf).
The web reader returned 502/internal errors; direct HTTPS retrieval failed
certificate-chain verification. Alternate www/query URL attempts also failed.
An attempted India Code location timed out and was not verified as the correct
document. Search results describing an August 2026 Taxation and Other Laws
amendment are not sufficient enacted-law evidence. Its effect on this scope
has not been established. Do not declare the Finance-Act-only pack current as
of 2026-10-05 without completing this review.

The 1961 consolidated PDF also could not be fully inspected: direct retrieval
returned 403, the web open failed and the search extract had corrupted text.
An initially probed `section-111a-13` page proved to be the **2016** version
and was rejected as current-year authority. Official domain alone does not
prove correct year/version. Other deduction, set-off and eligibility rows in
the checklist remain unfinished because the research gate stopped here.

## Resumption requirements

Obtain and inspect authoritative current-year evidence resolving B1/B2, and
the enacted subsequent-amendment text for B3. Complete both year-specific rule
registers, effective dates and independent vectors before writing tax code.
No user approval of an assumed formula substitutes for source verification.
No reduced-scope calculator is being delivered in this candidate.

## Resumption on 2026-10-05 — verified evidence and concrete conflict

The original blocked history above is retained. This section supersedes the
earlier statement that Gazette 275521 could not be inspected. It does **not**
certify either complete rule pack. The implementation gate remains blocked by
`B2-MR-112A-50L`, described below; no tax code has been written.

### Evidence provenance and current utility version

The handoff at `/tmp/moneybowl-income-tax-independent-review-20261005/`
was read after the four existing feature documents. Its SHA-256 is
`dd1b51f9df0ac8376dbceb7d0170b2c2af804960e34d719e226850561837665e`.
Every entry in its `evidence.sha256` passed verification. The retained Gazette
PDF and its visible enacted pages were inspected; no insecure TLS retry was
needed. No downloaded macros were executed and no cached workbook value was
accepted as a calculated output.

The [official download index](https://www.incometax.gov.in/iec/foportal/downloads/income-tax-returns)
now lists **ITR-2 AY 2026–27 v1.4, released 13 August 2026**. This differs from
the handoff's v1.3 index observation. Both versions were inspected separately:

| Evidence | SHA-256 | Scope |
| --- | --- | --- |
| Handoff `itr2-2026-v1.3.zip` | `0d465089d81472f2f328420d01c1b80fd108c52e9082a3e2416933a55d749b48` | AY 2026–27 utility; historical version within this review |
| [Official v1.4 ZIP](https://www.incometax.gov.in/iec/foportal/sites/default/files/2026-08/ITR2_AY_26-27_V1.4.zip), 9685572 bytes | `77ad3dcc84f138ac74c1f9f2ed871ee0ca20ba301fc8d8c81d326e2fa3c830f7` | Current version shown by inspected index; FY 2025–26 only |
| Retained Gazette 275521, 519890 bytes | `cfffceb03a2cccd2e19e89c176ecab3056f99913b255e26b0b622c15457c77cd` | Taxation and Other Laws (Amendment) Act 2026, Act 21 of 2026 |

New artifacts remain under `/tmp/moneybowl-income-tax-v1-evidence/`:
`expanded-workbook.json`, `v1.4-active-formulas.json`, static VBA text in
`vba-static/` and `vba-static-v1.4/`, `downloads-index-20261005.html`,
`inspect_v14.py`, `reproduce_b2_conflict.py`, `b2-conflict-vectors.json`, and
`resumption-evidence.sha256`. Extraction expands shared and array formulas.
The v1.4 extractor maps worksheet names through workbook relationships; it
does not reuse v1.3 worksheet numbers. V1.4's Tax Calculated is sheet54.xml,
whereas v1.3's is sheet53.xml. These are research artifacts, not application
dependencies or production tests. No entire Act or utility binary is in Git.

### B1 — active allocation chain located; full legal/rounding gate still open

Static inspection confirms `SPI - SI!U19 → U22 → U38 → U53/W53 → W54 → W57 →
W59 → U60/W60`. In the narrow supported combination, the intervening excluded
gain categories are zero: unused basic exemption is consumed by eligible 20%
STCG, then eligible 12.5% LTCG. `H21/I21` and `H28/P3/I28` are the active tax
outputs. `P3=MIN(125000,H28)` applies the annual threshold after that allocation.
Historical 15%/10% category cells are not the inputs to these outputs.

V1.4 retains this chain; its `G28` source changes from the v1.3 BFLA reference
to `MAX(0,LTCG125_112A)`, with an optional manual SI edit path. That is not a
reason to add an unrestricted override to this calculator. For the no-loss,
no-override synthetic combination in the handoff, the static arithmetic remains
3250 including cess. This remains **utility-derived research arithmetic**, not
a locked two-year statutory golden or an executed official-calculator result.

`Part B - TI TTI!L44` rounds total income; `SPI - SI!U22` subtracts the special
income from that rounded total. The [2025 edition of section 288A](https://www.incometaxindia.gov.in/w/section-288a-59),
[section 288B](https://www.incometaxindia.gov.in/w/section-288b-59), and
[2025 Act section 516, physical p.576](https://incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf)
were inspected: ignore paise first, then round to tens with five upward.
Display rounding and the utility's intermediate whole-rupee ROUND calls do
not establish a statutory requirement to round every component. A complete
component reconciliation, including a potentially negative ordinary residual
when rounded total income is below raw special gains, has not been certified.
Do not hide that residual or allocate the exemption twice.

### B2 — active dependency trace and material conflict B2-MR-112A-50L

The dividend attribution references have been traced beyond worksheet blanks.
`Tax_Calc.bas::calculateTax` writes `OS!T100/OSSW1` from
`Sheet8b.AggregateIncomeNew` (`Part B - TI TTI!O47`) and `OS!T101/osBFLA`
from `othsrcincl.IncOfCurYrAfterSetOffBFLosses5`. `OS!U112/tempBBDA_New`
includes the relevant dividend timing totals and dividend categories.
`V298` restricts the dividend component; `V300` attributes ordinary tax using
`taxAggrIncm / OSSW1 × Surcharge_IncomeEH`. `W300` is an alternative formula,
not the value summed into active `V309`. With no business income `V297=0`.
`U306:U311`, `V306:V309` and `AA306` assemble capped/other income, capped tax,
and the enhanced-surcharge cases. Reading blank cached `OS!T100/T101` as zero
would incorrectly bypass this path.

The VBA bodies of `getSlabbedIncome`, `calculateTaxPayable` and
`calcTaxPayableOnTINTR` were inspected as text. The former separates ordinary
income into the applicable age/regime slab buckets. The 50 lakh calculation
uses those buckets in ascending tax-rate order together with special-rate
income. Cutoff calculations at 1 crore, 2 crore and 5 crore are separate
branches; this investigation does not certify all of them. The historical
`getSlabbedIncomeold`/`calculateTaxPayableold` helpers are not substituted for
the active names. No VBA helper was executed.

**Conflict:** in both v1.3 and v1.4, the active false branch of
`Tax Calculated!I303` is:

```text
H303 + MAX(0, (H304 * 0.125) - LTCG.B1g_ImmpropertyB1e1c)
```

`I302` selects this branch when the 12.5% bucket `I301` is at least the remaining
cutoff income `H304`. The branch lacks the 125000 annual equity-LTCG threshold.
Its property adjustment is `CG!S197` and is zero for the supported equity-only
example. The other branch refers to the actual `SPI - SI!I28` tax, which does
use `P3`; those branches are not interchangeable.

Active propagation is `I303 → J303 → K303 → L303 → M303 → O303 → B307 → E310
→ E311 → G307/G308 → G311 → G314`. The name `Surcharge_ii` resolves to `G314`.
V1.4 `Tax_Calc.bas` lines 705–706 copy it into the return's surcharge field
and compute cess. The affected cutoff/surcharge formulas are identical across
the inspected versions. The v1.4 VBA changes do not replace this path.

**Exact legal comparison:** [1961 Act section 112A(2)(i)(b) and resident proviso](https://www.incometaxindia.gov.in/w/section-112a-60)
provide the 12.5% tax, annual 125000 threshold and resident shortfall adjustment.
[Finance Act 2026](https://incometaxindia.gov.in/documents/d/guest/finance-act-2026-pdf-1)
section 2(5), table row 6 (physical pp.8–9), limits New Regime tax plus surcharge
to tax at the 50 lakh cutoff plus excess income. Old Regime uses First Schedule
Part I-A Paragraph F, Table 2 row 1 (physical p.84). Section 2(6) supplies 4%
cess. Section 288B supplies final payable rounding. Finance Act 2025 section
22's change to the equity-oriented-fund definition does not remove this annual
threshold. Verification date: 2026-10-05; applicability: FY 2025–26/AY 2026–27.

Synthetic resident below 60, **only eligible equity LTCG 5000800**, before the
annual threshold, no other income/deductions/credits:

| Stage, rupees | New | Old |
| --- | --- | --- |
| Basic exemption shortfall | 400000 | 250000 |
| LTCG after basic exemption (`H28`) | 4600800 | 4750800 |
| Annual threshold (`P3`) | 125000 | 125000 |
| Actual income tax (`I28`) | 559475 | 578225 |
| Correct tax at total income 5000000 | 559375 | 578125 |
| Static cutoff formula `I303/B307/E310` | 575000 | 593750 |
| Statutory tax + surcharge ceiling, including excess 800 | 560175 | 578925 |
| Static formula tax + surcharge | 575800 | 594550 |
| Statutory amount after cess and 288B | 582580 | 602080 |
| Static formula amount after cess and 288B | 598830 | 618330 |
| Difference after cess/rounding | **16250** | **16250** |

This disagreement exists **before rounding**: the cutoff tax is higher by
15625 = 125000 × 12.5%. It does not depend on a STCG/LTCG allocation choice,
dividend attribution, losses, paise inputs, rebate, or property income.
`reproduce_b2_conflict.py` independently uses exact Fraction arithmetic,
asserts the inspected formulas agree across versions, and reproduces both
traces. The two checks pass; they demonstrate a conflict, not acceptance of a
tax engine. The statutory calculation must not be changed to match the utility.

The sole-category statutory answer is clear. The **complete mixed-income
counterfactual and relief algorithm remains unverified**: repairing one utility
branch is not independent verification of every cutoff, dividend attribution,
or the separate Tax Year 2026–27 rules. No current authoritative explanation
reconciling this active formula with the statutory ceiling was established.
Under the requested material-discrepancy gate, implementation stops here.

For Tax Year 2026–27, the separately inspected provisions are 2025 Act
section 198(2)–(3) (physical pp.259–260), section 516 (p.576), and Finance Act
2026 section 3(5), table row 6 (p.15). They are not inferred from the AY utility.
**Schedule-reference correction:** section 3(1) charges that tax year under
First Schedule **Part I-B**; the earlier provisional Part III reference is not
the completed rule-pack citation. No TY 2026–27 utility execution or complete
mixed-income golden suite has been verified.

### B3 — retained Gazette reviewed; wider amendment search not certified

[Gazette CG-DL-E-17082026-275521](https://egazette.gov.in/WriteReadData/2026/275521.pdf)
is the Taxation and Other Laws (Amendment) Act 2026, Act 21 of 2026, assented
17 August 2026. Its visible enacted text takes precedence over hidden older
Bill text in extraction. Section 1 generally deems commencement to be 1 April
2026, subject to express exceptions. Reviewed on 2026-10-05:

| Amendment | Effective date / relevance to this scope |
| --- | --- |
| Section 2, Payment and Settlement Systems Act | Publication, 17 August 2026; outside tax estimator |
| Section 3, substituted Schedule I | 1 April 2026; foreign investment funds/managers, excluded |
| Section 4, Schedule IV | Specified foreign/company/institution exemptions; generally 1 April 2026; items 13F/13G and notes 5/6 expressly 1 October 2026; excluded |
| Section 5, Schedule V row 5 column D(b) omission | 1 April 2026; business-trust dividend distributions; ordinary company-dividend input must reject REIT/InvIT/pass-through distributions |
| Section 6, Finance Act 2026 sections 3(4)(b)/3(12)(b) | Domestic-company surcharge categories; no change to individual rate/relief rows in this Act |
| Section 7 | Repeal/savings for Ordinance 2 of 2026 |

Schedule V row 5 in the pre-amendment consolidated 2025 Act (physical p.627)
and section 223 distinguish business-trust distribution treatment. This review
does not add support for such distributions or treat them as ordinary dividends.
The particular Gazette access/scope obstacle is resolved. No change to individual
slabs, resident rebate, sections 196/198 or section 516 was found in this Act.

The dated public search on 2026-10-05 included official-domain queries for
September/October 2026 Income-tax amendments/notifications, Gazette September
Income-tax material, AY 2026–27 marginal relief/112A, and newer ITR-2 releases.
It found the v1.4 utility and public departmental guidance but did not establish
a correction for the conflict. Draft Finance Bills, draft Rules and unrelated
treaty/administrative notices were not used as enacted authority. A complete
subsequent-amendment register remains **unfinished**; search absence, a stale
index or an inaccessible URL is not evidence that no amendment exists.

### Remaining rule-register work at the stop

No row is marked implemented. Existing observations remain research evidence.
`IT-PERIOD`, full `IT-SALARY`/`IT-HRA` legal definitions, `IT-NPS`/`IT-INVEST`
item eligibility, `IT-OTHER`, `IT-PROPERTY` set-offs, `IT-HEALTH`,
`IT-EDUCATION`, `IT-INTEREST-DEDUCTION`, `IT-CREDITS`, and complete year-specific
slab/rebate/surcharge/amendment coverage still need final source binding and
independent fixtures. `IT-ROUND` now has inspected statutory wording for each
Act, but its component reconciliation is still open. B1 has stronger active-
utility evidence, not full two-year legal certification. B2 now has the exact
material counterexample above. The original Normal/Advanced, two-regime,
two-income-year scope has not been reduced or declared complete.

## Component certification register — 2026-10-05

This appendix supersedes the earlier global implementation gate, without erasing
its history. Verification below is bounded to the specified component, not an
assertion of exhaustive amendment coverage. All verification dates: 2026-10-05.
Income-period packs are separate: `in-1961-fy2025-26-v1` (2025-04-01 through
2026-03-31, AY starts 2026-04-01) and `in-2025-ty2026-27-v1` (2026-04-01 through
2027-03-31). Never extrapolate either pack to another year.

Official source keys (page numbers are physical, one-based):

- L25: [1961 provisions, departmental treatment](https://www.incometaxindia.gov.in/w/treatment-of-income-from-different-sources-1), salary section 16 and family pension section 57(iia).
- FA25: [enacted Finance Act 2025](https://incometaxindia.gov.in/Documents/Act/Finance-Act-2025.pdf), sections 20 (87A) and 25 (115BAC), applicable AY 2026–27 from 2026-04-01.
- A26: [2025 Act amended by Finance Act 2026](https://incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf), commencing 2026-04-01.
- F26: [Finance Act 2026](https://incometaxindia.gov.in/documents/d/guest/finance-act-2026-pdf-1), sections 2/3 and First Schedule Parts I-A/I-B, effective 2026-04-01, separately charging AY 2026–27 and TY 2026–27.

| Stable ID | FY 2025–26 binding | TY 2026–27 binding | Resolved component / independent test family |
| --- | --- | --- | --- |
| IT-PERIOD | F26 s2(1), Part I-A A, pp.2/80–81; age at any time in income year | A26 ss1/3; F26 s3(1), Part I-B A, pp.9/84–85; age at any time in tax year | Exact dates, resident ordinary individual confirmation; `period_eligibility` |
| IT-ROUND | [288A](https://www.incometaxindia.gov.in/w/section-288a-59), [288B](https://www.incometaxindia.gov.in/w/section-288b-59) | A26 s516 p.576 | Ignore paise then nearest ten, digit 5 upward; exact BigInt rationals; `rounding_paise_components` |
| IT-SLAB-OLD | F26 Part I-A A(I–III), pp.80–81 | F26 Part I-B A(I–III), pp.84–85 | Age-specific ordinary schedule; `old_slab_boundaries` |
| IT-SLAB-NEW | FA25 s25 / 1961 s115BAC(1A)(iii) | A26 s202(1), pp.264–265 | Seven ordinary bands; `new_slab_boundaries` |
| IT-SALARY-STANDARD | L25 s16(ia), 50000 Old / 75000 New | A26 s19(1) table row2 p.46 | One salary/employment-pension pool; capped to salary; `salary_standard_once` |
| IT-REBATE | 1961 s87A as amended FA25 s20; s112A(6) | A26 s156 pp.216–217, s198(7) | Old 500000/12500 excludes LT tax; New 1200000/60000 and marginal relief limited to ordinary tax; `rebate_special_marginal` |
| IT-SURCHARGE-ORDINARY | F26 s2(4)(b) table10/s2(5) table6, pp.6–9; Part I-A F tables1/2 pp.82–84 | F26 s3(4)(b) table10/s3(5) table6, pp.13–15; Part I-B F tables1/2 pp.86–88 | Sole ordinary category: cutoff composition is necessarily all ordinary. Include prior-band surcharge in cutoff ceiling. `surcharge_ordinary_boundaries` |
| IT-CESS | F26 s2(6), p.9 | F26 s3(15), p.29 | 4% of tax after rebate plus surcharge after relief; `cess` |
| IT-LTCG-SOLE | [112A(2), resident proviso, (5)/(6)](https://www.incometaxindia.gov.in/w/section-112a-60); F26 same surcharge/relief/cess rows above | A26 s198(2)/(3)/(6)/(7), pp.259–260; F26 separate s3/Part I-B bindings above | Sole qualifying gain: rounded total is gain, subtract single resident basic shortfall then annual 125000; 12.5%; no rebate; surcharge capped15%. Cutoff also sole gain and keeps annual threshold. `ltcg_sole_boundaries` |
| IT-FAMILY-PENSION | L25 s57(iia) | A26 s93(1)(d), p.163 | Lesser of one third and 15000 Old/25000 New; separate from employment pension; `family_pension` |
| IT-INTEREST-DEDUCTION | [80TTA/80TTB official guidance](https://www.incometaxindia.gov.in/w/deductions) | A26 s153 pp.215–216 | Old: below60 savings cap10000; resident60+ eligible savings/deposits cap50000. No ordinary other-interest inclusion. `interest_age_eligibility` |

Statutory rounding reconciliation initially admits ordinary-only income and
sole-category gains. For ordinary plus special income, section 111A/112A (or
196/198) defines ordinary as total less gains; any rounding adjustment must be
shown explicitly and cannot make this balance negative. Combined gains with
unused basic exemption and unresolved mixed surcharge remain gated, not guessed.

B2-MR-112A-50L disposition: statute-derived New582580/Old602080 are the acceptance
values for FY2025–26. The retained v1.3/v1.4 formula reproduction remains
598830/618330, status `STATIC_FORMULA_REPRODUCTION`, never
`EXECUTED_OFFICIAL_UTILITY_RESULT`. No hardcoded16250 adjustment and no workbook
patch. Neighboring incomes and the general sole-gain method require tests.
Professional review remains outstanding; no departmental defect confirmation.

### Additional component prerequisites and hand calculations

All rows below verified 2026-10-05, Old only unless specified; FY2025–26 uses
1961 law applicable to AY2026–27, TY2026–27 uses the 2025 Act from 2026-04-01.
These tests are named `deductions`, `hra`, `special_income` and `credits` in the
new income-tax test directory; assertions are transcribed from the following
hand calculations, never obtained from the production engine.

- IT-STCG: [1961 s111A, 2025 edition](https://www.incometaxindia.gov.in/w/section-111a-22) (20% for transfers after 2024-07-23, resident shortfall, restricted Chapter VI-A base); A26 s196 pp.257–258 separately has20%, shortfall, Chapter VIII restriction. Ordinary1100000 + ST100000 gives New ordinary50000 + ST20000 − ordinary rebate50000 =20000; cess800; liability20800. Both gain categories are admitted only when no basic-exemption allocation is needed, and mixed surcharge is separately gated.
- IT-NPS: [1961 s80CCD](https://www.incometaxindia.gov.in/w/section-80ccd-21), A26 s124 pp.185–187 and Schedule XV1(y): employer salary-base1000000, contribution140000 → private Old100000/New140000; government both140000. Own contribution200000: additional50000 first; employee base800000 gives group80000 before combined150000 cap. No sum is allocated twice. Employer contribution is salary exactly once. NPS salary includes qualifying DA, excludes other allowances/perquisites. Pension recipients must explicitly distinguish employee eligibility.
- IT-INVEST: [1961 s80C, 2025 edition](https://www.incometaxindia.gov.in/w/section-80c-60), s80CCE; A26 s123 and Schedule XV1(e)/(f)/(m)/(x)/(y), pp.673–676. EPF80000 + PPF80000 permits150000 combined, before available-income restriction. Instrument-specific conditions are required; other 80C instruments remain pending, not an unrestricted allowance.
- IT-HEALTH: [1961 s80D](https://www.incometaxindia.gov.in/w/section-80d-60), A26 s126 pp.187–188. Family insurance24000, checkup4000; parent insurance24000, checkup4000: each bucket is capped25000, so total allowed is50000, of which only2000 checkup can be used. Allocate shared5000 checkup capacity only after each bucket's remaining capacity is known. Family insurance0, uninsured resident senior medical60000 allows50000; medical spending for an insured person is not eligible. Noncash insurance/medical, checkups may be cash. Multi-year premiums must be apportioned before entry, never counted in full in each year.
- IT-EDUCATION: [1961 s80E guidance](https://www.incometaxindia.gov.in/w/deductions), A26 s129 pp.191–192. Eligible interest50000 in repayment year8 allows50000, year9 allows0. Principal excluded; borrower, beneficiary, lender and payment from taxable income must qualify.
- IT-HRA: [1962 Rule2A](https://www.incometaxindia.gov.in/w/rule-2a-1), L25 s10(13A), Fourth Schedule Part A2(h); A26 ScheduleIII11 and notified2026 Rule279. Relevant-period basic/qualifyingDA600000, HRA300000, rent400000 in Hyderabad: FY25 min(300000,340000,240000)=240000; TY26 min(300000,340000,300000)=300000. Non-overlapping periods are separately evaluated. Commission interpretation for TY26 remains gated pending binding; no unrestricted override.
- IT-CREDITS: [1961 assessment guidance](https://www.incometaxindia.gov.in/w/assessment), ss140A/143(1)(c)/199/219/237; A26 ss266,270(1)(c),390(5),410,516. Optional credit subtraction is an estimate using user-entered eligible same-year amounts, never verification of credit entitlement. Exact liability97500, credits100000 → refund2500; credits95000 → payable2500; credits97500 → zero. Ignore interest/fees/penalties. Round the final balance once from the unrounded liability less credits; do not subtract from an already rounded liability.

The independent `component_goldens.py` retained outside Git created360 fixture
rows before engine implementation (720 year-specific executions), with closed-form
schedule identities and exact Python Fractions. Script SHA256:
`0a0e94c21aab1a98eef09b2a9aab3ab475a3156084ad7161cc2409ff3862be72`.
Fixture SHA256: `771d70c74f51fc93f20c252e14c88f21891b0ebe24e1faa9337db891069c9cee`.

### IT-PROPERTY component — 2026-10-05

Bindings: [1961 s24, 2025 edition](https://www.incometaxindia.gov.in/w/section-24-64),
[s71, 2025 edition](https://www.incometaxindia.gov.in/w/section-71-64), ss23/70/115BAC(2)–(3),
and A26 ss20–22 pp.52–54,108–110 pp.171–172,202(2)–(3) pp.265–266.
Applicable separately to the two supported periods above. GAV is the legally
required annual value, not automatically actual rent; municipal taxes must be
owner-paid in the income period. Let-out NAV=GAV−municipal taxes, deduction30%
NAV, then eligible borrowed-capital interest. Self-occupied cap30000, increased
to200000 only for acquisition/construction completed within five years from
end of borrowing year and with the interest certificate; FY25 additionally
requires capital borrowed on/after1999-04-01. The 2025 Act omits that date test.
New Regime allows no SO interest or inter-head house-property loss set-off.
Old inter-head maximum200000; unabsorbed amount disclosed without carry-forward
management. Intra-head aggregation occurs first.

Independent vectors: GAV300000, municipal20000, interest100000 → NAV280000,
statutory deduction84000, let-out96000 in both regimes. Qualified SO interest
250000 offsets200000 Old, zero New. Combined property head Old−104000/New96000.
Salary1500000 therefore Old TI1346000/NewTI1521000. Let-out interest600000 alone
with that GAV gives loss404000: Old offsets200000 against salary,204000
unabsorbed; New offsets0,404000 disallowed. Mixed loss allocation against
special gains or income supporting interest deductions remains a distinct gate.
Municipal taxes above GAV require a separately verified negative-NAV treatment;
do not clamp to zero or reject as inherently unlawful.

### Bounded amendment review continuation — 2026-10-05

Public searches were bounded to the departmental/Gazette domains using
`2026 marginal relief dividend`, `2026-27 basic exemption 111A 112A`, September
and October2026 income-tax amendments, and the numbered subsequent Rules.
The new official evidence is kept distinct from search leads and utility output.

| Instrument / source searched | Effective date and inspected scope | Disposition |
| --- | --- | --- |
| Retained Gazette275521, reviewed earlier above | Act21 of2026: generally2026-04-01; specified exceptions2026-10-01 | Business-trust distributions remain expressly excluded; review retained |
| [Notification120/2026, GSR822(E),17September2026](https://incometaxindia.gov.in/documents/d/guest/notification-no-120-2026-pdf),5pages | Rules2–4 retrospective2026-04-01; Rules5–8 publication date. References inRule160, electronic communicationsRule176, recoveryRule225, valuer/practitioner registration datesRules246/256 and Forms169/171 | Inspected official text through web PDF reader. No change to implemented individual tax computations. Initial www URL/direct TLS download403; no-www reader succeeded. Do not describe the text as still inaccessible |
| [Notification45/2026](https://www.incometaxindia.gov.in/documents/d/guest/notification-no-45-2026-pdf),30March2026 | Effective31March2026, AY2026–27 return Rule12/forms | Return-form eligibility, not permission to expand V1 property scope |
| [Notification46/2026](https://www.incometaxindia.gov.in/documents/d/guest/notification-no-46-2026-pdf),30March2026 | Effective31March2026, AY2026–27 ITR2 form substitution | Form/utility context, not an independently executed result |
| [Notification47/2026](https://www.incometaxindia.gov.in/documents/d/guest/notification-no-47-2026-pdf),30March2026 | Effective31March2026, AY2026–27 ITR3 substitution | Business return outside V1 |
| Notification97/2026 / GSR656(E),24July2026 | Referenced as preceding amendment in official120/2026 p.5. Secondary discovery describes block-assessment return; official document path retrieval unsuccessful | Scope not certified from a secondary description; retain retrieval gap |
| Notification94/2026 / GSR646(E),21July2026 | Secondary index lead describes Rule157 specified-fund definition; official document path retrieval unsuccessful | Not enacted authority in this register; retain retrieval gap |
| Department notifications index (legacy and replacement paths) | URLs failed in reader; exact instrument review above remained possible | No exhaustive absence-of-amendments claim |

No unchanged ITR workbook was re-downloaded and no downloaded macro was run.
The two utility manifests and original Gazette hashes remain unchanged. Additional
component arithmetic/verification logs reside outside Git in the existing evidence
directory. A full pack-wide subsequent-amendment review remains a release gate.

### Remaining material interaction questions (local calculations gated)

- `IT-GAINS-ALLOCATION`: 111A resident proviso and112A resident proviso, separately
  2025 Act196(2)/198(3), do not by themselves establish the combined order in this
  review. Utility chainU38→U53/W53→U60/W60 uses ST first. Synthetic ordinary100000,
  ST250000,LT200000, New basic400000: that static order produces3125 tax/3250
  with cess; reversing the available-exemption order gives30000 tax/31200 with
  cess. Neither alternative is adopted as a two-year statutory golden. Full
  legal reconciliation remains required, rather than silently choosing priority.
- `IT-SURCHARGE-MIXED`: F26 s2(5)/s3(5) and PartI-A/I-B F Table2 specify a
  cutoff ceiling; a verified rule for constructing mixed cutoff composition is
  still missing. The retained active utility branches include rate-bucket cutoff
  construction and `V294:V300`, `U306:V311`, `AA306`; they must not be replaced by
  a guessed pro-rata allocation. The precise pure-LT conflict and both outcomes
  remain recorded in B2 above. The sole-LT implementation is not certification
  of these mixed branches.
- `IT-DIVIDEND-SURCHARGE`: above2crore, ordinary/dividend tax attribution matters;
  `V300` uses active pro-rata tax attribution while W300 is not the active sum.
  No current two-year enacted/guidance binding for the general attribution
  method was established. REIT/InvIT distributions are not ordinary dividends.
- `IT-ROUND-COMPONENTS`: ordinary0.01 plus LT800003 produces statutory TI800000,
  less raw LT800003 = negative ordinary residual−3. The candidate returns no
  estimate; it neither clips that residual nor silently reduces multiple gains.
- `IT-PROPERTY-LOSS-ALLOCATION`: Old property losses with special gains or
  interest-deduction income need an explicit allocation/eligible-income binding.
  Standalone property plus salary and positive-property combinations work.
- `IT-PROPERTY-NEGATIVE-NAV`: municipality payments above GAV need the signed NAV
  and statutory-deduction interaction resolved; no zero-clamping is implemented.
- `IT-SALARY-LOSS`: professional tax exceeding salary after standard/HRA creates
  a negative head requiring verified set-off treatment; result is withheld.
- `IT-HRA-COMMISSION-2026`: notified Rule279 salary definition and commission
  inclusion require a separate interpretive binding; zero-commission cases use
  the verified period formula and expanded city list.
- `IT-INVEST-INSTRUMENTS`: additional80C instrument-specific guided input coverage
  remains implementation work, distinct from a discovered statutory conflict.

These gates are not scope exclusions or evidence of zero tax. They preserve the
full target while allowing verified independent components to be exercised.

### Further retrieval resolutions and input guards — 2026-10-05

The earlier retrieval entries above describe the state when recorded. Subsequent
bounded follow-up resolved the following documents without changing the utility:

| Official instrument | Reviewed scope / effective date | Current disposition |
| --- | --- | --- |
| [Notification 94/2026, GSR646(E)](https://www.incometaxindia.gov.in/documents/81799/15509036/Notification-94-2026.pdf/56e57deb-a79c-cbf5-7869-59de4a6dc6ab?t=1784702868303), two-page English extract | Rule157(5)(c), specified-fund definition for section262; Category I/II AIFs regulated by SEBI/IFSCA and ScheduleVI Note1(g). Effective Gazette publication, 21July2026 | Official PDF inspected. Earlier retrieval gap resolved; no implemented individual computation changed |
| [Notification 55/2026, GSR241(E)](https://www.incometaxindia.gov.in/documents/d/guest/notification-no-55-2026-1-pdf), one page | Rule128(1)(d)/(2), ChapterXI anti-avoidance application and investments made before1April2017; effective1April2026 | Official text inspected. Does not alter the bounded precomputed-gain rate or individual slab component; complex anti-avoidance arrangements are outside this estimator |
| [Notification 97/2026 official index entry](https://www.incometaxindia.gov.in/hi/w/notification-no.-97/2026-f.-no.-370142/11/2026-tpl-/-gsr-656-e-income-tax-third-amendment-rules-2026) | Department identifies GSR656(E), dated24July2026, third amendment, block-assessment return under section294 | Exact linked PDF discovered; reader cache/access failure and verified-TLS HTTP403. Full instrument/effective-date inspection remains pending; index title is not a substitute for enacted text |

The exact unresolved97 PDF is
`https://www.incometaxindia.gov.in/documents/81799/11848482/Notification-97-2026.pdf/f2eddb88-e8d6-5b8a-7a05-360f538b2c55?t=1784982742217`.
The retrieval log is retained outside Git. This finite search and instrument
review does not establish an exhaustive absence of other amendments.

Two additional declared-input gates prevent superficially complete estimates:

- `IT-INTEREST-EXEMPTION`: post-office savings and other special interest
  exemptions need separate two-year notification/savings-clause verification.
  The generic savings field must not silently tax exempt interest or apply an
  unverified exemption. Declaring such interest returns `TaxNotYetVerified`.
  Ordinary eligible post-office time-deposit interest remains distinct.
- `IT-NPS-MULTIPLE-EMPLOYERS`: this candidate has one employer-specific salary
  base and government/private classification. Multiple employers require separate
  contribution/base inputs and verified limit application. Declaring this case
  returns `TaxNotYetVerified`; no aggregate percentage is guessed. Employer NPS
  plus own NPS also requires employee status, preventing use of the nonemployee
  20%-of-GTI limit in that input combination.

These are pending parts of the original target, not newly certified exclusions.
Both are covered by `income_tax_state_test.dart` tests named
`unverified interest exemptions and separate employer limits fail closed` and
`employer NPS prevents selecting the nonemployee own-NPS percentage`.

### Executable rule-to-test index

The earlier short test-family names are register labels, not literal test names.
All paths below are under `test/calculators/income_tax/`. Both year values are
executed in the domain loop unless an explicitly identified controller or
comparator test concerns only one period. Source/effective-date bindings remain
the rows above; this table supplies exact executable locations.

| Rule IDs / derived trace aliases | Test file and literal family |
| --- | --- |
| IT-PERIOD, IT-SLAB-OLD, IT-SLAB-NEW, IT-SURCHARGE-ORDINARY, IT-CESS, IT-ROUND | `income_tax_engine_test.dart`: `independent golden ordinary_*`; `age bands, family versus employment pension`; `exact arithmetic, paise rounding, India formatting, immutable models` |
| IT-LTCG-SOLE / IT-LTCG, IT-SURCHARGE | Same file: `independent golden ltcg_*`; `B2 static formula reproduction remains separate from statutory acceptance` |
| IT-SALARY-STANDARD, IT-FAMILY-PENSION, IT-REBATE | Same file: `salary acceptance vectors and one standard deduction`; `age bands, family versus employment pension`; `special tax survives new rebate; old ST and LT restrictions differ` |
| IT-STCG | Same file: `special tax survives new rebate; old ST and LT restrictions differ` |
| IT-INVEST, IT-DEDUCTION-LIMIT | Same file: `deductions combined cap and restricted income` |
| IT-NPS | Same file: `NPS included once; employer percentage and own allocations`; state-test employee guard above |
| IT-HEALTH | Same file: `health shared checkup ceiling and uninsured senior medical` |
| IT-EDUCATION, IT-INTEREST-DEDUCTION | Same file: `education year eight/nine and eligible interest categories` |
| IT-CREDITS, IT-LIABILITY | Same file: `credits balance refund and zero`; all golden liability reconciliation assertions |
| IT-HRA, IT-PROPERTY | `income_tax_state_test.dart`: `HRA city period and salary inclusion`; `property limits intra/inter-head and disclosed unabsorbed loss` |
| Pending interaction IDs | Engine test: `unverified dependencies suppress the entire comparison`; state tests above; widget test: `retained advanced entries year invalidation reset and verification status` |

`IT-SALARY` refers to salary inclusion under1961 sections15/17 and2025
sections15–17 (A26 pp.41–45), together with the professional-tax deduction under
1961 section16(iii)/2025 section19(1) table. `IT-OTHER` is an aggregate trace of
ordinary taxable interest/company dividends and family pension under1961
sections56/57 and2025 sections92/93 (A26 pp.159–164); income is gross before TDS.
No dividend expense deduction is supported. `IT-SLAB`, `IT-SURCHARGE`,
`IT-DEDUCTION-LIMIT` and `IT-LIABILITY` are trace aliases/derived stages bound to
the selected pack and component rows, not additional unregistered tax rules.
Application dates are the two income periods in this register. Targeted tests
pass; the full original interaction acceptance matrix is not yet complete.

## Guided-input gate continuation — 2026-10-05

Pre-edit candidate/evidence manifests passed; canonical develop was freshly
fetched and remains clean at the expected base. The following component bindings
and independent expected values precede their implementation. Earlier pending
history is retained; passing safety gates alone is not component completion.

| Gate | Official source and separate year binding | Interpretation / independent expected value | Status before edits |
| --- | --- | --- | --- |
| IT-INVEST-LIFE | [1961 s80C](https://www.incometaxindia.gov.in/w/section-80c-60), (2)(i), (3), (3A), (4)(a), (5); [2025 Act](https://incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf) s123, ScheduleXV1(a),2,4, physicalpp673,676,678 | Self/spouse/child; cap each policy premium separately at20% for issue through2012-03-31,10% thereafter,15% from2013-04-01 with qualifying disability/ailment. Premium25000, assured100000 permits20000/10000/15000 respectively. New Regime disallows. Early-termination recapture must not disappear | Verified for both income periods; tests/implementation next |
| IT-INVEST-TUITION | Same1961 source (2)(xvii)/(4)(c); A26 ScheduleXV1(q),p675 | Full-time education in India, any two children per individual, tuition only; development/donation/transport excluded. Two eligible children40000+30000 →70000 before group/income cap; ineligible child contribution0 | Verified for both periods; tests/implementation next |
| IT-INVEST-HOUSING | Same1961 source (2)(xviii)/(5)(iii); A26 ScheduleXV1(r),3,4 table3,pp675–678 | Named qualifying lender/installment categories; acquisition/construction residential property; principal and transfer charges separate from interest, repairs, membership/share/deposit fees. Principal60000+eligible stamp/registration10000 →70000; private-person lender principal0. Five-year transfer/refund recapture requires separate handling | Verified for both periods; tests/implementation next |
| IT-NPS-MULTIPLE-EMPLOYERS | [1961 s80CCD(2)](https://www.incometaxindia.gov.in/w/section-80ccd-21); A26 s124(1)/(2)/(13)(b),pp185–187 | Apply contribution/base/category per employer, then sum; do not transfer one employer's unused allowance to another. Government90000/base500000 and other50000/base200000 →Old70000+20000=90000; New70000+28000=98000. Each contribution enters gross salary once | Verified for both periods; tests/implementation next |

All rows verified2026-10-05. The1961 bindings apply to FY2025-04-01 through
2026-03-31; A26 bindings apply from2026-04-01 through2027-03-31. Investment sums
share the original150000 group cap and eligible ordinary-income budget. No
financial identity or document upload is required for the guided forms.

Independent combined examples, before production implementation:
salary1500000 and NSC taxable reinvestment interest4000 gives Old salary/head
1450000+4000; with qualifying investment sums above150000, TI1304000,
tax203700, cess8148, rounded211850. New TI1429000, tax94350, cess3774,
rounded98120. For the two-employer example, salary1500000 already includes the
government90000 but excludes the other50000: gross1550000; Old TI1410000,
tax235500, cess9420, liability244920; New TI1377000, tax86550, cess3462,
liability90010. Salary-base and contribution inclusion are independently checked.

### NSC and HRA interpretation completed for bounded branches

`IT-INVEST-NSC`, verified2026-10-05:1961 s80C(2)(ix), notification
S.O.1560(E),2005-11-03, explicitly identified in the department's
[Circular4/2020 paragraph5.5.1(5),physicalp34](https://incometaxindia.gov.in/communications/circular/circular_no_4_2020.pdf).
The current [department deduction guidance](https://www.incometaxindia.gov.in/w/deductions)
separately confirms NSC subscription and reinvested interest, with that interest
taxable under other sources. TY2026 uses s123/ScheduleXV1(i) with s536(2)(j),
which preserves consistent notifications under corresponding provisions.
The official [NSI published Scheme2019](https://www.nsiindia.gov.in/InternalPage.aspx?Id_Pk=167),
GSR919(E),2019-12-12, amended GSR284(E),2020-05-05 effective2020-04-01,
paragraph5(3) deems annual interest through the fourth year reinvested. The
indexed official scheme text was readable; direct NSI retrieval failed TLS
verification (no TLS bypass), and reader requests failed. Subscription/current
accruals are supplied already computed; this calculator does not infer interest
rates from historical scheme tables. NSC principal20000+reinvestment4000 permits
24000 before group cap; final interest4000 adds income but no investment deduction.
An explicit no-duplicate affirmation accompanies automatic interest inclusion.
Senior-citizen NSC-interest attribution under80TTB/153 still needs a separate
binding; that dependent case remains gated, while NSC subscription alone does not.

`IT-HRA-COMMISSION-2026`, verified2026-10-05: retained notified Rule279(2)(b)
includes qualifying DA and excludes other allowances/perquisites. This is the
same operative salary wording as Fourth Schedule PartA2(h), interpreted for
turnover-percentage commission by Gestetner Duplicators117ITR1(SC), reproduced
in the department's [salary booklet section12.3,physicalp83](https://incometaxindia.gov.in/booklets%2520%2520pamphlets/tax-salaried-employees.pdf).
2025 Act16 separately includes commission in salary. The resolved inference is
limited to contractual fixed-percentage-of-turnover remuneration, not an
unrestricted bonus/commission override: the new rule does not exclude that
remuneration as an allowance or perquisite. New city percentages still come
from Rule279 itself. Basic600000+eligible commission100000, HRA400000,
rent600000, Hyderabad gives min(400000,530000,280000)=280000 FY25 and
min(400000,530000,350000)=350000 TY26; New Regime exemption remains0.
NPS statutory salary-base guidance also includes this qualified commission,
consistent with the departmental deductions guidance and identical salary
exclusion wording; bases remain user-entered statutory totals, not gross salary.

### Ordinary-loss and post-office gates — 2026-10-05, before implementation

- `IT-ORDINARY-LOSS`: FY2025 [section71(1),(2),(3A), 2025 edition](https://www.incometaxindia.gov.in/w/section-71-64); TY2026 A26 sections108–109 (physical p171), and section202 restrictions. The [Department loss guide, updated27May2026, p1](https://www.incometaxindia.gov.in/documents/20117/42998/Set-off-and-carry-forward-of-losses_2026-05-27_12-13-23_131dc8_en.pdf/6713bef0-2a75-75f8-a539-2b2aa9a128d7?t=1779945185808&version=2.0) explicitly cites Circular26 dated7July1955 for the most beneficial permissible set-off choice. A26 section536(2)(j) preserves consistent circulars. Salary loss may absorb positive ordinary heads; property loss is restricted to200000 in Old and no inter-head use in New. This interpretation is limited to **no capital gains**: use losses against ordinary income without an interest deduction first, then reduce eligible interest. Because every retained component has the same ordinary tax schedule and this maximises the interest deduction, the choice cannot increase current tax. Salary loss is used before the capped property loss; unabsorbed salary and property losses are separately disclosed, with no future utilisation computed. This does not certify loss allocation involving special-rate gains.
- `IT-INTEREST-EXEMPTION`: [Notification32/2011, S.O.1296(E),3June2011, p1](https://upload.indiacode.nic.in/showfile?actid=AC_CEN_2_2_00039_196143_1524045010860&filename=ita_notification_section_10_notification_no_32_2011_dated_3_6_2011.pdf&type=notification), effective Gazette publication3June2011, replaces GSR607(E) row9. FY2025 section10(15)(i); TY2026 A26 section11, ScheduleII row11 (physical p597), section536(2)(j). The individually held Post Office Savings Bank branch excludes up to3500 before total income and before the Old interest deduction. The notification's7000 joint-account limit is recorded, but attribution among holders still requires verification; joint/multiple-account attribution and other special exemptions remain explicitly pending. No unrestricted exemption override. Both regimes preserve this specific exemption; 115BAC/202 do not remove it.

Independent hand vectors for both years (before changing production engine):

| Input | Old taxable income / liability | New taxable income / liability |
| --- | --- | --- |
| Salary1500000, savings12000, eligible deposit60000, other interest5000, qualified self-property interest200000; below60 |1317000 /215900|1502000 /109510|
| Same, age60–79 |1277000 /200820|1502000 /109510|
| Same, age80+ |1277000 /190420|1502000 /109510|
| Salary0, savings20000, other15000, self-interest20000 |5000 /0|35000 /0|
| Salary1000, professional tax2000, savings100000, other600000, let-out GAV100000, no municipal tax/interest; below60 |758000 /66660|770000 /0|
| Salary1000, professional tax2000, other1000 |0 /0; salary loss used1000, unabsorbed1000|1000 /0|
| Salary1500000, individually held post-office savings13500; below60 |1450000 /257400 (3500 exempt,10000 deducted)|1435000 /99060|

Boundary fixtures will cover exemption3499.99/3500/3500.01 and3504.99/3505/3505.01, loss spill into qualified interest, all ages, both packs and both regimes. Expected values above use enacted slabs,4% cess and final nearest-ten rounding, independently of the Dart engine. These are planned vectors until the corresponding tests pass.

### Pure company-dividend surcharge branch — 2026-10-05, before implementation

`IT-DIVIDEND-SURCHARGE-PURE`: FY2025 Finance Act2026 section2(4)–(6), PartI-A ParagraphF Tables1–2; TY2026 separately section3(4)–(5),(15), PartI-B ParagraphF Tables1–2 (official F26 URL already registered above). Ordinary company dividends remain slab income; the15% surcharge ceiling concerns tax on those dividends. When **all positive ordinary income is company dividends, no head losses are used, and no capital gain is present**, the whole remaining income-tax amount is attributable to dividends even after Chapter deductions. There is no allocation ratio to infer. Apply the ordinary tax schedule, the capped0/10/15% surcharge bands at50/100lakh, same dividend-only composition at those cutoffs, then4% cess and statutory rounding. Enhanced2/5crore cutoffs introduce no surcharge increase for this category. This closes only the pure-dividend branch; attribution mixed with another positive category remains pending.

Independent vectors (no deductions, credits or other income; below60) for both packs: dividends21000000 give Old tax6112500, surcharge916875, cess281175, liability7310550; New tax5880000, surcharge882000, cess270480, liability7032480. At20000000: Old6951750, New6673680. New/Old ordinary-rate rebates remain applicable at their own ceilings. Boundary fixtures will compare every age and regime at4999990/5000000/5000010,9999990/10000000/10000010,19999990/20000000/20000010 and49999990/50000000/50000010 using independent Fraction arithmetic. No mixed-dividend branch is certified by these tests.

### Bounded amendment review closure and remaining legal questions — 2026-10-05

This entry completes this session's **dated, bounded review**, superseding the
retrieval status above. It does not assert that search silence proves the absence
of every later amendment. The inspected inventory comprises the enacted Finance
Acts and consolidated Act already registered, retained Act21/2026 Gazette275521,
notified2026 Rules, Notifications45/46/47,55,94,97,120 and Circular7/2026.

| Source / search | Instrument, effective date, scope and outcome |
| --- | --- |
| Official departmental and e-filing indexes; queries `97/2026 Income-tax notification pdf`, `G.S.R.656(E)2026`, `2026 Fourth Amendment Rules`, September/October2026 income-tax amendments; no unofficial text adopted as enacted authority | Located a different official host for the previously inaccessible97 PDF. Earlier failed retrieval history retained |
| [Notification97/2026, official e-filing PDF](https://www.incometax.gov.in/iec/foportal/sites/default/files/2026-07/Notification-97-2026.pdf),13pages, especially pp1,13 | GSR656(E),24July2026; deemed effective1April2026. Rule332/AppendixIV/FormITR-BN apply to search/requisition under247/248, section294 block returns. No change to this bounded ordinary individual computation. Retrieval gap **RESOLVED**; securely downloaded, no macro execution. PDF SHA256 `e228528d7afcfd9c4217b2269b1dd2824f50d39dc0c889ede99f5398741926c8` |
| [Circular7/2026](https://www.incometax.gov.in/iec/foportal/sites/default/files/2026-09/Circular-7-2026.pdf),28September2026,p1; found through official home-page29September update | AY2026–27 specified audit/return filing deadlines extended to21October/21November2026. Inspected exact text; filing deadlines are outside this estimator, no rate/deduction change |
| Retained Gazette275521 and prior reviewed55/94/120 | Resolutions above remain valid. Act21/2026 business-trust distributions stay explicitly excluded from ordinary company dividends. No repeat utility download |
| Current NSI Scheme2019 page, indexed official description; secure direct retrieval failed certificate verification | No TLS bypass. Instrument/accrual guidance additionally bound to current Department deductions page and official CBDT Circular4/2020, not a private calculator. Senior NSC80TTB/153 classification still pending; absence of a retrieved example is not proof of ineligibility |

The unresolved core interpretations remain **material**, independent of the
explained B2 comparator discrepancy:

- **Combined basic exemption**: the precise statutory provisos and active
  ST-first utility cells, plus the3250 versus31200 illustrative outcomes, remain
  recorded above. Current official general capital-gains guidance does not
  establish a combined order separately for each year. No allocation guessed.
- **Mixed surcharge cutoff composition**: the retained active dependency trace
  remains the evidence. Pure company dividends now have an independently proved
  capped branch; a mixture with other ordinary income above2crore still needs
  attribution, and mixtures with gains above50lakh still need cutoff composition.
- **Negative NAV**: [2025 edition of1961 section23(1) proviso](https://www.incometaxindia.gov.in/w/section-23-64)
  and A26 section21(3),physical p53, deduct owner-paid municipal taxes without an
  express numerical floor; sections24(a)/22(1)(a) set the30% deduction. Static
  ITR2v1.4 `House Property!K24=MAX((K20-I23),0)` and `K59` floor NAV at zero;
  `K25/K60` additionally round ownership NAV and `I26/I61` floor/round the30%
  calculation. Synthetic GAV10000,municipal15000,interest0: static branch NAV0,
  deduction0,head0; signed subtraction NAV−5000 with a non-negative deduction
  would give head−5000, whereas literal signed30% gives head−3500. No such
  alternative is adopted. The narrower validation document's row75 says1a−1d
  without settling this issue. This is **STATIC_FORMULA_INSPECTION**, not an
  executed result or a department-confirmed defect. Negative NAV stays gated.
- **Component rounding**: ordinary0.01+LT800003 still produces rounded TI800000
  below raw LT; clipping ordinary or redistributing gain reductions lacks the
  required verified allocation. No negative ordinary component can escape.
- **Remaining branch eligibility**: senior NSC-interest classification,
  joint/multiple post-office account attribution, other special-interest
  exemptions, additional instruments beyond the named guided set and recapture
  remain pending. They are not silently reclassified as completed exclusions.

### Current rule-to-test closure matrix (local rule-pack revision2)

Both packs remain explicit: `in-1961-fy2025-26-v2` applies only1April2025–31March2026;
`in-2025-ty2026-27-v2` applies only1April2026–31March2027. Revision1 history is
retained above. No future-year fallback. All new bindings verified5October2026.

| Rule ID / gate | Interpretation and independent expected values | Implementation / tests | Status |
| --- | --- | --- | --- |
| IT-INVEST-LIFE |80C(2)(i),(3),(3A),(4); A26 s123,ScheduleXV1(a),2;20/10/15% date and assured-sum tests, family eligibility; effective during respective years |`guided_deductions.dart`, `tax_deductions.dart`; guided test `policy date and beneficiary limits`; both packs, Old caps/New zero |RESOLVED for declared eligible policies; recapture separately gated |
| IT-INVEST-TUITION |80C(2)(xvii),(4)(c);ScheduleXV1(q); two children, full-time India tuition, cap shared;40000+30000 and ineligible-child examples |Guided test `tuition and housing eligibility`; browser controls enter both children and change eligibility |RESOLVED |
| IT-INVEST-HOUSING |80C(2)(xviii);ScheduleXV1(r),3; qualifying lender/purpose, transfer costs, exclusions and shared cap |Guided tests lender/purpose denial, mixed cap; actual housing-category dropdown journey |RESOLVED for declared qualifying current payments; recapture gated |
| IT-INVEST-NSC |80C(2)(ix),notifiedVIII Issue;A26 ScheduleXV1(i),s536(2)(j); subscription/reinvestment in shared cap; interest included once |Guided test `NSC accrual is income once`;cap-exhausted case Old211850/New98120; all-age subscription combinations |RESOLVED for subscription and below60 interest; senior interest PENDING |
| IT-NPS |80CCD(2),A26 s124(1),(2),(13)(b); separate contributions and employer salary bases, government14%,otherOld10%/New14%;70k+20k/28k example |`TaxInput.employers`, engine and per-employer deduction rows; guided all-age tests and actual two-employer journey |RESOLVED for declared ordinary contributions; complex perquisite computation excluded as originally agreed |
| IT-HRA |Rule2A/FourthSchedulePartA2(h); A26 Rule279 plus statutory salary definition and fixed-turnover commission interpretation above |Guided test all9 cities in both packs; browser adds/edits/removes2 periods, Hyderabad vs Delhi; 1135000/1100000 Old TI by year |RESOLVED for bounded contractual turnover commission and non-overlapping periods |
| IT-INTEREST-EXEMPTION |Notification32/2011,10(15)(i),A26 ScheduleII11/536(2)(j);3500 excluded before eligible interest deduction |`income_tax_ordinary_test.dart`: all-age, both-year exemption/paise boundaries; invalid ownership suppresses estimate |RESOLVED one individual account; other branches PENDING |
| IT-ORDINARY-LOSS / IT-PROPERTY |71,108/109,regime restrictions, Circular26; preserve eligible interest via beneficial ordinary-income set-off; independent table above |Ordinary test all ages and loss-spill/salary-loss cases; trace discloses use/unabsorbed/interest allocation |RESOLVED without gains; gain allocation and negative NAV PENDING |
| IT-DIVIDEND-SURCHARGE-PURE |Both enacted schedules separately, whole tax attributable to pure dividend category, cap15%; independent table above |Age fixture has pure-dividend cutoffs at50L/1Cr/2Cr/5Cr, all ages, both packs/regimes |RESOLVED; mixed attribution PENDING |
| IT-SLAB/REBATE/SURCHARGE/STCG/LTCG/ROUND |Existing separate pack bindings above; expanded independent Fraction vectors for all ages and unambiguous combinations |`income_tax_age_goldens_test.dart`, `age_interaction_goldens.json`;645 vectors run in both packs |RESOLVED only the named branches; no gate test counts as implementation |

The expanded fixture generator `continue_goldens.py` is outside Git and imports
no Dart/production engine. The final generator/fixture hashes are recorded in the
continuation evidence manifest. Existing statute-derived B2 fixtures and separate
static-discrepancy assertions are unchanged. Interactive comparisons remain
NOT_RUN: current environment has no browser automation or installed browser;
reader access and formula inspection are not form execution.

### Diagnostic counterexamples for the still-pending mixed branches

These are **alternative-interpretation diagnostics**, not certified tax goldens.
Exact Fraction arithmetic is retained in `continue-unresolved-examples.json`.
For both years the relevant enacted marginal-relief/cap bindings are F26
s2(4)–(6)/s3(4)–(5),(15), respective PartI-A/I-B ParagraphF Tables1–2.

For resident below60, ordinary taxable income3000000 plus eligible STCG2000800,
TI5000800, no deductions/credits, tax is880160 New/1112660 Old. Constructing the
50lakh cutoff by removing800 of ST yields tax-at-cutoff880000/1112500 and rounded
liability916030/1157830. Removing800 of ordinary income instead yields
879920/1112420 and915950/1157750. The active utility's ascending tax-bucket cutoff
helpers, already statically inspected, are not an enacted instruction to adopt
one composition in both years. The exact legal composition question remains;
the engine returns `IT-SURCHARGE-MIXED` for this input, without either number.

For New Regime ordinary non-dividend income21000000 plus company dividends1000000,
TI22000000 and income tax6180000, attribution as active `V300`'s ordinary-tax ratio
allocates3090000/11 to dividend tax, giving surcharge16686000/11 and rounded
liability8004790. Treating dividends as the last ordinary slice attributes300000,
giving surcharge1515000 and liability8002800. Marginal relief is inactive at this
input under either attribution. The current active `V300` formula, not historical
`W300`, explains the first alternative; no statutory/two-year binding selecting
that ratio has been established. The engine returns `IT-DIVIDEND-SURCHARGE`.
This is a separate unresolved interpretation from the pure-dividend branch.

The final input guard also removes any legacy fallback from an employer's missing
salary base to the own-NPS annual salary base. Tests retain the same expected
employer deductions with an explicit employer base, and assert that a missing base
cannot produce a comparison. This strengthens input separation rather than
changing statutory percentage limits.


## IT-REVIEW-001 resolution — 2026-10-05

This is an input-dependency correction, not a new tax allowance. Original history
above is retained. Reviewer evidence is outside Git at
`/tmp/moneybowl-income-tax-own-nps-review-ys70y55w/` (`probe.stdout`,
`own_nps_probe.dart`, `probe.stderr`). Both packs previously interpreted an
omitted own-NPS salary base as zero and returned Old TI1400000/tax241800 for
salary1500000, own contribution200000 and employee status. That complete
comparison was incorrect because the percentage deduction could not be evaluated.

| Rule / period / regime | Official binding, effective date and verification | Interpretation and independent tests |
| --- | --- | --- |
| IT-NPS-BASE-REQUIRED; FY2025–26 / AY2026–27; Old deduction, atomic Old/New comparison | [1961 s80CCD(1)(a), (1B), salary explanation](https://www.incometaxindia.gov.in/w/section-80ccd-21), s80CCE; applicable income period1April2025–31March2026; re-read5October2026 | Employee group deduction requires statutory salary. Additional bucket is independent. `IT-REVIEW-001` domain and actual-form regressions in guided/widgets test files |
| IT-NPS-BASE-REQUIRED; TY2026–27; Old deduction, atomic Old/New comparison | [2025 Act as amended by FA2026](https://www.incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf), s123,124(3)/(5), ScheduleXV1(y), physical pp185–186,676; effective1April2026; re-read5October2026 | Separate legal mapping: own employee percentage is in ScheduleXV, additional deduction in124(3); same required-input dependency, tested separately |

After employer deductions and eligible named instruments consume the ordinary
income and150000 group budgets, allocate up to50000 own contribution to the
additional bucket. If the employee has a positive remaining contribution, group
budget and eligible ordinary income, absence of `npsSalaryBase` returns
`TaxInvalidInput` naming **Own-NPS salary base**. No comparison or winner escapes.
Missing and whitespace controller entries remain absent from the typed amount
map. Explicit0 is a supplied declaration that the defined qualifying salary
components actually total zero; the percentage allowance is then0. It is not a
shortcut for unknown salary. Existing nonnegative/maximum-base validation and
NPS eligibility confirmation still apply. Gross salary and employer bases are
never substitutes. This guard does not demand a base when the additional-only
contribution, exhausted eligible group cap, exhausted ordinary budget or supported
nonemployee calculation makes it irrelevant. An ineligible entered investment
cannot exhaust a budget: this check uses allowed amounts, not entered totals.

Independent arithmetic: salary1500000−standard50000=1450000. Base800000 allows
80000 employee-group contribution plus50000 additional; TI1320000 gives
(12500+100000+96000)×1.04=216840. Explicit0 permits only50000; TI1400000 gives
(12500+100000+120000)×1.04=241800. Nonemployee200000 contribution, or eligible
EPF150000 plus the50000 additional NPS bucket, gives TI1250000/tax195000.
New salary-only liability remains97500. These expected values were derived from
statutory slabs independently; no production engine generated expectations.

Before source correction, newly added tests executed:12 passed,4 failed (missing
base domain and actual-form tests, each year). After correction the initial16
passed. Two additional reverse employer-to-own fallback regressions supplement
this coverage; existing employer-base regressions were not modified. Full final
validation is recorded in the validation document. No legal allocation gate was
closed by these input-validation tests.

## Scoped V1 investment source gate — 2026-10-05, before code

The [release contract](INCOME_TAX_CALCULATOR_V1_RELEASE_SCOPE.md) replaces the
historic requirement to implement every pending branch before a local commit.
Historical register entries above remain evidence. The historic
`IT-INVEST-POST5` row incorrectly cited 1961 section 80C(2)(xxv): the actual
five-year Post Office Time Deposit is **80C(2)(xxiv)**; (xxv) addresses a Central
Government employee's specified pension account. The 2025 Act location is
Schedule XV paragraph 1(v), not a numbered 80C analogue. The corrected citations
below govern the new implementation.

| ID / years / Old only | Enacted provision, official scheme evidence and effective date | Bounded interpretation, independent numbers and required test |
| --- | --- | --- |
| IT-INVEST-BANK5; FY2025–26 | [1961 80C(1),(2)(xxi)](https://www.incometaxindia.gov.in/w/section-80c-60); [CBDT Notification 63/2014, S.O.2906(E)](https://incometaxindia.gov.in/Communications/Notification/Notification63_2014.pdf), effective Gazette publication13Nov2014, names Bank Term Deposit Scheme2006, S.O.1220(E)28July2006, and changes scheme ceiling to150000; [Department deductions guidance](https://www.incometaxindia.gov.in/w/deductions), refreshed5Oct2026 | Only a current-year amount in a named Bank Term Deposit Scheme2006 tax-saving deposit with a scheduled bank and at least five-year lock-in. No ordinary FD. First/single-holder status must be asserted; this V1 accepts single-held deposits. Paid100000 gives Old226200/New97500 on salary1500000; combined EPF100000 caps Old at210600 |
| IT-INVEST-BANK5; TY2026–27 | [2025 Act s123/Schedule XV1(s)](https://incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf), physical pp185,675; effective1Apr2026; same notified Bank scheme continuing via [s536(2)(j)](https://incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf); Department guidance above | Separate pack; same bounded single-holder inputs, numbers and tests; no year rollover |
| IT-INVEST-POST5; FY2025–26 | [1961 80C(2)(xxiv)](https://www.incometaxindia.gov.in/w/section-80c-60); [G.S.R.922(E), National Savings Time Deposit Scheme2019](https://www.nsiindia.gov.in/writereaddata/SchemeRules/TimeDepositSchemeRule.pdf), effective Gazette publication12Dec2019, amended G.S.R.289(E)5May2020; [NSI current scheme summary](https://www.nsiindia.gov.in/InternalPage.aspx?Id_Pk=58) | Only the five-year category in the notified scheme, single-held by claimant and deposited in the period; 1/2/3-year, recurring and monthly-income accounts rejected. Department guidance treats current five-year Post Office TD as80C qualifying; the statute retains the predecessor1981 rule name. Paid100000 fixture as above; interest is taxable separately as eligible deposit interest, never another contribution |
| IT-INVEST-POST5; TY2026–27 | [2025 Act s123/Schedule XV1(v)](https://incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf), p675, effective1Apr2026; notified2019 scheme, NSI and Department current guidance above | Separate pack and same narrow single-holder five-year account; retain predecessor-name/current-scheme interpretive chain for independent review |
| IT-INVEST-SCSS; FY2025–26 | [1961 80C(2)(xxiii),(6A)](https://www.incometaxindia.gov.in/w/section-80c-60); [G.S.R.916(E), SCSS2019](https://www.nsiindia.gov.in/writereaddata/SchemeRules/SeniorCitizensSavingsSchemeRule.pdf), effective12Dec2019, amended G.S.R.287(E)5May2020 and G.S.R.240(E)31Mar2023 increasing scheme deposit ceiling to3000000; [NSI current scheme](https://www.nsiindia.gov.in/InternalPage.aspx?Id_Pk=168), [Department guidance](https://www.incometaxindia.gov.in/w/deductions) | V1 accepts current-year opening deposit in single-held account when claimant was at least60 at opening, under3000000 aggregate scheme ceiling. The account age must be confirmed separately from year-end tax age. Early-retiree/defence and joint attribution are deferred with no estimate. Paid100000 fixture as above; current SCSS interest goes in deposit-interest field |
| IT-INVEST-SCSS; TY2026–27 | [2025 Act s123/Schedule XV1(u)](https://incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf), p675, effective1Apr2026; notified SCSS2019, current NSI and Department guidance above | Same bounded age-at-opening/account conditions and separate pack; source still names2004 predecessor, recorded as current-scheme continuity interpretation rather than mechanical1:1 mapping |
| IT-INVEST-SUKANYA; FY2025–26 | [1961 80C(2)(viii)](https://www.incometaxindia.gov.in/w/section-80c-60); [CBDT Notification9/2015 S.O.210(E)](https://www.nsiindia.gov.in/writereaddata/FileUploads/SSA_80c_GZT.pdf), effective Gazette publication21Jan2015; [G.S.R.914(E), Sukanya2019](https://www.nsiindia.gov.in/writereaddata/SchemeRules/SukanyaSamriddhiAccountSchemeRule.pdf), effective12Dec2019, amended G.S.R.288(E)5May2020 | Own paid contributions into one or two different girl-child accounts; claimant confirms own daughter/legal guardianship, account opened before age10, deposit within first15 years, no duplicate claim and no special multiple-birth exception. Scheme maximum150000 per account per FY; reject excess rather than silently cap. No interest input inferred. Paid100000 fixture as above; two distinct25000+25000 allow50000 before group cap |
| IT-INVEST-SUKANYA; TY2026–27 | [2025 Act s123/Schedule XV1(h)](https://incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf), pp185,674, effective1Apr2026; Gazette notification9/2015 continued subject to s536(2)(j) and notified2019 scheme above | Separate pack, same bounded two distinct accounts and fixtures; do not move the contribution to an interest field |

The scheme PDFs were discoverable in official search indexes but NSI direct PDF
reader requests returned intermittent502/timeout; the official NSI text/summary,
Gazette index extracts, current Department guidance and enacted provisions were
reviewed without TLS bypass. This retrieval limit and predecessor-scheme wording
are retained for independent review. A new contrary enacted instrument would
block the corresponding V1 row. Figures above come from the existing Old/New
salary fixture: Old salary1500000−50000 standard−100000 eligible investment
=1350000; ordinary Old tax217500 plus4% cess=226200. New salary taxable1425000,
New tax97500. EPF100000 plus investment100000 is limited to the shared150000;
Old taxable1300000, tax210600. Invalid account/age/lock-in/beneficiary
conditions must return typed no-comparison, never a zero-eligibility success.

Independent senior-age correction for the SCSS vector: with salary1500000 and
contribution100000, Old gross salary less50000 standard less100000 deduction
=1350000; age60–79 ordinary tax is10000+100000+105000=215000, cess8600,
liability223600. The below60 figure226200 above does not apply to SCSS's
60-at-opening V1 branch. This correction was recorded before tax-engine edits.

## Bounded amendment refresh for the release contract — 2026-10-05

This is a dated, scoped check, **not** a claim that search silence proves no
other amendment exists. Inspected the official [Income-tax Department Act and
FAQ index](https://www.incometaxindia.gov.in/), [2025 Act as amended by Finance
Act 2026](https://incometaxindia.gov.in/documents/d/guest/income_tax_act_2025_as_amended_by_fa_act_2026-pdf),
[1961 section 80C](https://www.incometaxindia.gov.in/w/section-80c-60),
[Department deduction guide](https://www.incometaxindia.gov.in/w/deductions),
and National Savings Institute's published scheme pages for time deposits,
SCSS and Sukanya. Searched those official domains and eGazette for later
notifications mentioning s123/Schedule XV and the four required schemes.

The [Income-tax (Amendment) Ordinance, 2026, No.2 of 2026](https://www.legislative.gov.in/static/uploads/2026/05/61eb3f0307259c025404ddeaa563b08e.pdf),
published 5 June 2026 and deemed effective 1 April 2026, inserts Schedule IV
Table items 13D/13E for government-security interest/gains of foreign
institutional investors and the Bank for International Settlements. These are
outside the resident-individual V1 scope; it does not change Schedule XV,
ordinary salary or supported equity gains. This is enacted ordinance text,
not a proposal or calculator output.

The [National Savings Time Deposit (Fourth Amendment) Scheme, 2023,
G.S.R.830(E)](https://egazette.gov.in/WriteReadData/2023/249981.pdf),
published 7 November 2023, replaces paragraph 8 on premature closure. It does
not change the five-year account category or current opening-deposit minimum.
V1 excludes early closure and routes declared recapture to no estimate. The
Gazette PDF timed out during direct open on 5 October 2026, while the official
indexed Gazette text exposed its heading, commencement and paragraph-8
replacement; that retrieval limitation remains visible for independent review.
The NSI consolidated PDF still labels amendments only through G.S.R.289(E)
(2020), so it must not be mistaken for a complete amendment history.

For Sukanya eligibility, the [CBDT Circular 19/2015](https://incometaxindia.gov.in/communications/circular/circularno19-2015.pdf)
confirms the claimant must be the girl's parent or legal guardian; the [NSI
scheme text](https://www.nsiindia.gov.in/writereaddata/SchemeRules/SukanyaSamriddhiAccountSchemeRule.pdf)
and [Government Savings Promotion General Rules](https://www.nsiindia.gov.in/writereaddata/FileUploads/genralruleEnglish.pdf)
provide the account residence/citizenship conditions. V1 asks the user to
confirm these facts for each beneficiary. It does not infer them from the
taxpayer's current-year ROR status.

The dated bank-scheme cross-check also used the [Reserve Bank of India master
circular](https://www.rbi.org.in/scripts/BS_ViewMasterCirculars.aspx?Id=6512),
which identifies Government Notification203/2006/Bank Term Deposit Scheme2006,
and [Bank of Maharashtra's deposit policy, Annexure A item12](https://bankofmaharashtra.in/writereaddata/documentlibrary/0b19d3b0-1a38-4f3a-8e2c-5d071bce4911.pdf),
which separately distinguishes that scheme from ordinary fixed deposits,
listing a ₹100 minimum, ₹1.5 lakh financial-year ceiling, five-year minimum
and no loan facility. These are official regulator/operator materials, not a
substitute for the Government notification; CBDT Notification63/2014 and the
enacted s80C/Schedule XV remain the tax authority. The original S.O.1220(E)
full Gazette was not retrieved directly; V1 asks for the named scheme and a
single-held ₹100-multiple contribution, a narrower accepted input subset.

The 1961 s80C and 2025 Schedule XV clauses still use predecessor names for
the 2004 SCSS and 1981 Post Office Time Deposit rules. [G.S.R.912(E),
12 December 2019](https://www.nsiindia.gov.in/writereaddata/SchemeRules/RescindNotification.pdf)
rescinded those rules while preserving prior rights; [G.S.R.916(E)](https://www.nsiindia.gov.in/writereaddata/SchemeRules/SeniorCitizensSavingsSchemeRule.pdf)
and [G.S.R.922(E)](https://www.nsiindia.gov.in/writereaddata/SchemeRules/TimeDepositSchemeRule.pdf)
created the current schemes. The [National Savings Institute's current scheme
guide](https://www.nsiindia.gov.in/InternalPage.aspx?Id_Pk=27) expressly says
that deposits in present SCSS and five-year Time Deposit qualify under 80C.
For TY2026, s123/Schedule XV repeat the qualifying categories and s536(2)(j)
preserves notified instruments; this is the bounded continuity interpretation
applied in V1, with the stale predecessor wording visible for professional
review. No inference is made that every post-office scheme or every SCSS
account circumstance qualifies. A contrary enacted clarification would
require a versioned rule change and renewed independent tests.

The retained seven-page Gazette and evidence hashes in
`/tmp/moneybowl-income-tax-independent-review-20261005/` cover the earlier
Schedule V/business-trust distribution review; REIT/InvIT/pass-through
distributions remain excluded, never reclassified as ordinary company
dividends. Other previously recorded dated searches and retrieval failures
above remain unchanged. Interactive official and commercial calculators were
not used as legal sources.

### Revision3 implementation-to-test closure for the four V1 investments

Both explicit rule packs now report `in-1961-fy2025-26-v3` and
`in-2025-ty2026-27-v3`. The enacted/year-specific source rows above bind the
same **supported input subset** independently for each year; the engine does
not infer a third year. `tax_deductions.dart` adds named decisions after
instrument-level validation in `income_tax_engine.dart`. The shared Old group
budget is applied once, limited to eligible ordinary income; the New group
allowance is zero. The five decision rows are BANK5, POST5, SCSS and Sukanya
child1/child2, with entered/allowed/disallowed reasons in the trace.

| Rule ID | Independent acceptance input and result in each year | Test boundary and outcome |
| --- | --- | --- |
| IT-INVEST-BANK5 | Salary1500000, single-held paid100000: below60 Old226200/New97500; add EPF100000: Old210600/New97500 | `income_tax_guided_test.dart`: amount99/101/150100 invalid, missing scheme or exclusivity invalid; ordinary deposit interest10000 remains taxable Old229320/New99060; no eligible income gives allowed0, not invented tax |
| IT-INVEST-POST5 | Same100000 salary fixture Old226200/New97500 | Guided test: amount999/1050 invalid; only declared single-held five-year opening account, not one/three-year product; separate deposit interest |
| IT-INVEST-SCSS | Salary1500000, age60–79, current opening paid100000: Old223600/New97500 | Guided test: amount999/3001000 invalid; below60 exception `TaxNotYetVerified` and both estimates withheld; age-at-opening confirmed separately |
| IT-INVEST-SUKANYA | Salary1500000, own paid100000: below60 Old226200/New97500; two distinct child accounts25000+25000 share the group budget | Guided test: amount249/275/150050 invalid; second child requires first plus distinct-beneficiary confirmation; interest not merged into contribution |

`income_tax_widgets_test.dart` enters all four via actual controls for both
years, checks year reconfirmation, editing and Reset. Existing age/gain golden
files were not regenerated by the production engine. Ineligible or declared
out-of-scope scheme circumstances withhold the comparison; a typed no-estimate
assertion documents boundary enforcement, not a computed deduction.
