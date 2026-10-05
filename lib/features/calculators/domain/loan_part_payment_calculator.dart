import 'dart:math' as math;

import '../models/loan_part_payment.dart';

enum LoanInputField { principal, months, annualRate, partPayment }

/// Contains safe messages only, never the financial values that caused errors.
class LoanInputException implements Exception {
  LoanInputException(Map<LoanInputField, String> errors)
      : errors = Map.unmodifiable(errors);
  final Map<LoanInputField, String> errors;

  @override
  String toString() => 'Invalid loan calculator input';
}

/// Client-only, deterministic reducing-balance monthly loan estimates.
class LoanPartPaymentCalculator {
  const LoanPartPaymentCalculator();

  // Bound both work and numerical conditioning of the monthly simulation.
  static const double maxPrincipal = 10000000000;
  static const int maxMonths = 600;
  static const double maxAnnualRate = 30;

  Map<LoanInputField, String> validate(LoanPartPaymentInput input) {
    final errors = <LoanInputField, String>{};
    if (!input.principal.isFinite || input.principal <= 0) {
      errors[LoanInputField.principal] = 'Enter an amount greater than zero.';
    } else if (input.principal > maxPrincipal) {
      errors[LoanInputField.principal] =
          'Maximum supported amount is ₹10,00,00,00,000.';
    }
    if (input.months < 1 || input.months > maxMonths) {
      errors[LoanInputField.months] =
          'Enter a whole number from 1 to 600 months.';
    }
    if (!input.annualRatePercent.isFinite ||
        input.annualRatePercent < 0 ||
        input.annualRatePercent > maxAnnualRate) {
      errors[LoanInputField.annualRate] = 'Enter a rate from 0 to 30% p.a.';
    }
    if (!input.partPayment.isFinite || input.partPayment < 0) {
      errors[LoanInputField.partPayment] =
          'Enter a part payment of zero or more.';
    } else if (input.partPayment > input.principal) {
      errors[LoanInputField.partPayment] =
          'Part payment cannot exceed the outstanding amount.';
    }
    return errors;
  }

  LoanPartPaymentResult calculate(LoanPartPaymentInput input) {
    final errors = validate(input);
    if (errors.isNotEmpty) throw LoanInputException(errors);

    final rate = input.annualRatePercent / 12 / 100;
    final factor = _annuityFactor(rate, input.months);
    final currentEmi = input.principal / factor;
    if (currentEmi == 0) {
      throw LoanInputException({
        LoanInputField.principal:
            'Amount is too small for a reliable estimate.',
      });
    }
    final remaining = input.principal - input.partPayment;
    final revisedEmi = remaining / factor;
    final sameEmi = remaining == 0
        ? SameEmiResult(
            revisedMonths: 0, monthsReduced: input.months, finalPayment: 0)
        : input.partPayment == 0
            ? SameEmiResult(
                revisedMonths: input.months,
                monthsReduced: 0,
                finalPayment: currentEmi)
            : _simulate(remaining, rate, currentEmi, input.months);

    return LoanPartPaymentResult(
      input: input,
      remainingPrincipal: remaining,
      currentEmi: currentEmi,
      sameTenure: SameTenureResult(
        revisedEmi: revisedEmi,
        monthlyReduction: currentEmi - revisedEmi,
      ),
      sameEmi: sameEmi,
    );
  }

  double _annuityFactor(double rate, int months) {
    if (rate == 0) return months.toDouble();
    // Avoid subtracting nearly equal values for tiny positive rates.
    if (rate * months < 0.001) {
      final discount = 1 / (1 + rate);
      var factor = 0.0;
      for (var month = 0; month < months; month++) {
        factor = (factor + 1) * discount;
      }
      return factor;
    }
    return (1 - math.pow(1 + rate, -months)) / rate;
  }

  SameEmiResult _simulate(
      double principal, double rate, double emi, int months) {
    var balance = principal;
    var finalPayment = 0.0;
    // This tolerance only absorbs floating point dust, not rupee rounding.
    final tolerance = emi * 1e-13;
    for (var month = 1; month <= months; month++) {
      final interest = balance * rate;
      final amountDue = balance + interest;
      finalPayment = math.min(emi, amountDue);
      balance = amountDue - finalPayment;
      if (balance <= tolerance) {
        return SameEmiResult(
          revisedMonths: month,
          monthsReduced: months - month,
          finalPayment: finalPayment,
        );
      }
    }
    // The original EMI amortizes the larger original principal in `months`.
    // A reduced principal cannot require an extra instalment. Absorb any
    // accumulated floating point residue at that contractual upper bound.
    return SameEmiResult(
        revisedMonths: months, monthsReduced: 0, finalPayment: finalPayment);
  }
}
