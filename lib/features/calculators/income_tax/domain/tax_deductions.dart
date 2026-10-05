import '../models/tax_input.dart';
import '../models/tax_result.dart';
import '../models/guided_deductions.dart';
import 'exact_amount.dart';

/// Deduction budgets exclude prohibited special-rate gains. No mutable result
/// escapes this computation. Ordering is disclosed and cannot enlarge a cap.
final class TaxDeductions {
  static ({List<DeductionDecision> decisions, List<String> issues}) compute(
      TaxInput input,
      TaxRegime regime,
      Exact ordinaryAvailable,
      Exact grossTotalIncome,
      {Exact? interestAfterSetOff}) {
    final decisions = <DeductionDecision>[];
    var available = ordinaryAvailable.positive;
    final old = regime == TaxRegime.old;
    Exact a(TaxAmountField field) => input.amount(field);
    Exact allow(
        String rule, String label, Exact entered, Exact eligible, String reason,
        {bool both = false}) {
      final permitted =
          (old || both) ? eligible.min(available).positive : Exact.zero;
      available -= permitted;
      decisions.add(DeductionDecision(
          rule,
          label,
          entered,
          permitted,
          old || both
              ? '$reason; limited to remaining eligible ordinary income.'
              : 'Not allowed in New Regime.'));
      return permitted;
    }

    for (final (index, employer) in input.employers.indexed) {
      final employerPercent = !old || employer.government ? 14 : 10;
      allow(
          'IT-NPS',
          index == 0 ? 'Employer NPS' : 'Employer NPS ${index + 1}',
          employer.contribution,
          employer.contribution
              .min(employer.salaryBase.ratio(employerPercent, 100)),
          '$employerPercent% of statutory salary base; outside the investment cap',
          both: true);
    }

    var groupLeft = Exact.rupees(150000);
    for (final field in [
      TaxAmountField.epf,
      TaxAmountField.ppf,
      TaxAmountField.elss,
      TaxAmountField.annuity80ccc
    ]) {
      final used = allow('IT-INVEST', field.name, a(field),
          a(field).min(groupLeft), 'Shared ₹1,50,000 investment/NPS group cap');
      groupLeft -= used;
    }
    void investment(
        String id, String label, Exact paid, Exact eligible, String reason) {
      final used = allow(id, label, paid, eligible.min(groupLeft),
          '$reason; shared ₹1,50,000 group cap');
      groupLeft -= used;
    }

    for (final (i, policy) in input.lifePremiums.indexed) {
      investment(
          'IT-INVEST-LIFE',
          'Life insurance ${i + 1}',
          policy.paid,
          policy.eligible,
          policy.selfSpouseOrChild
              ? '${policy.percentage}% of actual capital sum assured'
              : 'Insured person is not self, spouse or child');
    }
    for (final (field, flag, label) in [
      (
        TaxAmountField.tuitionChildOne,
        TaxConfirmation.tuitionChildOneEligible,
        'Tuition child 1'
      ),
      (
        TaxAmountField.tuitionChildTwo,
        TaxConfirmation.tuitionChildTwoEligible,
        'Tuition child 2'
      ),
    ]) {
      investment(
          'IT-INVEST-TUITION',
          label,
          a(field),
          input.confirmed(flag) ? a(field) : Exact.zero,
          'At most two children; full-time education in India; tuition only');
    }
    final housing = input.confirmed(TaxConfirmation.housingPurchaseEligible);
    investment(
        'IT-INVEST-HOUSING',
        'Housing principal / qualifying instalment',
        a(TaxAmountField.housingPrincipal),
        housing && input.housingPaymentKind != HousingPaymentKind.otherLender
            ? a(TaxAmountField.housingPrincipal)
            : Exact.zero,
        'Qualifying purchase/construction and named lender or instalment category');
    investment(
        'IT-INVEST-HOUSING',
        'Housing transfer charges',
        a(TaxAmountField.housingTransferCharges),
        housing ? a(TaxAmountField.housingTransferCharges) : Exact.zero,
        'Stamp duty/registration and eligible transfer expenses; not interest, repairs or membership fees');
    investment(
        'IT-INVEST-NSC',
        'NSC subscription and reinvested interest',
        a(TaxAmountField.nscSubscription) +
            a(TaxAmountField.nscReinvestedInterest),
        a(TaxAmountField.nscSubscription) +
            a(TaxAmountField.nscReinvestedInterest),
        'VIII Issue subscription plus eligible first-four-year reinvestment; final interest excluded');
    for (final (field, id, label, reason) in [
      (
        TaxAmountField.bankFiveYearDeposit,
        'IT-INVEST-BANK5',
        'Five-year bank tax-saving deposit',
        'Bank Term Deposit Scheme 2006, scheduled bank, single holder and five-year lock-in'
      ),
      (
        TaxAmountField.postFiveYearDeposit,
        'IT-INVEST-POST5',
        'Five-year Post Office Time Deposit',
        'National Savings Time Deposit Scheme 2019, five-year single-held account'
      ),
      (
        TaxAmountField.scssDeposit,
        'IT-INVEST-SCSS',
        'SCSS opening deposit',
        '2019 SCSS, claimant at least 60 at opening, single-held and within scheme ceiling'
      ),
      (
        TaxAmountField.sukanyaChildOne,
        'IT-INVEST-SUKANYA',
        'Sukanya child 1',
        'Eligible distinct girl-child account, paid by claimant in first 15 deposit years'
      ),
      (
        TaxAmountField.sukanyaChildTwo,
        'IT-INVEST-SUKANYA',
        'Sukanya child 2',
        'Second distinct eligible girl-child account, paid by claimant'
      ),
    ]) {
      investment(id, label, a(field), a(field), reason);
    }
    final own = a(TaxAmountField.ownNpsTotal);
    final additionalEligible = own.min(Exact.rupees(50000));
    // Allocate actual contribution once: first the additional bucket, then group.
    allow(
        'IT-NPS',
        'Additional own NPS (80CCD(1B) / 124(3))',
        own.min(Exact.rupees(50000)),
        additionalEligible,
        'Additional cap ₹50,000');
    final remaining = own - additionalEligible;
    // Presence is material: explicit zero is a declared statutory base, while
    // omission cannot establish the employee percentage limit. Evaluate this
    // dependency only after actual eligible deductions consume both budgets.
    if (old &&
        remaining.isPositive &&
        groupLeft.isPositive &&
        available.isPositive &&
        input.confirmed(TaxConfirmation.npsEmployee) &&
        !input.amounts.containsKey(TaxAmountField.npsSalaryBase)) {
      return (
        decisions: List.unmodifiable(decisions),
        issues: const [
          'Own-NPS salary base: enter the statutory employee salary base to evaluate the remaining contribution under the shared investment cap. Enter 0 only if your qualifying salary components total zero; gross salary is not substituted.'
        ],
      );
    }
    final percentageCap = input.confirmed(TaxConfirmation.npsEmployee)
        ? a(TaxAmountField.npsSalaryBase).ratio(10, 100)
        : grossTotalIncome.ratio(20, 100);
    allow(
        'IT-NPS',
        'Own NPS investment group (80CCD(1) / Schedule XV)',
        remaining,
        remaining.min(percentageCap).min(groupLeft),
        'Own contribution remaining after additional deduction; 10% employee salary or 20% other individual gross total income; shared group cap');

    var checkupLeft = Exact.rupees(5000);
    for (final family in [true, false]) {
      final insurance = a(family
          ? TaxAmountField.familyInsurance
          : TaxAmountField.parentInsurance);
      final checkup = a(
          family ? TaxAmountField.familyCheckup : TaxAmountField.parentCheckup);
      final medical = a(
          family ? TaxAmountField.familyMedical : TaxAmountField.parentMedical);
      final seniorInsured = input.confirmed(family
          ? TaxConfirmation.familySeniorInsured
          : TaxConfirmation.parentSeniorInsured);
      final seniorUninsured = input.confirmed(family
          ? TaxConfirmation.familyUninsuredResidentSenior
          : TaxConfirmation.parentUninsuredResidentSenior);
      // Insurance and medical may concern different people in one bucket.
      final cap = Exact.rupees((seniorInsured && insurance.isPositive) ||
              (seniorUninsured && medical.isPositive)
          ? 50000
          : 25000);
      final insured =
          insurance.min(Exact.rupees(seniorInsured ? 50000 : 25000));
      final medicalEligible =
          seniorUninsured ? medical.min(Exact.rupees(50000)) : Exact.zero;
      final paidBase = (insured + medicalEligible).min(cap);
      final allowedCheckup = checkup.min(checkupLeft).min(cap - paidBase);
      checkupLeft -= allowedCheckup;
      allow(
          'IT-HEALTH',
          family
              ? 'Health: self / spouse / dependent children'
              : 'Health: parents',
          insurance + medical + checkup,
          paidBase + allowedCheckup,
          'Bucket cap ${cap.inr}; checkup eligible ${allowedCheckup.inr} within shared ₹5,000; medical only for uninsured resident senior');
    }
    final education = a(TaxAmountField.educationInterest);
    allow(
        'IT-EDUCATION',
        'Education-loan interest',
        education,
        input.educationRepaymentYear <= 8 ? education : Exact.zero,
        'Eligible interest only, first repayment year plus seven years');
    final interest = a(TaxAmountField.savingsInterest) +
        (a(TaxAmountField.postOfficeSavingsInterest) - Exact.rupees(3500))
            .positive +
        (input.age == TaxAge.below60
            ? Exact.zero
            : a(TaxAmountField.depositInterest));
    allow(
        'IT-INTEREST-DEDUCTION',
        input.age == TaxAge.below60
            ? 'Savings interest (80TTA / 153)'
            : 'Senior deposit interest (80TTB / 153)',
        interest,
        (interestAfterSetOff ?? interest)
            .min(Exact.rupees(input.age == TaxAge.below60 ? 10000 : 50000)),
        'Automatic single interest deduction after exemptions and loss allocation; other ordinary interest excluded');
    return (decisions: List.unmodifiable(decisions), issues: const []);
  }
}
