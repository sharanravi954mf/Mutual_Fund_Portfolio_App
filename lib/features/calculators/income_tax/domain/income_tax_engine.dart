import '../models/tax_input.dart';
import '../models/tax_result.dart';
import 'exact_amount.dart';
import 'house_property.dart';
import 'special_income.dart';
import 'tax_deductions.dart';
import 'tax_exemptions.dart';
import 'tax_rules.dart';

/// One deterministic, local engine for both modes. A comparison is atomic:
/// neither regime escapes if either calculation has an unresolved dependency.
final class IncomeTaxEngine {
  const IncomeTaxEngine();
  TaxOutcome calculate(TaxInput input) {
    try {
      return _calculate(input);
    } catch (_) {
      // Fail closed. Financial entries and exception details are never logged.
      return const TaxCalculationFailure();
    }
  }

  TaxOutcome _calculate(TaxInput input) {
    if (input.unsupported.isNotEmpty) return TaxUnsupported(input.unsupported);
    if (input.age != TaxAge.below60 &&
        (input.amount(TaxAmountField.nscReinvestedInterest) +
                input.amount(TaxAmountField.nscFinalInterest))
            .isPositive) {
      return TaxNotYetVerified({
        'IT-NSC-SENIOR-INTEREST':
            'NSC interest classification for the senior deposit deduction requires verification.'
      });
    }
    if (input.age == TaxAge.below60 &&
        input.amount(TaxAmountField.scssDeposit).isPositive) {
      return TaxNotYetVerified({
        'IT-INVEST-SCSS-EARLY-RETIREMENT':
            'A current-year SCSS deposit before age 60 needs the separate early-retirement/defence scheme conditions. This combination is not supported in V1. No tax comparison has been calculated.'
      });
    }
    if (input.pending.isNotEmpty) {
      return TaxNotYetVerified({
        if (input.pending.contains(PendingTaxFeature.additional80cInstruments))
          'IT-INVEST-INSTRUMENTS':
              'Guided eligibility and fixtures for additional 80C instruments are not yet implemented.',
        if (input.pending
            .contains(PendingTaxFeature.postOfficeSavingsExemption))
          'IT-INTEREST-EXEMPTION':
              'Post-office savings or other special interest exemptions need separate two-year verification before a full estimate.',
        if (input.pending.contains(PendingTaxFeature.multipleEmployerNps))
          'IT-NPS-MULTIPLE-EMPLOYERS':
              'Employer-specific contributions and salary bases need separate inputs and verification; aggregate limits are not substituted.',
        if (input.pending.contains(PendingTaxFeature.deductionRecapture))
          'IT-DEDUCTION-RECAPTURE':
              'Early termination, housing transfer/refund or another reversal requires previous-deduction recapture; not yet verified.',
      });
    }
    final issues = _validate(input);
    if (issues.isNotEmpty) return TaxInvalidInput(issues);
    final gates = <String, String>{};
    if (input.amount(TaxAmountField.municipalTax) >
        input.amount(TaxAmountField.grossAnnualValue)) {
      gates['IT-PROPERTY-NEGATIVE-NAV'] =
          'Municipal taxes exceed GAV; negative-NAV treatment still requires verification.';
    }
    if (gates.isNotEmpty) return TaxNotYetVerified(gates);
    final old = _regime(input, TaxRegime.old, gates, issues);
    final newer = _regime(input, TaxRegime.newRegime, gates, issues);
    if (issues.isNotEmpty) return TaxInvalidInput(issues);
    if (gates.isNotEmpty) return TaxNotYetVerified(gates);
    return TaxComparison(oldRegime: old!, newRegime: newer!);
  }

