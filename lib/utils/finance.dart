import 'dart:math';

/// Calculates absolute return percentage.
///
/// Formula: ((Current Value - Invested Value) / Invested Value) * 100
double calculateAbsoluteReturn(double invested, double current) {
  if (invested <= 0) return 0.0;
  return ((current - invested) / invested) * 100.0;
}

class CashFlow {
  final double amount;
  final DateTime date;

  CashFlow(this.amount, this.date);
}

/// Calculates the Internal Rate of Return for irregular cash flows (XIRR).
/// Uses the Newton-Raphson root-finding method.
///
/// Formula to solve for r: Sum(C_i / (1 + r)^((d_i - d_1) / 365)) = 0
///
/// @param cashFlows List of cash flows with amounts and dates.
/// @param guess Initial guess for rate (default: 0.1 for 10%).
/// @returns Annualized rate of return as a percentage (e.g. 15.5 for 15.5%).
double calculateXIRR(List<CashFlow> cashFlows, {double guess = 0.1}) {
  if (cashFlows.length < 2) return 0.0;

  // Sort chronologically
  final sorted = List<CashFlow>.from(cashFlows)
    ..sort((a, b) => a.date.compareTo(b.date));
  final d0 = sorted.first.date;

  // Function f(r)
  double f(double r) {
    double sum = 0.0;
    for (var cf in sorted) {
      final days = cf.date.difference(d0).inDays;
      sum += cf.amount / pow(1 + r, days / 365.0);
    }
    return sum;
  }

  // Derivative f'(r)
  double df(double r) {
    double sum = 0.0;
    for (var cf in sorted) {
      final days = cf.date.difference(d0).inDays;
      sum += -(days / 365.0) * cf.amount / pow(1 + r, (days / 365.0) + 1.0);
    }
    return sum;
  }

  double r = guess;
  const tolerance = 1e-6;
  const maxIterations = 100;

  for (var i = 0; i < maxIterations; i++) {
    final val = f(r);
    final deriv = df(r);

    if (deriv.abs() < 1e-12) {
      break; // Prevent division by zero
    }

    final nextR = r - val / deriv;

    if ((nextR - r).abs() < tolerance) {
      return nextR * 100.0; // Return percentage
    }

    r = nextR;
  }

  return r * 100.0; // Fallback to last calculated rate
}
