import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/domain/sip_calculator.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/models/sip.dart';

SipInput input(
        {double initial = 100000,
        double monthly = 10000,
        int tenure = 120,
        SipTenureUnit unit = SipTenureUnit.months,
        double roi = 12,
        double lump = 0,
        DateTime? lumpDate,
        DateTime? start}) =>
    SipInput(
      initialInvestment: initial,
      monthlySip: monthly,
      tenure: tenure,
      tenureUnit: unit,
      annualRoiPercent: roi,
      lumpSum: lump,
      lumpSumDate: lumpDate,
      startDate: start ?? DateTime(2026, 10, 5),
    );

void verify(SipResult result) {
  final value = result.input;
  final tolerance = math.max(1.0, result.totalFundValue) * 1e-12;
  expect(result.monthlyFlows.length, value.normalizedMonths);
  expect(result.totalFundValue, result.monthlyFlows.last.closingValue);
  expect(
      result.amountInvested,
      closeTo(
          value.initialInvestment +
              value.monthlySip * value.normalizedMonths +
              value.lumpSum,
          math.max(1, result.amountInvested) * 1e-12));
  expect(
      result.estimatedReturns, result.totalFundValue - result.amountInvested);
  for (final amount in [
    result.totalFundValue,
    result.amountInvested,
    result.estimatedReturns
  ]) {
    expect(amount.isFinite, isTrue);
    expect(amount, greaterThanOrEqualTo(0));
  }
  var previous = value.initialInvestment;
  var returns = 0.0;
  var contributions = value.initialInvestment;
  var lumpTotal = 0.0;
  for (final (i, row) in result.monthlyFlows.indexed) {
    expect(row.monthNumber, i + 1);
    expect(row.openingValue, previous);
    expect(row.sipContribution, value.monthlySip);
    for (final amount in [
      row.openingValue,
      row.sipContribution,
      row.lumpSumContribution,
      row.returnAmount,
      row.closingValue
    ]) {
      expect(amount.isFinite, isTrue);
      expect(amount, greaterThanOrEqualTo(0));
    }
    final funded =
        row.openingValue + row.sipContribution + row.lumpSumContribution;
    expect(row.returnAmount,
        closeTo(funded * value.annualRoiPercent / 1200, tolerance));
    expect(row.closingValue, closeTo(funded + row.returnAmount, tolerance));
    expect(row.closingValue, greaterThanOrEqualTo(row.openingValue));
    contributions += row.sipContribution + row.lumpSumContribution;
    returns += row.returnAmount;
    lumpTotal += row.lumpSumContribution;
    previous = row.closingValue;
    if (value.annualRoiPercent == 0) expect(row.returnAmount, 0);
  }
  expect(contributions, result.amountInvested);
  expect(lumpTotal, value.lumpSum);
  expect(returns, closeTo(result.estimatedReturns, tolerance));
  if (value.annualRoiPercent == 0) {
    expect(result.totalFundValue, result.amountInvested);
    expect(result.estimatedReturns, 0);
  }
}