  List<String> _validate(TaxInput input) {
    final errors = <String>[];
    void require(TaxConfirmation flag, String message) {
      if (!input.confirmed(flag)) errors.add(message);
    }

    require(TaxConfirmation.residentOrdinarilyResidentIndividual,
        'Confirm resident and ordinarily resident individual eligibility.');
    require(TaxConfirmation.scopeChecklistReviewed,
        'Review and confirm the supported-scope checklist.');
    require(TaxConfirmation.ageForSelectedYear,
        'Confirm your age band for the selected income period.');
    for (final entry in input.amounts.entries) {
      if (entry.value.isNegative ||
          entry.value > Exact.parse('999999999999.99') ||
          (entry.value.numerator * BigInt.from(100)) %
                  entry.value.denominator !=
              BigInt.zero) {
        errors.add(
            '${entry.key.name}: use a non-negative amount up to 12 rupee digits and 2 paise digits.');
      }
    }
    Exact a(TaxAmountField f) => input.amount(f);
    bool any(List<TaxAmountField> fields) => fields.any((f) => a(f).isPositive);
    if (a(TaxAmountField.salary).isPositive) {
      require(TaxConfirmation.salaryDefinition,
          'Confirm gross salary includes employment pension and taxable perquisites, before supported exemptions and standard deduction.');
    }
    if (any([TaxAmountField.savingsInterest, TaxAmountField.depositInterest])) {
      require(TaxConfirmation.depositEligibility,
          'Confirm eligible bank, co-operative bank or post-office interest held in your own capacity.');
    }
    if (a(TaxAmountField.postOfficeSavingsInterest).isPositive) {
      require(TaxConfirmation.individualPostOfficeAccount,
          'Confirm one individually held Post Office Savings Bank account, without joint ownership, clubbing or duplicate interest.');
    }
    if (any([
          TaxAmountField.epf,
          TaxAmountField.ppf,
          TaxAmountField.elss,
          TaxAmountField.annuity80ccc
        ]) ||
        input.lifePremiums.isNotEmpty ||
        any([
          TaxAmountField.tuitionChildOne,
          TaxAmountField.tuitionChildTwo,
          TaxAmountField.housingPrincipal,
          TaxAmountField.housingTransferCharges,
          TaxAmountField.nscSubscription,
          TaxAmountField.nscReinvestedInterest,
          TaxAmountField.bankFiveYearDeposit,
          TaxAmountField.postFiveYearDeposit,
          TaxAmountField.scssDeposit,
          TaxAmountField.sukanyaChildOne,
          TaxAmountField.sukanyaChildTwo
        ])) {
      require(TaxConfirmation.investmentEligibility,
          'Confirm each selected investment and annual contribution meets its statutory conditions.');
    }
    final guidedDeposits = [
      TaxAmountField.bankFiveYearDeposit,
      TaxAmountField.postFiveYearDeposit,
      TaxAmountField.scssDeposit,
      TaxAmountField.sukanyaChildOne,
      TaxAmountField.sukanyaChildTwo,
    ];
    if (guidedDeposits.any((field) => a(field).isPositive)) {
      require(TaxConfirmation.investmentAmountsExclusive,
          'Confirm each new investment contribution is paid in this year and entered once only, with no amount also in EPF, PPF, ELSS, annuity, NSC or another scheme.');
    }
    for (final (field, flag, label) in [
      (
        TaxAmountField.bankFiveYearDeposit,
        TaxConfirmation.bankFiveYearEligible,
        'Five-year bank tax-saving deposit'
      ),
      (
        TaxAmountField.postFiveYearDeposit,
        TaxConfirmation.postFiveYearEligible,
        'Five-year Post Office Time Deposit'
      ),
      (
        TaxAmountField.scssDeposit,
        TaxConfirmation.scssEligibleAtOpening,
        'SCSS opening deposit'
      ),
      (
        TaxAmountField.sukanyaChildOne,
        TaxConfirmation.sukanyaChildOneEligible,
        'Sukanya child 1 deposit'
      ),
      (
        TaxAmountField.sukanyaChildTwo,
        TaxConfirmation.sukanyaChildTwoEligible,
        'Sukanya child 2 deposit'
      ),
    ]) {
      if (a(field).isPositive) {
        require(flag,
            '$label: confirm the named scheme, current-year payment, account ownership and guided eligibility facts.');
      }
    }
    bool multipleOf(TaxAmountField field, int rupees) =>
        (a(field).numerator * BigInt.one) %
            (a(field).denominator * BigInt.from(rupees)) ==
        BigInt.zero;
    if (a(TaxAmountField.bankFiveYearDeposit).isPositive &&
        (a(TaxAmountField.bankFiveYearDeposit) > Exact.rupees(150000) ||
            a(TaxAmountField.bankFiveYearDeposit) < Exact.rupees(100) ||
            !multipleOf(TaxAmountField.bankFiveYearDeposit, 100))) {
      errors.add(
          'Five-year bank tax-saving deposit: enter an eligible current-year scheme amount from ₹100 to ₹1,50,000 in ₹100 multiples.');
    }
    if (a(TaxAmountField.postFiveYearDeposit).isPositive &&
        (a(TaxAmountField.postFiveYearDeposit) < Exact.rupees(1000) ||
            !multipleOf(TaxAmountField.postFiveYearDeposit, 100))) {
      errors.add(
          'Five-year Post Office Time Deposit: enter a current-year account opening deposit of at least ₹1,000 in ₹100 multiples.');
    }
    if (a(TaxAmountField.scssDeposit).isPositive &&
        (a(TaxAmountField.scssDeposit) < Exact.rupees(1000) ||
            a(TaxAmountField.scssDeposit) > Exact.rupees(3000000) ||
            !multipleOf(TaxAmountField.scssDeposit, 1000))) {
      errors.add(
          'SCSS opening deposit: enter an eligible current-year amount of ₹1,000–₹30,00,000 in ₹1,000 multiples, within your aggregate scheme ceiling.');
    }
    for (final field in [
      TaxAmountField.sukanyaChildOne,
      TaxAmountField.sukanyaChildTwo
    ]) {
      if (a(field).isPositive &&
          (a(field) < Exact.rupees(250) ||
              a(field) > Exact.rupees(150000) ||
              !multipleOf(field, 50))) {
        errors.add(
            '${field == TaxAmountField.sukanyaChildOne ? 'Sukanya child 1' : 'Sukanya child 2'}: enter current-year account deposits of ₹250–₹1,50,000 in ₹50 multiples.');
      }
    }
    if (a(TaxAmountField.sukanyaChildTwo).isPositive) {
      if (!a(TaxAmountField.sukanyaChildOne).isPositive) {
        errors.add(
            'Sukanya child 2 requires a separately entered child 1 account; use child 1 for a single beneficiary.');
      }
      require(TaxConfirmation.sukanyaDistinctChildren,
          'Sukanya child 2: confirm these are two different eligible girl-child accounts and no child or amount is repeated.');
    }
    if (a(TaxAmountField.ownNpsTotal).isPositive ||
        input.employers.isNotEmpty) {
      require(TaxConfirmation.npsEligibility,
          'Confirm own Tier-I NPS contributions and the statutory salary base; exclude minor accounts and withdrawals.');
    }
    if (input.employers.isNotEmpty) {
      require(TaxConfirmation.taxablePerquisitesIncluded,
          'Include already-computed taxable excess-contribution perquisites/accretions in gross salary.');
      if (!a(TaxAmountField.salary).isPositive) {
        errors.add('Employer NPS requires gross employment salary.');
      }
      if (input.confirmed(TaxConfirmation.employerNpsAlreadyInSalary) &&
          a(TaxAmountField.employerNps) > a(TaxAmountField.salary)) {
        errors
            .add('Employer NPS included in salary cannot exceed gross salary.');
      }
    }
    if (input.employers.isNotEmpty &&
        a(TaxAmountField.ownNpsTotal).isPositive &&
        !input.confirmed(TaxConfirmation.npsEmployee)) {
      errors.add(
          'Own NPS with employer NPS requires employee status for the 10% group limit.');
    }
    if (a(TaxAmountField.npsSalaryBase) > a(TaxAmountField.salary)) {
      errors
          .add('Statutory NPS salary base cannot exceed entered gross salary.');
    }
    bool valid(Exact v) =>
        !v.isNegative &&
        v <= Exact.parse('999999999999.99') &&
        (v.numerator * BigInt.from(100)) % v.denominator == BigInt.zero;
    final lastDay =
        DateTime.utc(input.year == TaxYear.fy2025 ? 2026 : 2027, 3, 31);
    for (final policy in input.lifePremiums) {
      if (!valid(policy.paid) ||
          !valid(policy.assured) ||
          (policy.paid.isPositive && !policy.assured.isPositive) ||
          policy.issued.isAfter(lastDay)) {
        errors.add(
            'Life policy: check rupees/paise, positive actual sum assured and issue date within or before the selected year.');
      }
    }
    var includedNps = Exact.zero, employerBases = Exact.zero;
    for (final employer in input.employers) {
      if (!valid(employer.contribution) ||
          !valid(employer.salaryBase) ||
          (employer.contribution.isPositive &&
              !employer.salaryBase.isPositive)) {
        errors.add(
            'Each employer needs a valid contribution and positive statutory salary base.');
      }
      employerBases += employer.salaryBase;
      if (employer.alreadyInGrossSalary) includedNps += employer.contribution;
    }
    if (employerBases + includedNps > a(TaxAmountField.salary)) {
      errors.add(
          'Distinct employer salary bases plus NPS already included cannot exceed annual gross salary; do not repeat another employer’s base.');
    }
    if (any([
      TaxAmountField.familyInsurance,
      TaxAmountField.familyCheckup,
      TaxAmountField.familyMedical,
      TaxAmountField.parentInsurance,
      TaxAmountField.parentCheckup,
      TaxAmountField.parentMedical
    ])) {
      require(TaxConfirmation.healthEligiblePayments,
          'Confirm health payment, relationship, residence, insurance and annual premium conditions.');
    }
    if (any([
      TaxAmountField.nscSubscription,
      TaxAmountField.nscReinvestedInterest,
      TaxAmountField.nscFinalInterest
    ])) {
      require(TaxConfirmation.nscEligibility,
          'Confirm NSC VIII Issue eligibility, accrued/reinvested amounts and no duplicate interest entry.');
    }
    if (a(TaxAmountField.educationInterest).isPositive) {
      require(TaxConfirmation.educationEligible,
          'Confirm qualifying borrower, beneficiary, lender and education-loan interest payment.');
      if (input.educationRepaymentYear < 1) {
        errors.add('Education repayment year must start at 1.');
      }
    }
    if (a(TaxAmountField.equityStcg).isPositive) {
      require(TaxConfirmation.equityStcgEligible,
          'Confirm statutory/STT eligibility for already-computed non-negative equity STCG.');
    }
    if (a(TaxAmountField.equityLtcg).isPositive) {
      require(TaxConfirmation.equityLtcgEligible,
          'Confirm statutory/STT eligibility for equity LTCG before the annual ₹1.25 lakh threshold.');
    }
    if (a(TaxAmountField.dividends).isPositive) {
      require(TaxConfirmation.ordinaryCompanyDividends,
          'Confirm ordinary domestic company dividends; exclude REIT/InvIT/pass-through distributions and expense claims.');
    }
    if (any([
      TaxAmountField.selfOccupiedInterest,
      TaxAmountField.grossAnnualValue,
      TaxAmountField.municipalTax,
      TaxAmountField.letOutInterest
    ])) {
      require(TaxConfirmation.completedFullyOwnedProperties,
          'Confirm at most one completed fully owned self-occupied and one let-out property; no unsupported property facts.');
    }
    if (any([
      TaxAmountField.grossAnnualValue,
      TaxAmountField.municipalTax,
      TaxAmountField.letOutInterest
    ])) {
      require(TaxConfirmation.annualValueVerified,
          'Confirm legally determined gross annual value and owner-paid municipal taxes.');
    }
    final sorted = [...input.hraPeriods]
      ..sort((a, b) => a.firstDay.compareTo(b.firstDay));
    var previousEnd = 0;
    var hraSalaryIncluded = Exact.zero;
    for (final p in sorted) {
      if (p.firstDay < 1 ||
          p.lastDay > 365 ||
          p.firstDay > p.lastDay ||
          p.firstDay <= previousEnd) {
        errors.add(
            'HRA periods must be within the selected income year and non-overlapping.');
      }
      previousEnd = p.lastDay;
      for (final v in [
        p.basic,
        p.eligibleDa,
        p.turnoverCommission,
        p.actualHra,
        p.rent
      ]) {
        if (v.isNegative ||
            v > Exact.parse('999999999999.99') ||
            (v.numerator * BigInt.from(100)) % v.denominator != BigInt.zero) {
          errors
              .add('HRA amounts must be valid non-negative rupees and paise.');
        }
      }
      hraSalaryIncluded +=
          p.basic + p.eligibleDa + p.turnoverCommission + p.actualHra;
    }
    if (hraSalaryIncluded > a(TaxAmountField.salary)) {
      errors.add(
          'Period salary components and HRA must already be included in annual gross salary.');
    }
    return errors;
  }

