# Income Tax Calculator V1 release contract

Decision date: 2026-10-05. This contract supersedes the earlier rule that all
37 entries in the [historical acceptance register](INCOME_TAX_CALCULATOR_V1_IMPLEMENTATION_PLAN.md#finite-remaining-acceptance-register--2026-10-05-reviewer-continuation)
be implemented before a local feature commit. It preserves that register and its
research history. A deferral below is an explicit product boundary, never a tax
conclusion or permission to show a partial comparison.

V1 remains one local, pure Dart engine comparing Old/New regimes for resident and
ordinarily resident individuals in FY 2025–26 / AY 2026–27 under the 1961 Act and
Tax Year 2026–27 under the 2025 Act. Both Normal and Advanced use separate,
explicitly versioned year packs. A combination is supported only when both
regimes' income, deductions, set-offs, special-rate tax, surcharge, relief,
rounding and credits can be completed and reconciled. One unresolved dependency
withholds the entire comparison, winner and balance. No year fallback is allowed.

Normal covers gross salary or employment pension, eligible ordinary interest and
guided common deductions. Advanced adds bounded HRA, employer NPS, family pension,
company dividends, one self-occupied and one let-out property, eligible equity
STCG/LTCG, and credits. Support for these categories is limited to the executable
predicates and accepted combinations in the current source and test matrix;
category labels do not imply every combination is supported. Current verified
branches and existing mathematical coverage must be preserved.

The four named current-year investments below are required before release.
Contributions are distinct from interest. Amounts are eligible only with the
scheme, ownership, payment-year and beneficiary facts required by enacted law and
notifications. The single ₹1,50,000 Old-Regime group budget and eligible ordinary
income limit apply. Early closure/recapture and disputed ownership withhold a
comparison. Source and tests, rather than this scope statement, determine the
actual eligible amount.

| Acceptance ID | Release status | Bounded V1 meaning |
| --- | --- | --- |
| IT-INVEST-BANK5 | REQUIRED_FOR_V1 | Current-year single-held qualifying five-year bank tax-saving deposit, guided; joint/pledged/recapture cases unavailable |
| IT-INVEST-POST5 | REQUIRED_FOR_V1 | Current-year single-held five-year Post Office Time Deposit, guided; shorter terms and early closure unavailable |
| IT-INVEST-SCSS | REQUIRED_FOR_V1 | Current-year single-held Senior Citizens Savings Scheme opening deposit for claimant at least60 on opening date; below60 retirement/defence exception unavailable |
| IT-INVEST-SUKANYA | REQUIRED_FOR_V1 | Current-year own Sukanya Samriddhi contributions to one or two distinct eligible girl-child accounts, guided; interest and special multiple-birth exception unavailable |
| IT-GAINS-ALLOCATION | DEFERRED_VERIFICATION | Both eligible gain types with unused basic exemption |
| IT-SURCHARGE-MIXED | DEFERRED_VERIFICATION | Mixed special-rate surcharge cutoff composition |
| IT-DIVIDEND-SURCHARGE | DEFERRED_VERIFICATION | Mixed dividend tax attribution at enhanced bands |
| IT-PROPERTY-LOSS-ALLOCATION | DEFERRED_VERIFICATION | Current property loss plus special gains |
| IT-SALARY-LOSS | DEFERRED_VERIFICATION | Salary-head loss plus special gains |
| IT-ROUND-COMPONENTS | DEFERRED_VERIFICATION | Rounding that makes ordinary residual negative |
| IT-PROPERTY-NEGATIVE-NAV | DEFERRED_VERIFICATION | Paid municipal taxes exceed gross annual value |
| IT-NSC-SENIOR-INTEREST | DEFERRED_VERIFICATION | NSC interest with age at least 60 |
| IT-POS-JOINT | DEFERRED_VERIFICATION | Joint Post Office Savings ownership/attribution |
| IT-POS-MULTIPLE | DEFERRED_VERIFICATION | Multiple Post Office Savings accounts/limits |
| IT-INTEREST-PPF | DEFERRED_FEATURE | Explicit exempt-interest entry and reconciliation |
| IT-INTEREST-SUKANYA | DEFERRED_FEATURE | Explicit exempt-interest entry and reconciliation |
| IT-INTEREST-TAXFREE-BOND | DEFERRED_VERIFICATION | Issue-specific notification and exemption |
| IT-INTEREST-PF-EXCESS | DEFERRED_VERIFICATION | Taxable/non-taxable PF account interest split |
| IT-INVEST-SUPERANNUATION | DEFERRED_FEATURE | Employee approved-superannuation contribution |
| IT-INVEST-STATUTORY-PF | DEFERRED_FEATURE | Provident Funds Act 1925 contribution |
| IT-INVEST-DEFERRED-ANNUITY | DEFERRED_FEATURE | Qualifying deferred annuity contracts |
| IT-INVEST-NOTIFIED-ANNUITY | DEFERRED_VERIFICATION | Named notified annuity plans |
| IT-INVEST-ULIP | DEFERRED_VERIFICATION | Legacy/notified unit-linked schemes |
| IT-INVEST-NOTIFIED-PENSION | DEFERRED_VERIFICATION | Notified mutual-fund/NHB pension scheme |
| IT-INVEST-HOUSING-DEPOSIT | DEFERRED_VERIFICATION | Notified housing-body deposit |
| IT-INVEST-NABARD | DEFERRED_VERIFICATION | Notified NABARD bond issue |
| IT-INVEST-NPS-TIER2 | DEFERRED_VERIFICATION | Central-government employee Tier-II scheme |
| IT-INVEST-LEGACY-SHARES | DEFERRED_VERIFICATION | Qualifying historic share/debenture scheme |
| IT-RECAPTURE-LIFE | DEFERRED_FEATURE | Past life-policy deduction recapture |
| IT-RECAPTURE-HOUSING | DEFERRED_FEATURE | Past housing deduction recapture |
| IT-RECAPTURE-MARKET | DEFERRED_FEATURE | Past share/fund/ULIP/Tier-II recapture |
| IT-RECAPTURE-DEPOSIT | DEFERRED_FEATURE | Past deposit deduction recapture |
| IT-ACCEPT-JOURNEYS | REQUIRED_FOR_V1 | Actual V1 form journeys and deferred-case boundaries |
| IT-ACCEPT-MATRIX | REQUIRED_FOR_V1 | Independent supported and blocked matrix for bounded scope |
| IT-ACCEPT-AMENDMENTS | REQUIRED_FOR_V1 | Dated, bounded official-source refresh |
| IT-ACCEPT-LOCAL | REQUIRED_FOR_V1 | Frozen local validation and exact commit scope |
| IT-ACCEPT-COMPARATORS | POST_IMPLEMENTATION_RELEASE_GATE | Honest interactive comparison status; not a local commit gate |

Existing accepted branches have status **SUPPORTED_V1**, including IT-PERIOD,
IT-SLAB-OLD, IT-SLAB-NEW, IT-REBATE, IT-SURCHARGE-ORDINARY, IT-CESS,
IT-ROUND for nonnegative component reconciliation, IT-SALARY, IT-HRA,
IT-NPS, IT-INVEST, IT-INVEST-LIFE, IT-INVEST-TUITION, IT-INVEST-HOUSING,
IT-INVEST-NSC for qualifying contributions/below-60 accrued interest,
IT-HEALTH, IT-EDUCATION, IT-INTEREST-DEDUCTION, IT-INTEREST-EXEMPTION
for one individual savings account, IT-PROPERTY and IT-ORDINARY-LOSS
without gains/negative NAV, IT-OTHER for ordinary supported income,
IT-STCG and IT-LTCG for verified sole/ordinary mixes, IT-DIVIDEND-SURCHARGE-PURE,
and IT-CREDITS. Their exact preconditions are in the
[rules register](INCOME_TAX_CALCULATOR_V1_RULES_AND_SOURCES.md#current-rule-to-test-closure-matrix-local-rule-pack-revision2)
and engine tests. The status does not override a named deferred interaction.

A newly found defect in a SUPPORTED_V1 or REQUIRED_FOR_V1 result has status
**RELEASE_BLOCKER** until fixed and retested. The known B2-MR-112A-50L static
utility discrepancy is explained, with separate statute-derived acceptance tests;
it is not itself a blocker or proof of executed utility behavior. A new unexplained
conflict in a supported case is a blocker.

Original exclusions remain: NRI/RNOR, nonindividual entities, business/AMT,
foreign income/treaties, agricultural integration, capital-loss management,
crypto/lottery/gaming, complex property/retirement/perquisites, business-trust
pass-through distributions, return filing and penalties. Unsupported/deferred
circumstances must be declared or inferred and produce no complete estimate.

Independent tax-professional signoff, interactive external comparison where
available, independent review and controlled hosted DEV commissioning are
**POST_IMPLEMENTATION_RELEASE_GATE** activities. A successful local commit is
not merge approval, public financial-use approval or Production readiness.
