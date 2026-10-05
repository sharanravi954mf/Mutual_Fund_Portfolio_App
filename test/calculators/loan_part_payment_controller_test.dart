import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/domain/loan_part_payment_calculator.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/loan_part_payment_controller.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/models/loan_part_payment.dart';

class FailingCalculator extends LoanPartPaymentCalculator {
  @override
  LoanPartPaymentResult calculate(LoanPartPaymentInput input) =>
      throw const LoanCalculationException();
}

void main() {
  late LoanPartPaymentController controller;
  setUp(() => controller = LoanPartPaymentController());
  tearDown(() => controller.dispose());

  void valid() {
    for (final entry in {
      LoanInputField.principal: '1000000',
      LoanInputField.months: '120',
      LoanInputField.annualRate: '8.5',
      LoanInputField.partPayment: '100000'
    }.entries) {
      controller.update(entry.key, entry.value);
    }
  }

  test('clock captured once per Calculate and cleared with stale results', () {
    controller.dispose();
    var now = DateTime(2026, 10, 5);
    var reads = 0;
    controller = LoanPartPaymentController(clock: () {
      reads++;
      return now;
    });
    valid();
    controller.calculate();
    expect(reads, 1);
    expect(controller.calculatedAt, DateTime(2026, 10, 5));
    now = DateTime(2027, 1, 1);
    expect(controller.calculatedAt, DateTime(2026, 10, 5));
    controller.calculate();
    expect(reads, 2);
    expect(controller.calculatedAt, now);
    controller.update(LoanInputField.months, 'bad');
    expect(controller.calculatedAt, isNull);
    controller.calculate();
    expect(reads, 3);
    expect(controller.result, isNull);
    expect(controller.calculatedAt, isNull);
    valid();
    controller.calculate();
    controller.reset();
    expect(controller.calculatedAt, isNull);
  });

  test(
      'accounting invariant failure returns safe error and no result or timestamp',
      () {
    controller.dispose();
    controller = LoanPartPaymentController(calculator: FailingCalculator());
    valid();
    controller.calculate();
    expect(controller.result, isNull);
    expect(controller.calculatedAt, isNull);
    expect(controller.calculationError,
        'Unable to reconcile this estimate. Please check your inputs and try again.');
    expect(const LoanCalculationException().toString(),
        'Unable to reconcile the loan estimate');
    controller.update(LoanInputField.months, '12');
    expect(controller.calculationError, isNull);
    controller.calculate();
    expect(controller.calculationError, isNotNull);
    controller.reset();
    expect(controller.calculationError, isNull);
  });

  test('all fields required', () {
    controller.calculate();
    expect(controller.errors.length, 4);
    expect(controller.result, isNull);
  });

  for (final bad in [
    '',
    ' ',
    'NaN',
    'Infinity',
    '-Infinity',
    '1e6',
    '1,00,000',
    '₹100',
    '1.2.3',
    'abc',
    '9' * 65
  ]) {
    test('malformed decimal rejected: $bad', () {
      valid();
      controller.update(LoanInputField.principal, bad);
      controller.calculate();
      expect(controller.errors, contains(LoanInputField.principal));
      expect(controller.result, isNull);
    });
  }
  for (final bad in [
    '1.5',
    '12.0',
    '-1',
    '0',
    '601',
    '99999999999999999999999999'
  ]) {
    test('months must be bounded whole integer: $bad', () {
      valid();
      controller.update(LoanInputField.months, bad);
      controller.calculate();
      expect(controller.errors, contains(LoanInputField.months));
      expect(controller.result, isNull);
    });
  }

  test('plain decimal paste and surrounding whitespace supported', () {
    valid();
    controller.update(LoanInputField.principal, ' 1000000.25 ');
    controller.update(LoanInputField.annualRate, '.5');
    controller.update(LoanInputField.partPayment, '100000.75');
    controller.calculate();
    expect(controller.errors, isEmpty);
    expect(controller.result!.remainingPrincipal, 899999.5);
  });

  test('edit invalidates old result; failed recalculation keeps entries', () {
    valid();
    controller.calculate();
    expect(controller.result, isNotNull);
    controller.update(LoanInputField.partPayment, '1000001');
    expect(controller.result, isNull);
    controller.calculate();
    expect(controller.result, isNull);
    expect(controller.errors, contains(LoanInputField.partPayment));
    controller.update(LoanInputField.partPayment, '200000');
    controller.calculate();
    expect(controller.result!.remainingPrincipal, 800000);
  });

  test('reset clears values errors and results', () {
    valid();
    controller.calculate();
    controller.reset();
    expect(controller.result, isNull);
    expect(controller.errors, isEmpty);
    controller.calculate();
    expect(controller.errors.length, 4);
  });
}
