enum SipTenureUnit { months, years }

/// Civil dates: calendar arithmetic, never elapsed days or a system clock.
class SipCalendar {
  static DateTime dateOnly(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  static DateTime endDate(DateTime start, int months) =>
      DateTime.utc(start.year, start.month + months, 0);

  static int monthOffset(DateTime start, DateTime date) =>
      (date.year - start.year) * 12 + date.month - start.month;
}

class SipInput {
  const SipInput({
    required this.initialInvestment,
    required this.monthlySip,
    required this.tenure,
    required this.tenureUnit,
    required this.annualRoiPercent,
    required this.lumpSum,
    required this.startDate,
    this.lumpSumDate,
  });

  final double initialInvestment;
  final double monthlySip;
  final int tenure;
  final SipTenureUnit tenureUnit;
  final double annualRoiPercent;
  final double lumpSum;
  final DateTime startDate;
  final DateTime? lumpSumDate;

  int get normalizedMonths =>
      tenureUnit == SipTenureUnit.years ? tenure * 12 : tenure;
  DateTime get planStartDate => SipCalendar.dateOnly(startDate);
  DateTime get planEndDate => SipCalendar.endDate(startDate, normalizedMonths);
}

/// The initial investment is the first row's opening value, not a second flow.
class SipMonth {
  const SipMonth({
    required this.monthNumber,
    required this.openingValue,
    required this.sipContribution,
    required this.lumpSumContribution,
    required this.returnAmount,
    required this.closingValue,
  });

  final int monthNumber;
  final double openingValue;
  final double sipContribution;
  final double lumpSumContribution;
  final double returnAmount;
  final double closingValue;
}

class SipResult {
  SipResult({
    required this.input,
    required this.amountInvested,
    required List<SipMonth> monthlyFlows,
  }) : monthlyFlows = List.unmodifiable(monthlyFlows);

  final SipInput input;
  final double amountInvested;
  final List<SipMonth> monthlyFlows;
  double get totalFundValue => monthlyFlows.last.closingValue;
  double get estimatedReturns => totalFundValue - amountInvested;
  int get normalizedMonths => input.normalizedMonths;
}
