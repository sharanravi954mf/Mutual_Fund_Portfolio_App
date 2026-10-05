import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/domain/emi_calculator.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/models/emi.dart';

EmiInput input(
        {double principal = 1000000,
        int tenure = 120,
        TenureUnit unit = TenureUnit.months,
        double rate = 8.5}) =>
    EmiInput(
        principal: principal,
        tenure: tenure,
        tenureUnit: unit,
        annualRatePercent: rate);

void verify(EmiResult result) {
  final p = result.input.principal;
  final tolerance = math.max(p, result.monthlyEmi) * 1e-12;
  final totalTolerance = math.max(p, result.totalRepayment) * 1e-12;
  final rate = result.input.annualRatePercent / 1200;
  expect(result.monthlyEmi.isFinite, isTrue);
  expect(result.monthlyEmi, greaterThan(0));
  expect(result.totalInterest.isFinite, isTrue);
  expect(result.totalInterest, greaterThanOrEqualTo(0));
  expect(result.totalRepayment.isFinite, isTrue);
  expect(result.totalRepayment, greaterThanOrEqualTo(p - totalTolerance));
  expect(result.schedule.length, inInclusiveRange(1, result.normalizedMonths));
  expect(result.schedule.length, result.normalizedMonths);
  var prior = p;
  var principal = 0.0;
  var interest = 0.0;
  var payments = 0.0;
  for (final (index, row) in result.schedule.indexed) {
    expect(row.monthNumber, index + 1);
    expect(row.openingOutstanding, prior);
    for (final value in [
      row.openingOutstanding,
      row.payment,
      row.interestComponent,
      row.principalComponent,
      row.closingOutstanding
    ]) {
      expect(value.isFinite, isTrue);
      expect(value, greaterThanOrEqualTo(0));
    }
    expect(row.payment,
        closeTo(row.interestComponent + row.principalComponent, tolerance));
    expect(row.closingOutstanding,
        closeTo(row.openingOutstanding - row.principalComponent, tolerance));
    expect(
        row.closingOutstanding,
        closeTo(row.openingOutstanding + row.interestComponent - row.payment,
            tolerance));
    expect(row.interestComponent,
        closeTo(row.openingOutstanding * rate, tolerance));
    expect(row.payment,
        lessThanOrEqualTo(row.openingOutstanding + row.interestComponent));
    expect(row.payment, lessThanOrEqualTo(result.monthlyEmi));
    expect(row.payment, closeTo(result.monthlyEmi, tolerance));
    if (rate == 0) {
      expect(row.interestComponent, 0);
      expect(row.principalComponent, row.payment);
    }
    prior = row.closingOutstanding;
    principal += row.principalComponent;
    interest += row.interestComponent;
    payments += row.payment;
  }
  expect(result.schedule.last.closingOutstanding, 0);
  expect(principal, closeTo(p, tolerance));
  expect(interest, result.totalInterest);
  expect(payments, result.totalRepayment);
  expect(payments, closeTo(p + interest, totalTolerance));
}

