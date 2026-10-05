import 'package:flutter/foundation.dart';

import '../domain/loan_part_payment_calculator.dart';
import '../models/loan_part_payment.dart';

/// Ephemeral screen-owned state. No persistence, services or telemetry.
class LoanPartPaymentController extends ChangeNotifier {
  final _calculator = const LoanPartPaymentCalculator();
  final _values = {for (final field in LoanInputField.values) field: ''};
  Map<LoanInputField, String> _errors = {};
  LoanPartPaymentResult? _result;

  Map<LoanInputField, String> get errors => Map.unmodifiable(_errors);
  LoanPartPaymentResult? get result => _result;

  void update(LoanInputField field, String value) {
    _values[field] = value;
    _result = null;
    _errors = {};
    notifyListeners();
  }

  void reset() {
    _values.updateAll((_, __) => '');
    _errors = {};
    _result = null;
    notifyListeners();
  }

  void calculate() {
    _result = null;
    _errors = {};
    final parsed = <LoanInputField, double>{};
    for (final field in LoanInputField.values) {
      final raw = _values[field]!.trim();
      if (raw.isEmpty) {
        _errors[field] = 'This field is required.';
        continue;
      }
      // Plain decimals only: no comma/currency rewriting, exponent, NaN or infinity.
      final pattern = field == LoanInputField.months
          ? RegExp(r'^\d+$')
          : RegExp(r'^-?(?:\d+(?:\.\d*)?|\.\d+)$');
      final number = double.tryParse(raw);
      if (raw.length > 64 ||
          !pattern.hasMatch(raw) ||
          number == null ||
          !number.isFinite) {
        _errors[field] = field == LoanInputField.months
            ? 'Enter a whole number from 1 to 600 months.'
            : 'Enter a plain number without commas or symbols.';
      } else {
        parsed[field] = number;
      }
    }
    // Validate complete fields too, while keeping syntax errors field-specific.
    final months = parsed[LoanInputField.months];
    if (months != null &&
        (months < 1 || months > LoanPartPaymentCalculator.maxMonths)) {
      _errors[LoanInputField.months] =
          'Enter a whole number from 1 to 600 months.';
    }
    if (_errors.isEmpty) {
      try {
        _result = _calculator.calculate(LoanPartPaymentInput(
          principal: parsed[LoanInputField.principal]!,
          months: months!.toInt(),
          annualRatePercent: parsed[LoanInputField.annualRate]!,
          partPayment: parsed[LoanInputField.partPayment]!,
        ));
      } on LoanInputException catch (error) {
        _errors = error.errors;
      }
    }
    notifyListeners();
  }
}
