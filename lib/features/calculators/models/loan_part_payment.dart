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
  const SameTenureResult(
      {required this.revisedEmi, required this.monthlyReduction});
  final double revisedEmi;
  final double monthlyReduction;
}

class SameEmiResult {
  const SameEmiResult({
    required this.revisedMonths,
    required this.monthsReduced,
    required this.finalPayment,
  });
  final int revisedMonths;
  final int monthsReduced;
  final double finalPayment;
}

class LoanPartPaymentResult {
  const LoanPartPaymentResult({
    required this.input,
    required this.remainingPrincipal,
    required this.currentEmi,
    required this.sameTenure,
    required this.sameEmi,
  });
  final LoanPartPaymentInput input;
  final double remainingPrincipal;
  final double currentEmi;
  final SameTenureResult sameTenure;
  final SameEmiResult sameEmi;

  bool get isFullyRepaid => remainingPrincipal == 0;
}
