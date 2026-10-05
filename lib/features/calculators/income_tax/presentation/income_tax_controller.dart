import 'package:flutter/foundation.dart';
import '../domain/exact_amount.dart';
import '../domain/income_tax_engine.dart';
import '../domain/tax_rules.dart';
import '../models/tax_input.dart';
import '../models/tax_result.dart';
import '../models/guided_deductions.dart';

final class HraDraft {
  HraDraft(this.id, Map<String, String> values)
      : values = Map.unmodifiable(values);
  final int id;
  final Map<String, String> values;
}

final class GuidedDraft {
  GuidedDraft(this.id, Map<String, String> values)
      : values = Map.unmodifiable(values);
  final int id;
  final Map<String, String> values;
}

final class IncomeTaxController extends ChangeNotifier {
  TaxYear _year = TaxYear.ty2026;
  TaxAge _age = TaxAge.below60;
  TaxMode _mode = TaxMode.normal;
  final _values = <TaxAmountField, String>{};
  final _confirmations = <TaxConfirmation>{};
  final _unsupported = <UnsupportedTaxCase>{};
  final _pending = <PendingTaxFeature>{};
  final _hra = <HraDraft>[];
  final _policies = <GuidedDraft>[];
  final _employers = <GuidedDraft>[];
  HousingPaymentKind _housingKind = HousingPaymentKind.governmentOrBank;
  int _nextId = 0, _generation = 0, _educationYear = 1;
  TaxOutcome? _outcome;
  TaxYear get year => _year;
  TaxAge get age => _age;
  TaxMode get mode => _mode;
  TaxRulePack get pack => TaxRulePack.forYear(_year);
  TaxOutcome? get outcome => _outcome;
  int get generation => _generation;
  int get educationYear => _educationYear;
  List<HraDraft> get hra => List.unmodifiable(_hra);
  List<GuidedDraft> get policies => List.unmodifiable(_policies);
  List<GuidedDraft> get employers => List.unmodifiable(_employers);
  HousingPaymentKind get housingKind => _housingKind;
  void setHousingKind(HousingPaymentKind kind) {
    _housingKind = kind;
    _changed();
  }

  void addPolicy() {
    _policies.add(GuidedDraft(_nextId++, {}));
    _changed();
  }

  void addEmployer() {
    _employers.add(GuidedDraft(_nextId++, {}));
    _changed();
  }

  void changeGuided(bool policy, int id, String field, String value) {
    final rows = policy ? _policies : _employers;
    final index = rows.indexWhere((p) => p.id == id);
    rows[index] = GuidedDraft(id, {...rows[index].values, field: value});
    _changed();
  }

  void removeGuided(bool policy, int id) {
    (policy ? _policies : _employers).removeWhere((p) => p.id == id);
    _changed();
  }

  String value(TaxAmountField field) => _values[field] ?? '';
  bool confirmed(TaxConfirmation flag) => _confirmations.contains(flag);
  bool unsupported(UnsupportedTaxCase flag) => _unsupported.contains(flag);
  bool pending(PendingTaxFeature field) => _pending.contains(field);
  void setPending(PendingTaxFeature field, bool value) {
    value ? _pending.add(field) : _pending.remove(field);
    _changed();
  }

  bool hasValue(TaxAmountField field) =>
      value(field).trim().isNotEmpty && value(field).trim() != '0';
  void _changed() {
    _outcome = null;
    notifyListeners();
  }

  void setAmount(TaxAmountField field, String value) {
    _values[field] = value;
    _changed();
  }

  void setConfirmation(TaxConfirmation flag, bool value) {
    value ? _confirmations.add(flag) : _confirmations.remove(flag);
    _changed();
  }

  void setUnsupported(UnsupportedTaxCase flag, bool value) {
    value ? _unsupported.add(flag) : _unsupported.remove(flag);
    _changed();
  }

  void setYear(TaxYear year) {
    if (_year == year) return;
    _year = year;
    // Financial entries stay visible. All eligibility facts must be reconfirmed.
    _confirmations.removeAll({
      TaxConfirmation.residentOrdinarilyResidentIndividual,
      TaxConfirmation.scopeChecklistReviewed,
      TaxConfirmation.ageForSelectedYear,
      TaxConfirmation.salaryDefinition,
      TaxConfirmation.depositEligibility,
      TaxConfirmation.individualPostOfficeAccount,
      TaxConfirmation.investmentEligibility,
      TaxConfirmation.npsEligibility,
      TaxConfirmation.taxablePerquisitesIncluded,
      TaxConfirmation.healthEligiblePayments,
      TaxConfirmation.educationEligible,
      TaxConfirmation.equityStcgEligible,
      TaxConfirmation.equityLtcgEligible,
      TaxConfirmation.ordinaryCompanyDividends,
      TaxConfirmation.completedFullyOwnedProperties,
      TaxConfirmation.annualValueVerified,
      TaxConfirmation.nscEligibility,
      TaxConfirmation.bankFiveYearEligible,
      TaxConfirmation.postFiveYearEligible,
      TaxConfirmation.scssEligibleAtOpening,
      TaxConfirmation.sukanyaChildOneEligible,
      TaxConfirmation.sukanyaChildTwoEligible,
      TaxConfirmation.sukanyaDistinctChildren,
      TaxConfirmation.investmentAmountsExclusive,
      TaxConfirmation.housingPurchaseEligible,
      TaxConfirmation.tuitionChildOneEligible,
      TaxConfirmation.tuitionChildTwoEligible,
    });
    _changed();
  }

  void setAge(TaxAge age) {
    _age = age;
    _confirmations.remove(TaxConfirmation.ageForSelectedYear);
    _changed();
  }

