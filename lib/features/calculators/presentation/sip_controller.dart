import 'package:flutter/foundation.dart';

import '../domain/sip_calculator.dart';
import '../models/sip.dart';

/// Ephemeral, screen-owned input state with one clock read per Calculate.
class SipController extends ChangeNotifier {
  SipController(
      {DateTime Function()? clock,
      SipCalculator calculator = const SipCalculator()})
      : _clock = clock ?? DateTime.now,
        _calculator = calculator;
  final DateTime Function() _clock;
  final SipCalculator _calculator;
  final _values = {
    for (final field in SipInputField.values) field: _defaultValue(field)
  };
  Map<SipInputField, String> _errors = {};
  SipTenureUnit _tenureUnit = SipTenureUnit.months;
  SipResult? _result;
  DateTime? _calculatedAt;
  String? _calculationError;

  static String _defaultValue(SipInputField field) =>
      field == SipInputField.initialInvestment || field == SipInputField.lumpSum
          ? '0'
          : '';
  Map<SipInputField, String> get errors => Map.unmodifiable(_errors);
  String value(SipInputField field) => _values[field]!;
  SipTenureUnit get tenureUnit => _tenureUnit;
  SipResult? get result => _result;
  DateTime? get calculatedAt => _calculatedAt;
  String? get calculationError => _calculationError;

  static DateTime? parseDate(String text) {
    final raw = text.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return null;
    final year = int.parse(raw.substring(0, 4));
    final month = int.parse(raw.substring(5, 7));
    final day = int.parse(raw.substring(8, 10));
    if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime.utc(year, month, day);
    // DateTime normalizes invalid days; reject that normalization explicitly.
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  void _invalidate() {
    _result = null;
    _calculatedAt = null;
    _calculationError = null;
  }

  void update(SipInputField field, String value) {
    _values[field] = value;
    _errors = {};
    _invalidate();
    notifyListeners();
  }

  void changeTenureUnit(SipTenureUnit unit) {
    if (unit == _tenureUnit) return;
    _tenureUnit = unit;
    _values[SipInputField.tenure] = '';
    _errors = {..._errors}..remove(SipInputField.tenure);
    _invalidate();
    notifyListeners();
  }

  void reset() {
    _values.updateAll((field, _) => _defaultValue(field));
    _tenureUnit = SipTenureUnit.months;
    _errors = {};
    _invalidate();
    notifyListeners();
  }

  void calculate() {
    final calculationTime = _clock();
    _invalidate();
    _errors = {};
    final parsed = <SipInputField, double>{};
    for (final field
        in SipInputField.values.where((f) => f != SipInputField.lumpSumDate)) {
      final raw = _values[field]!.trim();
      if (raw.isEmpty) {
        _errors[field] = 'This field is required.';
        continue;
      }
      final pattern = field == SipInputField.tenure
          ? RegExp(r'^\d+$')
          : RegExp(r'^-?(?:\d+(?:\.\d*)?|\.\d+)$');
      final number = double.tryParse(raw);
      if (raw.length > 64 ||
          !pattern.hasMatch(raw) ||
          number == null ||
          !number.isFinite) {
        _errors[field] = field == SipInputField.tenure
            ? SipCalculator.tenureError(_tenureUnit)
            : 'Enter a plain number without commas or symbols.';
      } else {
        parsed[field] = number;
      }
    }
    final tenure = parsed[SipInputField.tenure];
    final limit = _tenureUnit == SipTenureUnit.months
        ? SipCalculator.maxMonths
        : SipCalculator.maxYears;
    if (tenure != null && (tenure < 1 || tenure > limit)) {
      _errors[SipInputField.tenure] = SipCalculator.tenureError(_tenureUnit);
    }
    DateTime? lumpDate;
    if ((parsed[SipInputField.lumpSum] ?? 0) > 0) {
      final raw = _values[SipInputField.lumpSumDate]!;
      lumpDate = parseDate(raw);
      if (lumpDate == null) {
        _errors[SipInputField.lumpSumDate] = raw.trim().isEmpty
            ? 'Choose a date for the lump sum.'
            : 'Enter a real date as YYYY-MM-DD.';
      }
    }
    if (_errors.isEmpty) {
      try {
        _result = _calculator.calculate(SipInput(
          initialInvestment: parsed[SipInputField.initialInvestment]!,
          monthlySip: parsed[SipInputField.monthlySip]!,
          tenure: tenure!.toInt(),
          tenureUnit: _tenureUnit,
          annualRoiPercent: parsed[SipInputField.annualRoi]!,
          lumpSum: parsed[SipInputField.lumpSum]!,
          lumpSumDate: lumpDate,
          startDate: SipCalendar.dateOnly(calculationTime),
        ));
        _calculatedAt = calculationTime;
      } on SipInputException catch (error) {
        _errors = error.errors;
      } on SipCalculationException {
        _calculationError =
            'Unable to calculate this estimate. Please check your inputs and try again.';
      }
    }
    notifyListeners();
  }
}
