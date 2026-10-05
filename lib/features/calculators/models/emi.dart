import 'amortization_row.dart';

enum TenureUnit { months, years }

/// Unrounded rupees and annual percentage, independent of calendar time.
class EmiInput {
  const EmiInput({
    required this.principal,
    required this.tenure,
    required this.tenureUnit,
    required this.annualRatePercent,
  });

  final double principal;
  final int tenure;
  final TenureUnit tenureUnit;
  final double annualRatePercent;

  int get normalizedMonths =>
      tenureUnit == TenureUnit.years ? tenure * 12 : tenure;
}

class EmiResult {
  EmiResult({
    required this.input,
    required this.monthlyEmi,
    required List<AmortizationRow> schedule,
  })  : schedule = List.unmodifiable(schedule),
        totalInterest =
            schedule.fold(0.0, (sum, row) => sum + row.interestComponent),
        totalRepayment = schedule.fold(0.0, (sum, row) => sum + row.payment);

  final EmiInput input;
  final double monthlyEmi;
  final double totalInterest;
  final double totalRepayment;
  final List<AmortizationRow> schedule;
  int get normalizedMonths => input.normalizedMonths;
}
