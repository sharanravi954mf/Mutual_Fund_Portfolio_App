import 'package:flutter/foundation.dart';

import '../domain/emi_calculator.dart';
import '../models/emi.dart';

/// Screen-owned state; no persistence, services, network or telemetry.
class EmiController extends ChangeNotifier {
  EmiController(
      {DateTime Function()? clock,
      EmiCalculator calculator = const EmiCalculator()})
      : _clock = clock ?? DateTime.now,
        _calculator = calculator;
  final DateTime Function() _clock;
  final EmiCalculator _calculator;
  final _values = {for (final field in EmiInputField.values) field: ''};
  Map<EmiInputField, String> _errors = {};
  TenureUnit _tenureUnit = TenureUnit.months;
  EmiResult? _result;
  DateTime? _calculatedAt;
  String? _calculationError;

  Map<EmiInputField, String> get errors => Map.unmodifiable(_errors);
  String value(EmiInputField field) => _values[field]!;
  TenureUnit get tenureUnit => _tenureUnit;
  EmiResult? get result => _result;
  DateTime? get calculatedAt => _calculatedAt;
  String? get calculationError => _calculationError;

  void _invalidate() {
    _result = null;
    _calculatedAt = null;
    _calculationError = null;
  }

  void update(EmiInputField field, String value) {
    _values[field] = value;
    _errors = {};
    _invalidate();
    notifyListeners();
  }

  void changeTenureUnit(TenureUnit unit) {
    if (unit == _tenureUnit) return;
    _tenureUnit = unit;
    _values[EmiInputField.tenure] = '';
    _errors = {..._errors}..remove(EmiInputField.tenure);
    _invalidate();
    notifyListeners();
  }

  void reset() {
    _values.updateAll((_, __) => '');
    _tenureUnit = TenureUnit.months;
    _errors = {};
    _invalidate();
    notifyListeners();
  }

  void calculate() {
    final calculationTime = _clock();
    _invalidate();
    _errors = {};
    final parsed = <EmiInputField, double>{};
    for (final field in EmiInputField.values) {
      final raw = _values[field]!.trim();
      if (raw.isEmpty) {
        _errors[field] = 'This field is required.';
        continue;
      }
      final pattern = field == EmiInputField.tenure
          ? RegExp(r'^\d+$')
          : RegExp(r'^-?(?:\d+(?:\.\d*)?|\.\d+)$');
      final number = double.tryParse(raw);
      if (raw.length > 64 ||
          !pattern.hasMatch(raw) ||
          number == null ||
          !number.isFinite) {
        _errors[field] = field == EmiInputField.tenure
            ? EmiCalculator.tenureError(_tenureUnit)
            : 'Enter a plain number without commas or symbols.';
      } else {
        parsed[field] = number;
      }
    }
    final tenure = parsed[EmiInputField.tenure];
    final limit = _tenureUnit == TenureUnit.months
        ? EmiCalculator.maxMonths
        : EmiCalculator.maxYears;
    if (tenure != null && (tenure < 1 || tenure > limit)) {
      _errors[EmiInputField.tenure] = EmiCalculator.tenureError(_tenureUnit);
    }
    if (_errors.isEmpty) {
      try {
        _result = _calculator.calculate(EmiInput(
          principal: parsed[EmiInputField.principal]!,
          tenure: tenure!.toInt(),
          tenureUnit: _tenureUnit,
          annualRatePercent: parsed[EmiInputField.annualRate]!,
        ));
        _calculatedAt = calculationTime;
      } on EmiInputException catch (error) {
        _errors = error.errors;
      } on EmiCalculationException {
        _calculationError =
            'Unable to reconcile this estimate. Please check your inputs and try again.';
      }
    }
    notifyListeners();
  }
}
