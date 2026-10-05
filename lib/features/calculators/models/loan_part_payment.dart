/// All amounts are unrounded rupees; the rate is an annual percentage.
class LoanPartPaymentInput {
  const LoanPartPaymentInput({
    required this.principal,
    required this.months,
    required this.annualRatePercent,
    required this.partPayment,
  });

  final double principal;
  final int months;
  final double annualRatePercent;
  final double partPayment;
}

class SameTenureResult {
  SameTenureResult({
    required this.revisedEmi,
    required this.monthlyReduction,
    required this.totalInterest,
    required this.interestSaved,
    required List<AmortizationRow> schedule,
  }) : schedule = List.unmodifiable(schedule);
  final double revisedEmi;
  final double monthlyReduction;
  final double totalInterest;
  final double interestSaved;
  final List<AmortizationRow> schedule;
}

class SameEmiResult {
  SameEmiResult({
    required this.revisedMonths,
    required this.monthsReduced,
    required this.finalPayment,
    required this.totalInterest,
    required this.interestSaved,
    required List<AmortizationRow> schedule,
  }) : schedule = List.unmodifiable(schedule);
  final int revisedMonths;
  final int monthsReduced;
  final double finalPayment;
  final double totalInterest;
  final double interestSaved;
  final List<AmortizationRow> schedule;
}

class LoanPartPaymentResult {
  LoanPartPaymentResult({
    required this.input,
    required this.remainingPrincipal,
    required this.currentEmi,
    required this.sameTenure,
    required this.sameEmi,
    required this.baselineRemainingInterest,
    required List<AmortizationRow> baselineSchedule,
  }) : baselineSchedule = List.unmodifiable(baselineSchedule);
  final LoanPartPaymentInput input;
  final double remainingPrincipal;
  final double currentEmi;
  final SameTenureResult sameTenure;
  final SameEmiResult sameEmi;
  final double baselineRemainingInterest;
  final List<AmortizationRow> baselineSchedule;

  bool get isFullyRepaid => remainingPrincipal == 0;
}

/// A monthly EMI after the immediate part payment, with no calendar dependency.
class AmortizationRow {
  const AmortizationRow({
    required this.monthNumber,
    required this.openingOutstanding,
    required this.payment,
    required this.interestComponent,
    required this.principalComponent,
    required this.closingOutstanding,
  });
  final int monthNumber;
  final double openingOutstanding;
  final double payment;
  final double interestComponent;
  final double principalComponent;
  final double closingOutstanding;
}
