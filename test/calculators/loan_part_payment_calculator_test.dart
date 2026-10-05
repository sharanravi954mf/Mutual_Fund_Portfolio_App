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
            }
            if (fraction == 1) {
              expect(result.remainingPrincipal, 0);
              expect(result.sameTenure.revisedEmi, 0);
              expect(result.sameEmi.revisedMonths, 0);
            }
            priorEmi = result.sameTenure.revisedEmi;
            priorMonths = result.sameEmi.revisedMonths;
          }
        }
      }
    }
  });
}