  RegimeEstimate? _regime(TaxInput input, TaxRegime regime,
      Map<String, String> gates, List<String> issues) {
    final pack = TaxRulePack.forYear(input.year);
    final trace = <TaxAuditEntry>[];
    final decisions = <DeductionDecision>[];
    final old = regime == TaxRegime.old;
    Exact a(TaxAmountField f) => input.amount(f);
    void record(TaxStage stage, String id, String label, Exact amount,
            String reason) =>
        trace.add(TaxAuditEntry(stage, id, label, amount, reason));
    final salary = a(TaxAmountField.salary) +
        input.employers.fold(
            Exact.zero,
            (sum, employer) =>
                sum +
                (employer.alreadyInGrossSalary
                    ? Exact.zero
                    : employer.contribution));
    final hra = input.hraPeriods
        .fold(Exact.zero, (sum, p) => sum + TaxExemptions.hra(p, input.year));
    final exempt = old ? hra : Exact.zero;
    final standard = (salary - exempt).positive.min(pack.standard(regime));
    final professional = old ? a(TaxAmountField.professionalTax) : Exact.zero;
    final salaryHead = salary - exempt - standard - professional;
    if (salaryHead.isNegative &&
        (a(TaxAmountField.equityStcg) + a(TaxAmountField.equityLtcg))
            .isPositive) {
      gates['IT-SALARY-LOSS'] =
          'Salary-head loss allocation involving capital gains still requires verification.';
      return null;
    }
    record(
        TaxStage.incomeHeads,
        'IT-SALARY',
        'Gross salary including employer NPS once',
        salary,
        'Gross employment pension is part of the same salary pool.');
    record(TaxStage.exemptions, 'IT-HRA', 'HRA exemption', exempt,
        'Period calculations; HRA is already in gross salary.');
    decisions.add(DeductionDecision(
        'IT-HRA',
        'HRA',
        hra,
        exempt,
        old
            ? 'Minimum-of-three helper per period'
            : 'Not allowed in New Regime'));
    decisions.add(DeductionDecision(
        'IT-SALARY-STANDARD',
        'Standard deduction',
        pack.standard(regime),
        standard,
        'Once across salary and employment pension, limited to eligible salary'));
    decisions.add(DeductionDecision(
        'IT-SALARY',
        'Professional tax',
        a(TaxAmountField.professionalTax),
        professional,
        old ? 'Actually paid employment tax' : 'Not allowed in New Regime'));
    record(
        TaxStage.exemptions,
        'IT-SALARY-STANDARD',
        'Salary standard deduction',
        standard,
        'Salary-head deduction, not a second Chapter deduction.');
    final family = a(TaxAmountField.familyPension);
    final familyDeduction =
        family.ratio(1, 3).min(Exact.rupees(old ? 15000 : 25000));
    decisions.add(DeductionDecision(
        'IT-FAMILY-PENSION',
        'Family pension deduction',
        family,
        familyDeduction,
        'Lesser of one third and regime cap; not salary standard deduction'));
    final postOfficeExempt =
        a(TaxAmountField.postOfficeSavingsInterest).min(Exact.rupees(3500));
    record(
        TaxStage.exemptions,
        'IT-INTEREST-EXEMPTION',
        'Post-office savings exemption',
        postOfficeExempt,
        'One individually held account; applied before interest deduction.');
    decisions.add(DeductionDecision(
        'IT-INTEREST-EXEMPTION',
        'Post-office savings exemption',
        a(TaxAmountField.postOfficeSavingsInterest),
        postOfficeExempt,
        'Individual account cap ₹3,500, both regimes'));
    final other = a(TaxAmountField.savingsInterest) +
        a(TaxAmountField.postOfficeSavingsInterest) -
        postOfficeExempt +
        a(TaxAmountField.depositInterest) +
        a(TaxAmountField.otherInterest) +
        a(TaxAmountField.nscReinvestedInterest) +
        a(TaxAmountField.nscFinalInterest) +
        a(TaxAmountField.dividends) +
        family -
        familyDeduction;
    record(
        TaxStage.incomeHeads,
        'IT-OTHER',
        'Other sources after family-pension deduction',
        other,
        'Gross before TDS; separate from salary.');
    // Property may be positive while salary is negative. Compute its raw head
    // independently, then apply unrestricted salary loss before capped HP loss.
    final rawProperty = houseProperty(input, regime, Exact.zero);
    final salaryLoss = (-salaryHead).positive;
    final salaryLossUsed = salaryLoss.min(other + rawProperty.head.positive);
    final available = salaryHead.positive + other - salaryLossUsed;
    final property = houseProperty(input, regime, available.positive);
    if (property.head.isNegative &&
        old &&
        [
          TaxAmountField.equityStcg,
          TaxAmountField.equityLtcg,
        ].any((f) => a(f).isPositive)) {
      gates['IT-PROPERTY-LOSS-ALLOCATION'] =
          'House-property loss allocation involving capital gains remains unverified.';
      return null;
    }
    decisions.addAll(property.decisions);
    record(
        TaxStage.incomeHeads,
        'IT-PROPERTY',
        'Let-out net annual value',
        property.netAnnualValue,
        'GAV less eligible municipal taxes actually paid.');
    record(TaxStage.exemptions, 'IT-PROPERTY', 'Let-out statutory deduction',
        property.statutoryDeduction, '30% of NAV.');
    record(
        TaxStage.incomeHeads,
        'IT-PROPERTY',
        'House-property head after intra-head set-off',
        property.head,
        'Let-out result less eligible self-occupied interest.');
    record(
        TaxStage.setOffs,
        'IT-PROPERTY',
        'House-property inter-head loss used',
        property.interHeadUsed,
        old
            ? 'Up to ₹2 lakh and available other income.'
            : 'Not allowed in New Regime.');
    record(
        TaxStage.setOffs,
        'IT-PROPERTY',
        'House-property loss unabsorbed / disallowed',
        property.unabsorbed,
        old
            ? 'Potential carry-forward not managed by this calculator.'
            : 'No current inter-head set-off or future deduction under this regime.');
    record(
        TaxStage.setOffs,
        'IT-ORDINARY-LOSS',
        'Salary-head loss used',
        salaryLossUsed,
        'Against positive ordinary heads before capped property loss.');
    record(TaxStage.setOffs, 'IT-ORDINARY-LOSS', 'Salary-head loss unabsorbed',
        salaryLoss - salaryLossUsed, 'No future loss utilisation computed.');
    final positiveOrdinary =
        salaryHead.positive + other + property.head.positive;
    final totalLossUsed = salaryLossUsed + property.interHeadUsed;
    final grossOrdinary = positiveOrdinary - totalLossUsed;
    final eligibleInterest = a(TaxAmountField.savingsInterest) +
        a(TaxAmountField.postOfficeSavingsInterest) -
        postOfficeExempt +
        (input.age == TaxAge.below60
            ? Exact.zero
            : a(TaxAmountField.depositInterest));
    final interestLoss =
        (totalLossUsed - (positiveOrdinary - eligibleInterest)).positive;
    final interestAfterSetOff = (eligibleInterest - interestLoss).positive;
    record(
        TaxStage.setOffs,
        'IT-ORDINARY-LOSS',
        'Loss allocated to eligible interest',
        interestLoss,
        'Ordinary income without an interest deduction absorbs loss first; preserves the most beneficial permitted deduction.');
    final rawStcg = a(TaxAmountField.equityStcg);
    final rawLtcg = a(TaxAmountField.equityLtcg);
    record(TaxStage.incomeHeads, 'IT-STCG', 'Eligible equity STCG entered',
        rawStcg, 'Gains, not sale proceeds.');
    record(TaxStage.incomeHeads, 'IT-LTCG', 'Eligible equity LTCG entered',
        rawLtcg, 'Before the annual threshold; retained in total income.');
    final chapter = TaxDeductions.compute(
        input, regime, grossOrdinary, grossOrdinary + rawStcg + rawLtcg,
        interestAfterSetOff: interestAfterSetOff);
    if (chapter.issues.isNotEmpty) {
      issues.addAll(chapter.issues);
      return null;
    }
    decisions.addAll(chapter.decisions);
    final deducted =
        chapter.decisions.fold(Exact.zero, (sum, row) => sum + row.allowed);
    record(
        TaxStage.deductions,
        'IT-DEDUCTION-LIMIT',
        'Chapter deductions allowed',
        deducted,
        'Cannot absorb eligible special-rate gains.');
    final beforeRounding = grossOrdinary - deducted;
    final rawTotal = beforeRounding + rawStcg + rawLtcg;
    final total = rawTotal.statutoryTen();
    final adjustment = total - rawTotal;
    var ordinary = beforeRounding + adjustment;
    var stcg = rawStcg;
    var ltcg = rawLtcg;
    if (beforeRounding.isZero && (rawStcg.isPositive != rawLtcg.isPositive)) {
      ordinary = Exact.zero;
      if (rawStcg.isPositive) {
        stcg = total;
      } else {
        ltcg = total;
      }
    }
    if (ordinary.isNegative) {
      gates['IT-ROUND-COMPONENTS'] =
          'Rounded total is below the special-income components; a non-negative statutory reconciliation remains unverified.';
      return null;
    }
    if (stcg.isPositive &&
        ltcg.isPositive &&
        ordinary < pack.basic(regime, input.age)) {
      gates['IT-GAINS-ALLOCATION'] =
          'Both gain categories need unused basic exemption: year-specific allocation remains unverified.';
      return null;
    }
    if (total > Exact.rupees(5000000) &&
        (stcg + ltcg).isPositive &&
        (ordinary.isPositive || (stcg.isPositive && ltcg.isPositive))) {
      gates['IT-SURCHARGE-MIXED'] =
          'Mixed-income cutoff composition and component-specific surcharge relief remain unverified.';
      return null;
    }
    final soleDividend = a(TaxAmountField.dividends).isPositive &&
        positiveOrdinary == a(TaxAmountField.dividends) &&
        totalLossUsed.isZero &&
        (stcg + ltcg).isZero;
    if (total > Exact.rupees(20000000) &&
        a(TaxAmountField.dividends).isPositive &&
        !soleDividend) {
      gates['IT-DIVIDEND-SURCHARGE'] =
          'Dividend tax attribution at enhanced surcharge bands remains unverified.';
      return null;
    }
    record(
        TaxStage.totalIncome,
        'IT-ROUND',
        'Total-income rounding adjustment',
        adjustment,
        beforeRounding.isZero && (stcg + ltcg).isPositive
            ? 'Applied to the sole gain category; ordinary stays zero.'
            : 'Applied to ordinary residual = statutory total less special gains.');
    record(TaxStage.totalIncome, 'IT-ROUND', 'Statutory total income', total,
        pack.roundingReference);
    final special =
        specialIncomeTax(pack, regime, input.age, ordinary, stcg, ltcg);
    final tax = special.total;
    record(
        TaxStage.incomeTax,
        'IT-STCG',
        'Basic exemption used against gains',
        special.basicUsed,
        'Allocated at most once; unresolved combined allocation is gated.');
    record(
        TaxStage.incomeTax,
        'IT-LTCG',
        'LTCG annual threshold used',
        special.annualThresholdUsed,
        'Reduces gain tax base, not statutory total income.');
    record(TaxStage.incomeTax, 'IT-SLAB', 'Ordinary income tax',
        special.ordinaryTax, pack.slabReference);
    record(TaxStage.incomeTax, 'IT-STCG', 'Equity STCG tax', special.stcgTax,
        '20% after permitted shortfall.');
    record(TaxStage.incomeTax, 'IT-LTCG', 'Equity LTCG tax', special.ltcgTax,
        '12.5% after shortfall and annual threshold.');
    var rebate = Exact.zero;
    var rebateRelief = Exact.zero;
    if (old && total <= Exact.rupees(500000)) {
      rebate = (special.ordinaryTax + special.stcgTax).min(Exact.rupees(12500));
    } else if (!old && total <= Exact.rupees(1200000)) {
      rebate = special.ordinaryTax.min(Exact.rupees(60000));
    } else if (!old) {
      rebateRelief = (tax - (total - Exact.rupees(1200000)))
          .positive
          .min(special.ordinaryTax);
    }
    record(TaxStage.rebate, 'IT-REBATE', 'Resident rebate', rebate,
        'Separate Old/New eligibility; LTCG tax never rebated.');
    record(TaxStage.rebateRelief, 'IT-REBATE', 'Rebate marginal relief',
        rebateRelief, 'New Regime; limited to ordinary-rate tax.');
    final afterRebate = tax - rebate - rebateRelief;
    final soleGain = ordinary.isZero && (stcg + ltcg).isPositive;
    Exact taxAt(Exact cutoff) => soleGain
        ? specialIncomeTax(
                pack,
                regime,
                input.age,
                Exact.zero,
                stcg.isPositive ? cutoff : Exact.zero,
                ltcg.isPositive ? cutoff : Exact.zero)
            .total
        : pack.ordinaryTax(cutoff, regime, input.age);
    final sur = homogeneousSurcharge(total, afterRebate, regime,
        cappedCategory: soleGain || soleDividend, taxAt: taxAt);
    record(
        TaxStage.surcharge,
        'IT-SURCHARGE',
        'Surcharge before marginal relief',
        sur.amount + sur.relief,
        pack.surchargeReference);
    record(
        TaxStage.surchargeRelief,
        'IT-SURCHARGE',
        'Surcharge marginal relief',
        sur.relief,
        'Same sole income category at cutoff; retain all its tax thresholds and prior-band surcharge.');
    final cess = (afterRebate + sur.amount).ratio(4, 100);
    record(TaxStage.cess, 'IT-CESS', 'Health and Education Cess', cess,
        '4% after surcharge relief.');
    final exactLiability = afterRebate + sur.amount + cess;
    final liability = exactLiability.statutoryTen();
    record(TaxStage.liability, 'IT-ROUND', 'Liability rounding adjustment',
        liability - exactLiability, pack.roundingReference);
    record(
        TaxStage.liability,
        'IT-LIABILITY',
        'Estimated liability before credits',
        liability,
        'Not a filing computation of interest, fees or penalties.');
    final credits = [
      TaxAmountField.tds,
      TaxAmountField.tcs,
      TaxAmountField.advanceTax,
      TaxAmountField.selfAssessmentTax
    ].fold(Exact.zero, (sum, f) => sum + a(f));
    final exactBalance = exactLiability - credits;
    final balance = exactBalance.statutoryTen();
    record(TaxStage.credits, 'IT-CREDITS', 'Entered credits', credits,
        'Same-year eligible tax only; no Form 26AS/AIS validation.');
    record(
        TaxStage.balance,
        'IT-ROUND',
        'Balance rounding adjustment',
        balance - exactBalance,
        'Round exact liability less credits; do not round intermediates.');
    record(
        TaxStage.balance,
        'IT-CREDITS',
        'Estimated balance (negative means refund)',
        balance,
        'Subject to actual eligible credits and excluded charges.');
    final orderedTrace = trace.indexed.toList()
      ..sort((a, b) {
        final stage = a.$2.stage.index.compareTo(b.$2.stage.index);
        return stage == 0 ? a.$1.compareTo(b.$1) : stage;
      });
    return RegimeEstimate(
        regime: regime,
        ruleVersion: pack.version,
        totalIncome: total,
        ordinaryIncome: ordinary,
        stcg: stcg,
        ltcg: ltcg,
        incomeTax: tax,
        rebate: rebate,
        rebateRelief: rebateRelief,
        surcharge: sur.amount,
        surchargeRelief: sur.relief,
        cess: cess,
        exactLiability: exactLiability,
        liability: liability,
        credits: credits,
        balance: balance,
        trace: orderedTrace.map((entry) => entry.$2),
        deductions: decisions);
  }
}