void main() {
  const calculator = SipCalculator();

  test('locked 120 periods uses an independent exact rational cash-flow oracle',
      () {
    final result = calculator
        .calculate(input(lump: 200000, lumpDate: DateTime(2031, 10, 20)));
    verify(result);
    // Independent future-value oracle: compound each dated contribution directly
    // as an exact rational number. No recursive balance or product helper.
    final q = BigInt.from(101);
    final base = BigInt.from(100);
    final denominator = base.pow(120);
    var numerator = BigInt.from(100000) * q.pow(120);
    for (var remaining = 1; remaining <= 120; remaining++) {
      numerator +=
          BigInt.from(10000) * q.pow(remaining) * base.pow(120 - remaining);
    }
    // October 2031 is period 61, so the lump sum earns exactly 60 returns.
    numerator += BigInt.from(200000) * q.pow(60) * base.pow(60);
    final expected = numerator.toDouble() / denominator.toDouble();
    final expectedPaise =
        (numerator * base + denominator ~/ BigInt.two) ~/ denominator;
    expect(expectedPaise, BigInt.from(301676879));
    expect(result.totalFundValue, closeTo(expected, 1e-7));
    expect(result.totalFundValue, closeTo(3016768.792689586, 1e-7));
    expect(result.amountInvested, 1500000);
    expect(result.estimatedReturns, closeTo(1516768.792689586, 1e-7));
    expect(result.input.planEndDate, DateTime.utc(2036, 9, 30));
    expect(result.monthlyFlows.first.closingValue, 111100);
    expect(result.monthlyFlows[59].lumpSumContribution, 0);
    expect(result.monthlyFlows[60].lumpSumContribution, 200000);
  });

  test('zero initial investment and no lump sum still invest SIP before return',
      () {
    final result = calculator.calculate(input(initial: 0, tenure: 1));
    verify(result);
    expect(result.totalFundValue, 10100);
    expect(result.amountInvested, 10000);
    expect(result.estimatedReturns, 100);
  });

  test(
      'zero ROI produces exact principal-only fund value including decimal cash flows',
      () {
    final result = calculator.calculate(input(
        initial: 123.45,
        monthly: 10.01,
        roi: 0,
        lump: 456.78,
        lumpDate: DateTime(2030, 1, 1)));
    verify(result);
    expect(result.totalFundValue, result.amountInvested);
    expect(result.estimatedReturns, 0);
  });

  test('12 months and one year have identical values and every cash-flow field',
      () {
    final a = calculator.calculate(
        input(tenure: 12, lump: 1000, lumpDate: DateTime(2027, 3, 15)));
    final b = calculator.calculate(input(
        tenure: 1,
        unit: SipTenureUnit.years,
        lump: 1000,
        lumpDate: DateTime(2027, 3, 15)));
    verify(a);
    verify(b);
    expect(a.totalFundValue, b.totalFundValue);
    expect(a.amountInvested, b.amountInvested);
    expect(a.estimatedReturns, b.estimatedReturns);
    for (var i = 0; i < 12; i++) {
      final x = a.monthlyFlows[i];
      final y = b.monthlyFlows[i];
      expect([
        x.monthNumber,
        x.openingValue,
        x.sipContribution,
        x.lumpSumContribution,
        x.returnAmount,
        x.closingValue
      ], [
        y.monthNumber,
        y.openingValue,
        y.sipContribution,
        y.lumpSumContribution,
        y.returnAmount,
        y.closingValue
      ]);
    }
  });

  for (final (date, month, returns) in [
    (DateTime(2026, 10, 5), 1, 12),
    (DateTime(2027, 4, 15), 7, 6),
    (DateTime(2027, 9, 30), 12, 1),
  ]) {
    test('lump sum in period $month earns only $returns monthly returns', () {
      final result =
          calculator.calculate(input(tenure: 12, lump: 200000, lumpDate: date));
      final without = calculator.calculate(input(tenure: 12));
      verify(result);
      expect(result.monthlyFlows[month - 1].lumpSumContribution, 200000);
      expect(
          result.monthlyFlows
              .where((row) => row.lumpSumContribution > 0)
              .length,
          1);
      expect(result.totalFundValue - without.totalFundValue,
          closeTo(200000 * math.pow(1.01, returns), 1e-7));
    });
  }

  test(
      'same calendar month earns same return; time of day does not affect dates',
      () {
    final first = calculator.calculate(
        input(tenure: 12, lump: 100, lumpDate: DateTime(2027, 1, 1, 23)));
    final last = calculator.calculate(
        input(tenure: 12, lump: 100, lumpDate: DateTime.utc(2027, 1, 31)));
    expect(first.totalFundValue, last.totalFundValue);
    final sameDay = calculator.calculate(input(
        tenure: 1,
        start: DateTime(2026, 10, 5, 23, 59),
        lump: 100,
        lumpDate: DateTime.utc(2026, 10, 5)));
    verify(sameDay);
  });

  test('zero lump sum needs no date and ignores irrelevant out-of-range dates',
      () {
    final expected = calculator.calculate(input());
    final ignored = calculator.calculate(input(lumpDate: DateTime(1900)));
    verify(ignored);
    expect(ignored.totalFundValue, expected.totalFundValue);
  });

  for (final date in [
    null,
    DateTime(2026, 10, 4),
    DateTime(2026, 9, 30),
    DateTime(2027, 10, 1)
  ]) {
    test('missing or outside date $date is rejected for a positive lump sum',
        () {
      expect(
          () => calculator
              .calculate(input(tenure: 12, lump: 100, lumpDate: date)),
          throwsA(isA<SipInputException>().having((e) => e.errors, 'date error',
              contains(SipInputField.lumpSumDate))));
    });
  }

  for (final (start, months, end) in [
    (DateTime(2024, 2, 29), 1, DateTime.utc(2024, 2, 29)),
    (DateTime(2026, 1, 31), 2, DateTime.utc(2026, 2, 28)),
    (DateTime(2026, 12, 31), 2, DateTime.utc(2027, 1, 31)),
  ]) {
    test('calendar end handles leap/month/year boundary $start', () {
      final result = calculator.calculate(
          input(start: start, tenure: months, lump: 100, lumpDate: end));
      verify(result);
      expect(result.input.planEndDate, end);
      expect(result.monthlyFlows.last.lumpSumContribution, 100);
    });
  }

  test('decimal ROI and contributions stay unrounded', () {
    final result = calculator.calculate(
        input(initial: 100.25, monthly: 33.33, tenure: 1, roi: 8.375));
    verify(result);
    expect(result.totalFundValue,
        closeTo((100.25 + 33.33) * (1 + 8.375 / 1200), 1e-10));
  });

  test('600 months / 50 years at maximum amounts and ROI remain finite', () {
    final months = calculator.calculate(input(
        initial: 1e10,
        monthly: 1e10,
        tenure: 600,
        roi: 30,
        lump: 1e10,
        lumpDate: DateTime(2026, 10, 5)));
    final years = calculator.calculate(input(
        initial: 1e10,
        monthly: 1e10,
        tenure: 50,
        unit: SipTenureUnit.years,
        roi: 30,
        lump: 1e10,
        lumpDate: DateTime(2026, 10, 5)));
    verify(months);
    verify(years);
    expect(months.totalFundValue, years.totalFundValue);
    expect(years.monthlyFlows.length, 600);
  });

  test('result cash flows are immutable snapshots', () {
    final result = calculator.calculate(input());
    expect(result.monthlyFlows.clear, throwsUnsupportedError);
    expect(() => result.monthlyFlows[0] = result.monthlyFlows.last,
        throwsUnsupportedError);
    final rows = result.monthlyFlows.toList();
    final copy = SipResult(
        input: result.input,
        amountInvested: result.amountInvested,
        monthlyFlows: rows);
    rows.clear();
    expect(copy.monthlyFlows.length, 120);
  });

  for (final (i, bad) in [
    input(initial: -1),
    input(initial: double.nan),
    input(initial: double.infinity),
    input(initial: 1e10 + 1),
    input(monthly: 0),
    input(monthly: -1),
    input(monthly: double.nan),
    input(monthly: double.infinity),
    input(monthly: 1e10 + 1),
    input(lump: -1),
    input(lump: double.nan),
    input(lump: double.infinity),
    input(lump: 1e10 + 1),
    input(roi: -1),
    input(roi: double.nan),
    input(roi: double.infinity),
    input(roi: 30.01),
    input(tenure: 0),
    input(tenure: -1),
    input(tenure: 601),
    input(tenure: 0, unit: SipTenureUnit.years),
    input(tenure: -1, unit: SipTenureUnit.years),
    input(tenure: 51, unit: SipTenureUnit.years),
  ].indexed) {
    test('invalid domain input $i is rejected with safe errors', () {
      expect(
          () => calculator.calculate(bad),
          throwsA(isA<SipInputException>().having((e) => e.toString(),
              'safe diagnostic', 'Invalid SIP calculator input')));
    });
  }

  test('576 boundary combinations reconcile every cash flow and summary', () {
    for (final initial in [0.0, 123456.78, 1e10]) {
      for (final monthly in [.01, 10000.0, 1e10]) {
        for (final roi in [0.0, 1e-12, 12.5, 30.0]) {
          for (final months in [1, 12, 120, 600]) {
            for (final offset in [-1, 0, months ~/ 2, months - 1]) {
              verify(calculator.calculate(input(
                  initial: initial,
                  monthly: monthly,
                  roi: roi,
                  tenure: months,
                  lump: offset < 0 ? 0 : 54321.98,
                  lumpDate:
                      offset < 0 ? null : DateTime(2026, 10 + offset, 5))));
            }
          }
        }
      }
    }
  });
}
