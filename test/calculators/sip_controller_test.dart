import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/domain/sip_calculator.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/models/sip.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/sip_controller.dart';

void fill(SipController controller,
    {String tenure = '120',
    String lump = '200000',
    String date = '2031-10-20'}) {
  for (final (field, value) in [
    (SipInputField.initialInvestment, '100000'),
    (SipInputField.monthlySip, '10000'),
    (SipInputField.tenure, tenure),
    (SipInputField.annualRoi, '12'),
    (SipInputField.lumpSum, lump),
    (SipInputField.lumpSumDate, date),
  ]) {
    controller.update(field, value);
  }
}

void main() {
  late SipController controller;
  setUp(() => controller = SipController(clock: () => DateTime(2026, 10, 5)));
  tearDown(() => controller.dispose());

  test(
      'explicit calculation captures clock once; all edits clear result and timestamp',
      () {
    var reads = 0;
    final timed = SipController(clock: () {
      reads++;
      return DateTime(2026, 10, 5, 17);
    });
    addTearDown(timed.dispose);
    fill(timed);
    expect(timed.result, isNull);
    expect(reads, 0);
    timed.calculate();
    expect(reads, 1);
    expect(timed.calculatedAt, DateTime(2026, 10, 5, 17));
    expect(timed.result!.input.planStartDate, DateTime.utc(2026, 10, 5));
    expect(timed.result!.totalFundValue, closeTo(3016768.792689586, 1e-7));
    for (final field in SipInputField.values) {
      timed.update(field, timed.value(field));
      expect(timed.result, isNull);
      expect(timed.calculatedAt, isNull);
      expect(timed.calculationError, isNull);
      timed.calculate();
    }
    expect(reads, 7);
  });

  test(
      'new calculation revalidates selected date against the newly captured start',
      () {
    var now = DateTime(2026, 10, 5, 23);
    var reads = 0;
    final timed = SipController(clock: () {
      reads++;
      return now;
    });
    addTearDown(timed.dispose);
    fill(timed, date: '2026-10-05');
    timed.calculate();
    expect(timed.result, isNotNull);
    now = DateTime(2026, 10, 6);
    expect(timed.calculatedAt, DateTime(2026, 10, 5, 23));
    expect(reads, 1);
    timed.calculate();
    expect(reads, 2);
    expect(timed.result, isNull);
    expect(timed.calculatedAt, isNull);
    expect(timed.errors[SipInputField.lumpSumDate],
        'Date cannot be before the calculation date.');
  });

  test('unit switch clears tenure/error/result and never reinterprets it', () {
    fill(controller);
    controller.calculate();
    final monthlyResult = controller.result!;
    controller.changeTenureUnit(SipTenureUnit.years);
    expect(controller.value(SipInputField.tenure), '');
    expect(controller.value(SipInputField.lumpSumDate), '2031-10-20');
    expect(controller.result, isNull);
    expect(controller.calculatedAt, isNull);
    controller.calculate();
    expect(controller.errors[SipInputField.tenure], 'This field is required.');
    controller.changeTenureUnit(SipTenureUnit.months);
    expect(controller.errors, isEmpty);
    expect(controller.value(SipInputField.tenure), '');
    controller.changeTenureUnit(SipTenureUnit.years);
    controller.update(SipInputField.tenure, '10');
    controller.calculate();
    expect(controller.result!.totalFundValue, monthlyResult.totalFundValue);
    final result = controller.result;
    controller.changeTenureUnit(SipTenureUnit.years);
    expect(controller.result, same(result));
  });

  test(
      'zero optional amounts default; reset restores defaults and removes errors/results',
      () {
    expect(controller.value(SipInputField.initialInvestment), '0');
    expect(controller.value(SipInputField.lumpSum), '0');
    controller.calculate();
    expect(controller.errors.length, 3);
    expect(controller.errors.clear, throwsUnsupportedError);
    fill(controller);
    controller.calculate();
    controller.changeTenureUnit(SipTenureUnit.years);
    controller.reset();
    expect(controller.tenureUnit, SipTenureUnit.months);
    expect(controller.result, isNull);
    expect(controller.calculatedAt, isNull);
    expect(controller.errors, isEmpty);
    for (final field in SipInputField.values) {
      expect(
          controller.value(field),
          field == SipInputField.initialInvestment ||
                  field == SipInputField.lumpSum
              ? '0'
              : '');
    }
  });

  for (final unit in SipTenureUnit.values) {
    for (final tenure in unit == SipTenureUnit.months
        ? ['1', '12', '120', '600']
        : ['1', '10', '50']) {
      test('accept $tenure ${unit.name}', () {
        controller.changeTenureUnit(unit);
        fill(controller, tenure: tenure, lump: '0', date: '');
        controller.calculate();
        expect(controller.errors, isEmpty);
        expect(controller.result!.normalizedMonths,
            int.parse(tenure) * (unit == SipTenureUnit.years ? 12 : 1));
      });
    }
    for (final tenure in [
      '0',
      '-1',
      '1.5',
      '10.5',
      '12.0',
      '1e2',
      unit == SipTenureUnit.months ? '601' : '51'
    ]) {
      test('reject $tenure ${unit.name} without changing text', () {
        controller.changeTenureUnit(unit);
        fill(controller, tenure: tenure);
        controller.calculate();
        expect(controller.errors[SipInputField.tenure],
            SipCalculator.tenureError(unit));
        expect(controller.value(SipInputField.tenure), tenure);
        expect(controller.result, isNull);
      });
    }
  }

  for (final raw in [
    'NaN',
    'Infinity',
    '1e6',
    '₹100000',
    '1,00,000',
    '.',
    '--1',
    '9' * 65
  ]) {
    test('reject malformed decimal $raw in every amount/rate field', () {
      for (final field in [
        SipInputField.initialInvestment,
        SipInputField.monthlySip,
        SipInputField.annualRoi,
        SipInputField.lumpSum
      ]) {
        fill(controller);
        controller.update(field, raw);
        controller.calculate();
        expect(controller.errors[field],
            'Enter a plain number without commas or symbols.');
        expect(controller.value(field), raw);
        expect(controller.result, isNull);
      }
    });
  }

  for (final raw in [
    '2026-02-29',
    '2026-04-31',
    '2026-00-05',
    '2026-13-01',
    '2026-10-00',
    '0000-01-01',
    '05/10/2026',
    '2026-1-1',
    '2026-10-05T12:00:00Z'
  ]) {
    test('invalid date $raw is not silently normalized', () {
      fill(controller, date: raw);
      controller.calculate();
      expect(controller.errors[SipInputField.lumpSumDate],
          'Enter a real date as YYYY-MM-DD.');
      expect(controller.value(SipInputField.lumpSumDate), raw);
      expect(controller.result, isNull);
    });
  }

  test('real leap date parses strictly; surrounding whitespace preserved', () {
    expect(SipController.parseDate(' 2024-02-29 '), DateTime.utc(2024, 2, 29));
    fill(controller, date: ' 2031-10-20 ');
    controller.update(SipInputField.initialInvestment, ' 100000.25 ');
    controller.update(SipInputField.annualRoi, ' 8.375 ');
    controller.calculate();
    expect(controller.errors, isEmpty);
    expect(controller.result!.input.annualRoiPercent, 8.375);
    expect(controller.value(SipInputField.lumpSumDate), ' 2031-10-20 ');
  });

  test(
      'positive lump sum requires date; zero ignores empty or irrelevant date text',
      () {
    fill(controller, date: '');
    controller.calculate();
    expect(controller.errors[SipInputField.lumpSumDate],
        'Choose a date for the lump sum.');
    controller.update(SipInputField.lumpSum, '0');
    controller.calculate();
    expect(controller.errors, isEmpty);
    expect(controller.result!.input.lumpSumDate, isNull);
    controller.update(SipInputField.lumpSumDate, 'not a date');
    controller.calculate();
    expect(controller.errors, isEmpty);
    expect(controller.result!.input.lumpSumDate, isNull);
    controller.update(SipInputField.lumpSum, '100');
    controller.calculate();
    expect(controller.result, isNull);
    expect(controller.errors, contains(SipInputField.lumpSumDate));
  });

  test('before-start and after-tenure errors remain field-specific', () {
    for (final date in ['2026-10-04', '2036-10-01']) {
      fill(controller, date: date);
      controller.calculate();
      expect(controller.errors.keys, [SipInputField.lumpSumDate]);
      expect(controller.result, isNull);
      expect(controller.value(SipInputField.lumpSumDate), date);
    }
  });

  test('negative, zero SIP and over-limit values fail without clamping', () {
    for (final (field, value) in [
      (SipInputField.initialInvestment, '-1'),
      (SipInputField.initialInvestment, '10000000001'),
      (SipInputField.monthlySip, '0'),
      (SipInputField.monthlySip, '-1'),
      (SipInputField.monthlySip, '10000000001'),
      (SipInputField.lumpSum, '-1'),
      (SipInputField.lumpSum, '10000000001'),
      (SipInputField.annualRoi, '-1'),
      (SipInputField.annualRoi, '30.01'),
    ]) {
      fill(controller);
      controller.update(field, value);
      controller.calculate();
      expect(controller.errors, contains(field));
      expect(controller.value(field), value);
      expect(controller.result, isNull);
    }
  });
}