void main() {
  const calculator = EmiCalculator();
  test('locked 120-month EMI, totals and first/final accounting rows', () {
    final result = calculator.calculate(input());
    verify(result);
    expect(result.monthlyEmi, closeTo(12398.5688874511, 1e-7));
    expect(result.totalInterest, closeTo(487828.27, .005));
    expect(result.totalRepayment, closeTo(1487828.27, .005));
    final first = result.schedule.first;
    expect(first.openingOutstanding, 1000000);
    expect(first.payment, closeTo(12398.57, .005));
    expect(first.interestComponent, closeTo(7083.33, .005));
    expect(first.principalComponent, closeTo(5315.24, .005));
    expect(first.closingOutstanding, closeTo(994684.76, .005));
    final last = result.schedule.last;
    expect(last.monthNumber, 120);
    expect(last.openingOutstanding, closeTo(12311.36, .005));
    expect(last.payment, closeTo(12398.57, .005));
    expect(last.interestComponent, closeTo(87.21, .005));
    expect(last.principalComponent, closeTo(12311.36, .005));
    expect(last.closingOutstanding, 0);
  });

  test('10 years and 120 months produce identical outputs and every row', () {
    final months = calculator.calculate(input());
    final years =
        calculator.calculate(input(tenure: 10, unit: TenureUnit.years));
    verify(years);
    expect(years.normalizedMonths, 120);
    expect(years.monthlyEmi, months.monthlyEmi);
    expect(years.totalInterest, months.totalInterest);
    expect(years.totalRepayment, months.totalRepayment);
    for (var i = 0; i < 120; i++) {
      final a = months.schedule[i];
      final b = years.schedule[i];
      expect([
        a.monthNumber,
        a.openingOutstanding,
        a.payment,
        a.interestComponent,
        a.principalComponent,
        a.closingOutstanding
      ], [
        b.monthNumber,
        b.openingOutstanding,
        b.payment,
        b.interestComponent,
        b.principalComponent,
        b.closingOutstanding
      ]);
    }
  });

  test('zero interest has 12 rows and principal-only repayment', () {
    final result =
        calculator.calculate(input(principal: 100000, tenure: 12, rate: 0));
    verify(result);
    expect(result.monthlyEmi, closeTo(8333.333333333, 1e-8));
    expect(result.totalInterest, 0);
    expect(result.totalRepayment, closeTo(100000, 1e-8));
  });

  test('one month pays exactly principal plus monthly interest', () {
    final result =
        calculator.calculate(input(principal: 100000, tenure: 1, rate: 12));
    verify(result);
    expect(result.monthlyEmi, closeTo(101000, 1e-8));
    expect(result.totalInterest, 1000);
    expect(result.schedule.single.principalComponent, 100000);
    expect(result.totalRepayment, closeTo(101000, 1e-8));
  });

  test('decimal principal/rate preserve full precision', () {
    final result = calculator
        .calculate(input(principal: 123456.78, tenure: 1, rate: 8.375));
    verify(result);
    expect(result.monthlyEmi, closeTo(123456.78 * (1 + 8.375 / 1200), 1e-8));
  });

  for (final unit in TenureUnit.values) {
    for (final tenure
        in unit == TenureUnit.months ? [1, 12, 120, 600] : [1, 10, 50]) {
      test('$tenure ${unit.name} normalizes and satisfies all invariants', () {
        final result = calculator.calculate(input(tenure: tenure, unit: unit));
        expect(result.normalizedMonths,
            unit == TenureUnit.months ? tenure : tenure * 12);
        verify(result);
      });
    }
  }

  test(
      'maximum amount, tenure and rate close with no material final adjustment',
      () {
    final result = calculator.calculate(
        input(principal: 1e10, tenure: 50, unit: TenureUnit.years, rate: 30));
    verify(result);
    expect(result.schedule.length, 600);
    expect(result.schedule.last.payment, closeTo(result.monthlyEmi, .01));
  });

  test('tiny positive rate is continuous with zero', () {
    final result = calculator.calculate(input(rate: 1e-12));
    verify(result);
    expect(result.monthlyEmi, closeTo(1000000 / 120, 1e-7));
    expect(result.totalInterest, greaterThan(0));
  });

  test('schedule is an immutable snapshot', () {
    final result = calculator.calculate(input());
    expect(result.schedule.clear, throwsUnsupportedError);
    expect(() => result.schedule[0] = result.schedule.last,
        throwsUnsupportedError);
    final rows = result.schedule.toList();
    final copy = EmiResult(
        input: result.input, monthlyEmi: result.monthlyEmi, schedule: rows);
    rows.clear();
    expect(copy.schedule.length, 120);
  });

  for (final (index, bad) in [
    input(principal: 0),
    input(principal: -1),
    input(principal: double.nan),
    input(principal: double.infinity),
    input(principal: 10000000001),
    input(tenure: 0),
    input(tenure: -1),
    input(tenure: 601),
    input(tenure: 0, unit: TenureUnit.years),
    input(tenure: -1, unit: TenureUnit.years),
    input(tenure: 51, unit: TenureUnit.years),
    input(rate: -1),
    input(rate: double.nan),
    input(rate: double.infinity),
    input(rate: 30.01),
    input(principal: double.minPositive, tenure: 600, rate: 0),
  ].indexed) {
    test('invalid domain input $index fails safely', () {
      expect(
          () => calculator.calculate(bad),
          throwsA(isA<EmiInputException>().having((e) => e.toString(),
              'safe message', 'Invalid EMI calculator input')));
    });
  }

  test(
      '180 deterministic boundary combinations preserve the accounting contract',
      () {
    for (final principal in [0.01, 1.0, 123456.78, 1e10]) {
      for (final tenure in [1, 2, 12, 120, 599, 600]) {
        for (final rate in [0.0, 1e-12, .00001, 8.375, 30.0]) {
          verify(calculator.calculate(
              input(principal: principal, tenure: tenure, rate: rate)));
          if (tenure % 12 == 0) {
            verify(calculator.calculate(input(
                principal: principal,
                tenure: tenure ~/ 12,
                unit: TenureUnit.years,
                rate: rate)));
          }
        }
      }
    }
  });
}
