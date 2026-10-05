import 'dart:math' as math;

import '../models/loan_part_payment.dart';

enum LoanInputField { principal, months, annualRate, partPayment }

/// An internal accounting invariant failed; never includes financial values.
class LoanCalculationException implements Exception {
  const LoanCalculationException();
  @override
  String toString() => 'Unable to reconcile the loan estimate';
}

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
    final baseline = _amortize(input.principal, rate, currentEmi, input.months);
    final sameTenureSchedule = input.partPayment == 0
        ? baseline
        : _amortize(remaining, rate, revisedEmi, input.months);
    final sameEmiSchedule = input.partPayment == 0
        ? baseline
        : _amortize(input.principal, rate, currentEmi, input.months,
            partPayment: input.partPayment);
    final baselineInterest = _interest(baseline);
    final sameTenureInterest = _interest(sameTenureSchedule);
    final sameEmiInterest = _interest(sameEmiSchedule);

    return LoanPartPaymentResult(
      input: input,
      remainingPrincipal: remaining,
      currentEmi: currentEmi,
      baselineSchedule: baseline,
      baselineRemainingInterest: baselineInterest,
      sameTenure: SameTenureResult(
        revisedEmi: revisedEmi,
        monthlyReduction: currentEmi - revisedEmi,
        totalInterest: sameTenureInterest,
        interestSaved: _savings(baselineInterest, sameTenureInterest),
        schedule: sameTenureSchedule,
      ),
      sameEmi: SameEmiResult(
        revisedMonths: sameEmiSchedule.length,
        monthsReduced: input.months - sameEmiSchedule.length,
        finalPayment:
            sameEmiSchedule.isEmpty ? 0 : sameEmiSchedule.last.payment,
        totalInterest: sameEmiInterest,
        interestSaved: _savings(baselineInterest, sameEmiInterest),
        schedule: sameEmiSchedule,
      ),
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

  double _interest(List<AmortizationRow> rows) =>
      rows.fold(0.0, (total, row) => total + row.interestComponent);

  double _savings(double baseline, double scenario) {
    final saved = baseline - scenario;
    final tolerance = math.max(baseline, scenario) * 1e-12;
    if (!saved.isFinite || saved < -tolerance) {
      throw const LoanCalculationException();
    }
    return saved < 0 ? 0 : saved;
  }

  List<AmortizationRow> _amortize(
      double principal, double rate, double emi, int months,
      {double partPayment = 0}) {
    var balance = principal - partPayment;
    if (balance == 0) return const [];
    final rows = <AmortizationRow>[];
    final tolerance = math.max(principal, emi) * 1e-12;

    // For constant EMI, principal[k+1] = principal[k] * (1+r).
    // Computing the first principal component from a geometric sum avoids
    // cancellation in EMI - interest and its amplification over 600 months.
    // Part payment adds A*r to that first component. This is algebraically
    // identical to the monthly balance recurrence, without balance rounding.
    var growthSum = 0.0;
    for (var month = 0; month < months; month++) {
      growthSum = growthSum * (1 + rate) + 1;
    }
    var principalStep = principal / growthSum + partPayment * rate;
    for (var month = 1; month <= months; month++) {
      final opening = balance;
      final interest = balance * rate;
      final amountDue = balance + interest;
      var payment = math.min(emi, amountDue);
      var principalPaid = math.min(principalStep, opening);
      balance = opening - principalPaid;
      final finalMonth = balance <= tolerance;
      if (finalMonth) {
        balance = 0;
        principalPaid = opening;
        // Keep a contractual last EMI unchanged when the difference is only
        // roundoff. Materially smaller final payments always use amountDue.
        if (month == months && (amountDue - emi).abs() <= tolerance) {
          payment = emi;
        }
      }
      if (rate == 0) principalPaid = payment;
      if (![opening, payment, interest, principalPaid, balance]
              .every((value) => value.isFinite && value >= 0) ||
          (payment - interest - principalPaid).abs() > tolerance ||
          (opening + interest - payment - balance).abs() > tolerance) {
        throw const LoanCalculationException();
      }
      rows.add(AmortizationRow(
        monthNumber: month,
        openingOutstanding: opening,
        payment: payment,
        interestComponent: interest,
        principalComponent: principalPaid,
        closingOutstanding: balance,
      ));
      if (finalMonth) return rows;
      principalStep *= 1 + rate;
    }
    // A material residual is an invariant failure, never an extra dust row
    // or a silently discarded balance.
    throw const LoanCalculationException();
  }
}
