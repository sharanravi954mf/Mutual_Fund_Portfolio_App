import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/domain/loan_part_payment_calculator.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/models/loan_part_payment.dart';

LoanPartPaymentInput input(
        {double principal = 1000000,
        int months = 120,
        double rate = 8.5,
        double payment = 100000}) =>
    LoanPartPaymentInput(
        principal: principal,
        months: months,
        annualRatePercent: rate,
        partPayment: payment);

void main() {
  const calculator = LoanPartPaymentCalculator();

  void verifySchedule(List<AmortizationRow> rows, double principal, double emi,
      double rate, int maxMonths, double scale) {
    final tolerance = scale * 2e-12;
    expect(rows.length, lessThanOrEqualTo(maxMonths));
    if (principal == 0) {
      expect(rows, isEmpty);
      return;
    }
    expect(rows, isNotEmpty);
    expect(rows.first.openingOutstanding, principal);
    var previous = principal;
    var principalSum = 0.0;
    for (final (index, row) in rows.indexed) {
      expect(row.monthNumber, index + 1);
      expect(row.openingOutstanding, previous);
      for (final amount in [
        row.openingOutstanding,
        row.payment,
        row.interestComponent,
        row.principalComponent,
        row.closingOutstanding
      ]) {
        expect(amount.isFinite && amount >= 0, isTrue);
      }
      expect(row.interestComponent,
          closeTo(row.openingOutstanding * rate / 12 / 100, tolerance));
      expect(row.payment, lessThanOrEqualTo(emi));
      expect(row.payment,
          closeTo(row.interestComponent + row.principalComponent, tolerance));
      expect(row.closingOutstanding,
          closeTo(row.openingOutstanding - row.principalComponent, tolerance));
      expect(
          row.closingOutstanding,
          closeTo(row.openingOutstanding + row.interestComponent - row.payment,
              tolerance));
      principalSum += row.principalComponent;
      previous = row.closingOutstanding;
    }
    expect(rows.last.closingOutstanding, 0);
    expect(principalSum, closeTo(principal, tolerance * 4));
  }

  test('locked interest summaries and first/last amortization rows', () {
    final result = calculator.calculate(input());
    expect(result.baselineRemainingInterest, closeTo(487828.27, .005));
    expect(result.sameTenure.totalInterest, closeTo(439045.44, .005));
    expect(result.sameTenure.interestSaved, closeTo(48782.83, .005));
    expect(result.sameEmi.totalInterest, closeTo(368084.53, .005));
    expect(result.sameEmi.interestSaved, closeTo(119743.74, .005));
    final a = result.sameTenure.schedule.first;
    expect(a.monthNumber, 1);
    expect(a.openingOutstanding, 900000);
    expect(a.payment, closeTo(11158.71, .005));
    expect(a.interestComponent, closeTo(6375, 1e-9));
    expect(a.principalComponent, closeTo(4783.71, .005));
    expect(a.closingOutstanding, closeTo(895216.29, .005));
    final b = result.sameEmi.schedule.first;
    expect(b.openingOutstanding, 900000);
    expect(b.payment, closeTo(12398.57, .005));
    expect(b.interestComponent, closeTo(6375, 1e-9));
    expect(b.principalComponent, closeTo(6023.57, .005));
    expect(b.closingOutstanding, closeTo(893976.43, .005));
    final last = result.sameEmi.schedule.last;
    expect(last.monthNumber, 103);
    expect(last.openingOutstanding, closeTo(3406.37, .005));
    expect(last.payment, closeTo(3430.50, .005));
    expect(last.interestComponent, closeTo(24.13, .005));
    expect(last.principalComponent, closeTo(3406.37, .005));
    expect(last.closingOutstanding, 0);
    expect(result.sameEmi.finalPayment, last.payment);
  });

  test('zero payment schedules exactly reuse baseline rows and have no savings',
      () {
    final result = calculator.calculate(input(payment: 0));
    expect(result.sameTenure.schedule, orderedEquals(result.baselineSchedule));
    expect(result.sameEmi.schedule, orderedEquals(result.baselineSchedule));
    expect(result.sameTenure.interestSaved, 0);
    expect(result.sameEmi.interestSaved, 0);
  });

  test('schedule collections cannot be mutated', () {
    final result = calculator.calculate(input());
    for (final schedule in [
      result.baselineSchedule,
      result.sameTenure.schedule,
      result.sameEmi.schedule
    ]) {
      expect(schedule.clear, throwsUnsupportedError);
    }
  });

  test(
      '600 months at maximum principal/rate closes without discarding a residual',
      () {
    final result = calculator
        .calculate(input(principal: 1e10, months: 600, rate: 30, payment: .01));
    for (final schedule in [
      result.baselineSchedule,
      result.sameTenure.schedule,
      result.sameEmi.schedule
    ]) {
      expect(schedule.length, 600);
      expect(schedule.last.closingOutstanding, 0);
    }
    verifySchedule(
        result.baselineSchedule, 1e10, result.currentEmi, 30, 600, 1e10);
    verifySchedule(result.sameTenure.schedule, result.remainingPrincipal,
        result.sameTenure.revisedEmi, 30, 600, 1e10);
    verifySchedule(result.sameEmi.schedule, result.remainingPrincipal,
        result.currentEmi, 30, 600, 1e10);
  });

  test('locked 8.5 percent example matches EMI, tenure and last payment', () {
    final result = calculator.calculate(input());
    expect(result.currentEmi, closeTo(12398.5688874511, 1e-7));
    expect(result.remainingPrincipal, 900000);
    expect(result.sameTenure.revisedEmi, closeTo(11158.711998706, 1e-7));
    expect(result.sameTenure.monthlyReduction, closeTo(1239.856888745, 1e-7));
    expect(result.sameEmi.revisedMonths, 103);
    expect(result.sameEmi.monthsReduced, 17);
    expect(result.sameEmi.finalPayment, closeTo(3430.5025571, 1e-5));
  });

  test('zero interest supports a smaller final instalment', () {
    final result = calculator.calculate(
        input(principal: 100000, months: 12, rate: 0, payment: 10000));
    expect(result.currentEmi, closeTo(8333.333333, 1e-6));
    expect(result.sameTenure.revisedEmi, 7500);
    expect(result.sameEmi.revisedMonths, 11);
    expect(result.sameEmi.finalPayment, closeTo(6666.666667, 1e-6));
  });

  test('zero part payment exactly reproduces the contractual baseline', () {
    final result = calculator.calculate(input(payment: 0));
    expect(result.sameTenure.revisedEmi, result.currentEmi);
    expect(result.sameTenure.monthlyReduction, 0);
    expect(result.sameEmi.revisedMonths, 120);
    expect(result.sameEmi.monthsReduced, 0);
    expect(result.sameEmi.finalPayment, result.currentEmi);
  });

  test('full prepayment returns immediate payoff', () {
    final result = calculator.calculate(input(payment: 1000000));
    expect(result.isFullyRepaid, isTrue);
    expect(result.remainingPrincipal, 0);
    expect(result.sameTenure.revisedEmi, 0);
    expect(result.sameEmi.revisedMonths, 0);
    expect(result.sameEmi.monthsReduced, 120);
    expect(result.sameEmi.finalPayment, 0);
  });

  test('one month uses simple monthly interest and a final smaller payment',
      () {
    final result = calculator.calculate(
        input(principal: 1000, months: 1, rate: 12, payment: 100.25));
    expect(result.currentEmi, closeTo(1010, 1e-9));
    expect(result.sameTenure.revisedEmi, closeTo(908.7475, 1e-9));
    expect(result.sameEmi.revisedMonths, 1);
    expect(result.sameEmi.finalPayment, closeTo(908.7475, 1e-9));
  });

  test('decimal principal, payment and rate retain precision', () {
    final result = calculator.calculate(
        input(principal: 123456.78, months: 1, rate: 8.375, payment: 1234.56));
    expect(result.remainingPrincipal, closeTo(122222.22, 1e-8));
    expect(result.currentEmi, closeTo(123456.78 * (1 + 8.375 / 1200), 1e-8));
    expect(result.sameEmi.finalPayment,
        closeTo(122222.22 * (1 + 8.375 / 1200), 1e-8));
  });

  test('exact zero-interest payoff does not create a dust instalment', () {
    final result = calculator.calculate(
        input(principal: 100000, months: 12, rate: 0, payment: 25000));
    expect(result.sameEmi.revisedMonths, 9);
    expect(result.sameEmi.finalPayment, closeTo(result.currentEmi, 1e-8));
  });

  test('tiny positive rate avoids cancellation and approaches zero rate', () {
    final result = calculator.calculate(
        input(principal: 100000, months: 12, rate: 1e-12, payment: 10000));
    expect(result.currentEmi, closeTo(100000 / 12, 1e-8));
    expect(result.sameEmi.revisedMonths, 11);
  });

  for (final bad in [
    input(principal: 0),
    input(principal: -1),
    input(principal: double.nan),
    input(principal: double.infinity),
    input(principal: 10000000001),
    input(months: 0),
    input(months: -1),
    input(months: 601),
    input(rate: -1),
    input(rate: double.nan),
    input(rate: double.infinity),
    input(rate: 30.01),
    input(payment: -1),
    input(payment: double.nan),
    input(payment: double.infinity),
    input(payment: 1000001),
  ].indexed) {
    test(
        'invalid domain input ${bad.$1} is rejected with no values in exception',
        () {
      expect(
          () => calculator.calculate(bad.$2),
          throwsA(isA<LoanInputException>().having((error) => error.toString(),
              'safe diagnostic', 'Invalid loan calculator input')));
    });
  }

  test('unrepresentable subnormal EMI is rejected safely', () {
    expect(
        () => calculator.calculate(input(
            principal: double.minPositive, months: 600, rate: 0, payment: 0)),
        throwsA(isA<LoanInputException>()));
  });

  test(
      '800 deterministic boundary scenarios satisfy invariants and monotonicity',
      () {
    for (final principal in [
      0.01,
      1.0,
      1000000.0,
      LoanPartPaymentCalculator.maxPrincipal
    ]) {
      for (final months in [1, 2, 12, 120, 600]) {
        for (final rate in [0.0, 1e-12, 0.1, 8.5, 30.0]) {
          double? priorEmi;
          int? priorMonths;
          for (final fraction in [
            0.0,
            0.00000001,
            0.1,
            0.2,
            0.5,
            0.9,
            0.99999999,
            1.0
          ]) {
            final result = calculator.calculate(input(
                principal: principal,
                months: months,
                rate: rate,
                payment: principal * fraction));
            final amounts = [
              result.baselineRemainingInterest,
              result.sameTenure.totalInterest,
              result.sameTenure.interestSaved,
              result.sameEmi.totalInterest,
              result.sameEmi.interestSaved,
              result.remainingPrincipal,
              result.currentEmi,
              result.sameTenure.revisedEmi,
              result.sameTenure.monthlyReduction,
              result.sameEmi.finalPayment
            ];
            for (final value in amounts) {
              expect(value.isFinite, isTrue);
              expect(value, greaterThanOrEqualTo(0));
            }
            expect(result.remainingPrincipal, lessThanOrEqualTo(principal));
            expect(result.sameTenure.revisedEmi,
                lessThanOrEqualTo(result.currentEmi));
            expect(result.sameEmi.revisedMonths, inInclusiveRange(0, months));
            expect(result.sameEmi.monthsReduced,
                months - result.sameEmi.revisedMonths);
            expect(result.sameEmi.finalPayment,
                lessThanOrEqualTo(result.currentEmi));
            verifySchedule(result.baselineSchedule, principal,
                result.currentEmi, rate, months, principal);
            verifySchedule(
                result.sameTenure.schedule,
                result.remainingPrincipal,
                result.sameTenure.revisedEmi,
                rate,
                months,
                principal);
            verifySchedule(result.sameEmi.schedule, result.remainingPrincipal,
                result.currentEmi, rate, months, principal);
            expect(
                result.sameTenure.schedule.length, fraction == 1 ? 0 : months);
            expect(
                result.sameEmi.schedule.length, result.sameEmi.revisedMonths);
            final schedules = [
              result.baselineSchedule,
              result.sameTenure.schedule,
              result.sameEmi.schedule
            ];
            final totals = [
              result.baselineRemainingInterest,
              result.sameTenure.totalInterest,
              result.sameEmi.totalInterest
            ];
            for (var i = 0; i < schedules.length; i++) {
              expect(
                  schedules[i].fold<double>(
                      0, (sum, row) => sum + row.interestComponent),
                  totals[i]);
              if (rate == 0) {
                expect(totals[i], 0);
                expect(
                    schedules[i].every((row) =>
                        row.principalComponent == row.payment &&
                        row.interestComponent == 0),
                    isTrue);
              }
            }
            expect(
                result.sameTenure.interestSaved,
                closeTo(
                    result.baselineRemainingInterest -
                        result.sameTenure.totalInterest,
                    principal * 1e-10));
            expect(
                result.sameEmi.interestSaved,
                closeTo(
                    result.baselineRemainingInterest -
                        result.sameEmi.totalInterest,
                    principal * 1e-10));
            if (priorEmi != null) {
              expect(result.sameTenure.revisedEmi, lessThanOrEqualTo(priorEmi));
            }
            if (priorMonths != null) {
              expect(
                  result.sameEmi.revisedMonths, lessThanOrEqualTo(priorMonths));
            }
            if (fraction == 0) {
              expect(result.sameTenure.revisedEmi, result.currentEmi);
              expect(result.sameEmi.revisedMonths, months);
              expect(result.sameEmi.monthsReduced, 0);
              expect(result.sameTenure.interestSaved, 0);
              expect(result.sameEmi.interestSaved, 0);
            }
            if (fraction == 1) {
              expect(result.remainingPrincipal, 0);
              expect(result.sameTenure.revisedEmi, 0);
              expect(result.sameEmi.revisedMonths, 0);
              expect(result.sameTenure.totalInterest, 0);
              expect(result.sameEmi.totalInterest, 0);
              expect(result.sameTenure.interestSaved,
                  result.baselineRemainingInterest);
              expect(result.sameEmi.interestSaved,
                  result.baselineRemainingInterest);
            }
            priorEmi = result.sameTenure.revisedEmi;
            priorMonths = result.sameEmi.revisedMonths;
          }
        }
      }
    }
  });
}