  void setMode(TaxMode mode) {
    _mode = mode;
    notifyListeners();
  }

  void setEducationYear(int year) {
    _educationYear = year;
    _changed();
  }

  static const advancedFields = {
    TaxAmountField.professionalTax,
    TaxAmountField.employerNps,
    TaxAmountField.employerSalaryBase,
    TaxAmountField.otherInterest,
    TaxAmountField.dividends,
    TaxAmountField.familyPension,
    TaxAmountField.educationInterest,
    TaxAmountField.selfOccupiedInterest,
    TaxAmountField.grossAnnualValue,
    TaxAmountField.municipalTax,
    TaxAmountField.letOutInterest,
    TaxAmountField.equityStcg,
    TaxAmountField.equityLtcg,
    TaxAmountField.tds,
    TaxAmountField.tcs,
    TaxAmountField.advanceTax,
    TaxAmountField.selfAssessmentTax,
  };
  bool get hasAdvancedData =>
      _hra.isNotEmpty ||
      _employers.isNotEmpty ||
      _pending.contains(PendingTaxFeature.multipleEmployerNps) ||
      advancedFields.any(hasValue);
  bool get showAdvanced => mode == TaxMode.advanced || hasAdvancedData;
  void addHra() {
    final start = year == TaxYear.fy2025 ? 2025 : 2026;
    _hra.add(HraDraft(_nextId++, {
      'start': '$start-04-01',
      'end': '${start + 1}-03-31',
      'city': 'Mumbai'
    }));
    _changed();
  }

  void changeHra(int id, String field, String value) {
    final index = _hra.indexWhere((p) => p.id == id);
    _hra[index] = HraDraft(id, {..._hra[index].values, field: value});
    _changed();
  }

  void removeHra(int id) {
    _hra.removeWhere((p) => p.id == id);
    _changed();
  }

  void calculate() {
    final issues = <String>[];
    final amounts = <TaxAmountField, Exact>{};
    for (final entry in _values.entries) {
      if (entry.value.trim().isEmpty) continue;
      try {
        amounts[entry.key] = Exact.parse(entry.value);
      } on FormatException {
        issues.add(
            '${entry.key.name}: enter non-negative rupees with at most two paise digits, without commas.');
      }
    }
    if (_values.containsKey(TaxAmountField.employerNps)) {
      amounts.putIfAbsent(TaxAmountField.employerSalaryBase, () => Exact.zero);
    }
    final periods = <HraPeriod>[];
    final life = <LifePremium>[];
    final employers = <EmployerNps>[];
    DateTime date(String text) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
        throw const FormatException();
      }
      final parsed = DateTime.parse('${text}T00:00:00Z');
      if (parsed.toIso8601String().substring(0, 10) != text) {
        throw const FormatException();
      }
      return parsed;
    }

    for (final policy in [true, false]) {
      for (final row in policy ? _policies : _employers) {
        try {
          Exact amount(String key) => Exact.parse(
              (row.values[key] ?? '').trim().isEmpty ? '0' : row.values[key]!);
          bool yes(String key) => row.values[key] == 'yes';
          if (policy) {
            life.add(LifePremium(
                paid: amount('paid'),
                assured: amount('assured'),
                issued: date(row.values['issued'] ?? ''),
                selfSpouseOrChild: yes('family'),
                qualifyingDisabilityOrAilment: yes('special')));
          } else {
            employers.add(EmployerNps(
                contribution: amount('contribution'),
                salaryBase: amount('base'),
                government: yes('government'),
                alreadyInGrossSalary: yes('included')));
          }
        } on FormatException {
          issues.add(
              '${policy ? 'Life policy' : 'Employer'} ${row.id + 1}: check amounts and date.');
        }
      }
    }
    final start = DateTime.utc(year == TaxYear.fy2025 ? 2025 : 2026, 4, 1);
    for (final p in _hra) {
      try {
        int day(String key) {
          final text = p.values[key] ?? '';
          if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
            throw const FormatException();
          }
          final date = DateTime.parse('${text}T00:00:00Z');
          if (date.toIso8601String().substring(0, 10) != text) {
            throw const FormatException();
          }
          return date.difference(start).inDays + 1;
        }

        Exact amount(String key) => Exact.parse(
            (p.values[key] ?? '').trim().isEmpty ? '0' : p.values[key]!);
        periods.add(HraPeriod(
            firstDay: day('start'),
            lastDay: day('end'),
            city: p.values['city'] ?? 'Other',
            basic: amount('basic'),
            eligibleDa: amount('da'),
            turnoverCommission: amount('commission'),
            actualHra: amount('hra'),
            rent: amount('rent')));
      } on FormatException {
        issues.add(
            'HRA period ${p.id + 1}: check dates (YYYY-MM-DD) and amounts.');
      }
    }
    _outcome = issues.isNotEmpty
        ? TaxInvalidInput(issues)
        : const IncomeTaxEngine().calculate(TaxInput(
            year: year,
            age: age,
            amounts: amounts,
            confirmations: _confirmations,
            unsupported: _unsupported,
            pending: _pending,
            hraPeriods: periods,
            lifePremiums: life,
            additionalEmployers: employers,
            housingPaymentKind: housingKind,
            educationRepaymentYear: educationYear));
    notifyListeners();
  }

  void reset() {
    _values.clear();
    _confirmations.clear();
    _unsupported.clear();
    _pending.clear();
    _hra.clear();
    _policies.clear();
    _employers.clear();
    _housingKind = HousingPaymentKind.governmentOrBank;
    _year = TaxYear.ty2026;
    _age = TaxAge.below60;
    _mode = TaxMode.normal;
    _educationYear = 1;
    _generation++;
    _changed();
  }
}
