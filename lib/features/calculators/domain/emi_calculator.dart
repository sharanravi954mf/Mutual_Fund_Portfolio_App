import 'dart:math' as math;

import '../models/amortization_row.dart';
import '../models/emi.dart';

enum EmiInputField { principal, tenure, annualRate }

class EmiInputException implements Exception {
  EmiInputException(Map<EmiInputField, String> errors)
      : errors = Map.unmodifiable(errors);
  final Map<EmiInputField, String> errors;
  @override
  String toString() => 'Invalid EMI calculator input';
}

class EmiCalculationException implements Exception {
  const EmiCalculationException();
  @override
  String toString() => 'Unable to reconcile the EMI estimate';
}

/// Pure, bounded, constant-rate reducing-balance loan mathematics.
class EmiCalculator {
  const EmiCalculator();
  static const double maxPrincipal = 10000000000;
  static const int maxMonths = 600;
  static const int maxYears = 50;
  static const double maxAnnualRate = 30;

  static String tenureError(TenureUnit unit) => unit == TenureUnit.months
      ? 'Enter a whole number from 1 to 600 months.'
      : 'Enter a whole number from 1 to 50 years.';

  Map<EmiInputField, String> validate(EmiInput input) {
    final errors = <EmiInputField, String>{};
    if (!input.principal.isFinite || input.principal <= 0) {
      errors[EmiInputField.principal] = 'Enter an amount greater than zero.';
    } else if (input.principal > maxPrincipal) {
      errors[EmiInputField.principal] =
          'Maximum supported amount is ₹10,00,00,00,000.';
    }
    final maxTenure =
        input.tenureUnit == TenureUnit.months ? maxMonths : maxYears;
    // Check raw tenure before multiplication, including direct domain callers.
    if (input.tenure < 1 || input.tenure > maxTenure) {
      errors[EmiInputField.tenure] = tenureError(input.tenureUnit);
    }
    if (!input.annualRatePercent.isFinite ||
        input.annualRatePercent < 0 ||
        input.annualRatePercent > maxAnnualRate) {
      errors[EmiInputField.annualRate] = 'Enter a rate from 0 to 30% p.a.';
    }
    return errors;
  }

  EmiResult calculate(EmiInput input) {
    final errors = validate(input);
    if (errors.isNotEmpty) throw EmiInputException(errors);
    final months = input.normalizedMonths;
    final rate = input.annualRatePercent / 12 / 100;
    final emi = input.principal / _annuityFactor(rate, months);
    if (emi == 0) {
      throw EmiInputException({
        EmiInputField.principal: 'Amount is too small for a reliable estimate.'
      });
    }
    final rows = _amortize(input.principal, rate, emi, months);
    return EmiResult(input: input, monthlyEmi: emi, schedule: rows);
  }

  double _annuityFactor(double rate, int months) {
    if (rate == 0) return months.toDouble();
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

  List<AmortizationRow> _amortize(
      double principal, double rate, double emi, int months) {
    final rows = <AmortizationRow>[];
    final tolerance = math.max(principal, emi) * 1e-12;
    var balance = principal;
    var growthSum = 0.0;
    for (var month = 0; month < months; month++) {
      growthSum = growthSum * (1 + rate) + 1;
    }
    // Algebraically principal[k+1] = principal[k]*(1+r). This avoids
    // amplifying cancellation in EMI-interest over long, high-rate loans.
    var principalStep = principal / growthSum;
    for (var month = 1; month <= months; month++) {
      final opening = balance;
      final interest = opening * rate;
      final amountDue = opening + interest;
      final payment = math.min(emi, amountDue);
      var principalPaid = math.min(principalStep, opening);
      balance = opening - principalPaid;
      final paidOff = balance <= tolerance;
      if (paidOff) {
        balance = 0;
        principalPaid = opening;
      }
      if (rate == 0) principalPaid = payment;
      if (![opening, payment, interest, principalPaid, balance]
              .every((value) => value.isFinite && value >= 0) ||
          (payment - interest - principalPaid).abs() > tolerance ||
          (opening + interest - payment - balance).abs() > tolerance) {
        throw const EmiCalculationException();
      }
      rows.add(AmortizationRow(
        monthNumber: month,
        openingOutstanding: opening,
        payment: payment,
        interestComponent: interest,
        principalComponent: principalPaid,
        closingOutstanding: balance,
      ));
      if (paidOff) return rows;
      principalStep *= 1 + rate;
    }
    // Never discard a material residual or append an extra dust payment.
    throw const EmiCalculationException();
  }
}
