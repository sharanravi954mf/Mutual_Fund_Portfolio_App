import '../models/sip.dart';

enum SipInputField {
  initialInvestment,
  monthlySip,
  tenure,
  annualRoi,
  lumpSum,
  lumpSumDate
}

class SipInputException implements Exception {
  SipInputException(Map<SipInputField, String> errors)
      : errors = Map.unmodifiable(errors);
  final Map<SipInputField, String> errors;
  @override
  String toString() => 'Invalid SIP calculator input';
}

class SipCalculationException implements Exception {
  const SipCalculationException();
  @override
  String toString() => 'Unable to calculate the SIP estimate';
}

/// A single pure, bounded monthly cash-flow simulation supplies every result.
class SipCalculator {
  const SipCalculator();

  static const double maxAmount = 10000000000;
  static const double maxAnnualRoi = 30;
  static const int maxMonths = 600;
  static const int maxYears = 50;

  static String tenureError(SipTenureUnit unit) => unit == SipTenureUnit.months
      ? 'Enter a whole number from 1 to 600 months.'
      : 'Enter a whole number from 1 to 50 years.';

  Map<SipInputField, String> validate(SipInput input) {
    final errors = <SipInputField, String>{};
    for (final (field, amount) in [
      (SipInputField.initialInvestment, input.initialInvestment),
      (SipInputField.monthlySip, input.monthlySip),
      (SipInputField.lumpSum, input.lumpSum),
    ]) {
      if (!amount.isFinite ||
          amount < 0 ||
          (field == SipInputField.monthlySip && amount == 0)) {
        errors[field] = field == SipInputField.monthlySip
            ? 'Enter a monthly SIP greater than zero.'
            : 'Enter an amount of zero or more.';
      } else if (amount > maxAmount) {
        errors[field] = 'Maximum supported amount is ₹10,00,00,00,000.';
      }
    }
    final limit =
        input.tenureUnit == SipTenureUnit.months ? maxMonths : maxYears;
    if (input.tenure < 1 || input.tenure > limit) {
      errors[SipInputField.tenure] = tenureError(input.tenureUnit);
    }
    if (!input.annualRoiPercent.isFinite ||
        input.annualRoiPercent < 0 ||
        input.annualRoiPercent > maxAnnualRoi) {
      errors[SipInputField.annualRoi] =
          'Enter an expected ROI from 0 to 30% p.a.';
    }
    if (input.lumpSum > 0) {
      final date = input.lumpSumDate;
      if (date == null) {
        errors[SipInputField.lumpSumDate] = 'Choose a date for the lump sum.';
      } else {
        final selected = SipCalendar.dateOnly(date);
        if (selected.isBefore(input.planStartDate)) {
          errors[SipInputField.lumpSumDate] =
              'Date cannot be before the calculation date.';
        } else if (!errors.containsKey(SipInputField.tenure) &&
            selected.isAfter(input.planEndDate)) {
          errors[SipInputField.lumpSumDate] =
              'Date cannot be after the final month of the SIP tenure.';
        }
      }
    }
    return errors;
  }

  SipResult calculate(SipInput input) {
    final errors = validate(input);
    if (errors.isNotEmpty) throw SipInputException(errors);
    final rate = input.annualRoiPercent / 12 / 100;
    final lumpMonth = input.lumpSum > 0
        ? SipCalendar.monthOffset(input.startDate, input.lumpSumDate!)
        : -1;
    var balance = input.initialInvestment;
    var invested = input.initialInvestment;
    final flows = <SipMonth>[];
    for (var month = 0; month < input.normalizedMonths; month++) {
      final opening = balance;
      final lump = month == lumpMonth ? input.lumpSum : 0.0;
      final contribution = input.monthlySip + lump;
      invested += contribution;
      final funded = opening + contribution;
      final growth = funded * rate;
      balance = funded + growth;
      if (![invested, balance, growth].every((v) => v.isFinite && v >= 0) ||
          balance < invested) {
        throw const SipCalculationException();
      }
      flows.add(SipMonth(
        monthNumber: month + 1,
        openingValue: opening,
        sipContribution: input.monthlySip,
        lumpSumContribution: lump,
        returnAmount: growth,
        closingValue: balance,
      ));
    }
    return SipResult(
        input: input, amountInvested: invested, monthlyFlows: flows);
  }
}
