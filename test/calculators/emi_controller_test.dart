import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/domain/emi_calculator.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/models/emi.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/emi_controller.dart';

void fill(EmiController controller, {String tenure = '120'}) {
  controller.update(EmiInputField.principal, '1000000');
  controller.update(EmiInputField.tenure, tenure);
  controller.update(EmiInputField.annualRate, '8.5');
}

void main() {
  late EmiController controller;
  setUp(() => controller = EmiController());
  tearDown(() => controller.dispose());

  test(
      'explicit calculate, one clock capture, editing and reset clear stale state',
      () {
    var reads = 0;
    var now = DateTime(2026, 10, 5);
    final timed = EmiController(clock: () {
      reads++;
      return now;
    });
    addTearDown(timed.dispose);
    fill(timed);
    expect(timed.result, isNull);
    expect(reads, 0);
    timed.calculate();
    expect(timed.calculatedAt, now);
    expect(reads, 1);
    final previous = timed.result;
    now = DateTime(2026, 12, 31);
    expect(timed.calculatedAt, DateTime(2026, 10, 5));
    expect(timed.result, same(previous));
    expect(reads, 1);
    for (final field in EmiInputField.values) {
      timed.update(field, timed.value(field));
      expect(timed.result, isNull);
      expect(timed.calculatedAt, isNull);
      timed.calculate();
    }
    expect(reads, 4);
    expect(timed.calculatedAt, now);
    timed.reset();
    expect(timed.result, isNull);
    expect(timed.calculatedAt, isNull);
    expect(timed.errors, isEmpty);
    expect(EmiInputField.values.map(timed.value), everyElement(''));
  });

  test(
      'switching units clears tenure, validation, schedule and timestamp both ways',
      () {
    fill(controller);
    controller.calculate();
    controller.changeTenureUnit(TenureUnit.years);
    expect(controller.tenureUnit, TenureUnit.years);
    expect(controller.value(EmiInputField.tenure), '');
    expect(controller.value(EmiInputField.principal), '1000000');
    expect(controller.result, isNull);
    expect(controller.calculatedAt, isNull);
    controller.calculate();
    expect(controller.errors[EmiInputField.tenure], 'This field is required.');
    controller.changeTenureUnit(TenureUnit.months);
    expect(controller.errors, isEmpty);
    expect(controller.value(EmiInputField.tenure), '');
    fill(controller);
    controller.calculate();
    final result = controller.result;
    controller.changeTenureUnit(TenureUnit.months);
    expect(controller.result, same(result));
    controller.changeTenureUnit(TenureUnit.years);
    controller.update(EmiInputField.tenure, '10');
    controller.calculate();
    expect(controller.result!.monthlyEmi, result!.monthlyEmi);
    controller.reset();
    expect(controller.tenureUnit, TenureUnit.months);
  });

  for (final unit in TenureUnit.values) {
    for (final tenure in unit == TenureUnit.months
        ? ['1', '12', '120', '600']
        : ['1', '10', '50']) {
      test('accept $tenure ${unit.name}', () {
        controller.changeTenureUnit(unit);
        fill(controller, tenure: tenure);
        controller.calculate();
        expect(controller.errors, isEmpty);
        expect(controller.result!.normalizedMonths,
            int.parse(tenure) * (unit == TenureUnit.years ? 12 : 1));
      });
    }
    for (final tenure in [
      '0',
      '-1',
      '1.5',
      '10.5',
      '12.5',
      '1e2',
      '10 years',
      unit == TenureUnit.months ? '601' : '51'
    ]) {
      test('reject $tenure ${unit.name} without changing text', () {
        controller.changeTenureUnit(unit);
        fill(controller, tenure: tenure);
        controller.calculate();
        expect(controller.errors[EmiInputField.tenure],
            EmiCalculator.tenureError(unit));
        expect(controller.value(EmiInputField.tenure), tenure);
        expect(controller.result, isNull);
        expect(controller.calculatedAt, isNull);
      });
    }
  }

  test('empty fields required and errors immutable', () {
    controller.calculate();
    expect(controller.errors.values, everyElement('This field is required.'));
    expect(controller.errors.length, 3);
    expect(controller.errors.clear, throwsUnsupportedError);
  });

  for (final raw in [
    'NaN',
    'Infinity',
    '1e6',
    '₹100000',
    '1,00,000',
    'abc',
    '.',
    '--1',
    '9' * 65
  ]) {
    test('malformed decimal $raw rejected for principal and rate', () {
      for (final field in [EmiInputField.principal, EmiInputField.annualRate]) {
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

  test('valid decimal whitespace and zero interest accepted', () {
    fill(controller);
    controller.update(EmiInputField.principal, ' 123456.78 ');
    controller.update(EmiInputField.annualRate, ' 0.0 ');
    controller.calculate();
    expect(controller.errors, isEmpty);
    expect(controller.result!.totalInterest, 0);
    expect(controller.value(EmiInputField.principal), ' 123456.78 ');
  });

  test('invalid numeric ranges have explicit errors without clamping', () {
    for (final (field, value) in [
      (EmiInputField.principal, '0'),
      (EmiInputField.principal, '-1'),
      (EmiInputField.principal, '10000000001'),
      (EmiInputField.annualRate, '-1'),
      (EmiInputField.annualRate, '30.01')
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
