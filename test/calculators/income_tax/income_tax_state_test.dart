import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/domain/exact_amount.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/domain/income_tax_engine.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/domain/tax_exemptions.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/models/tax_input.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/models/tax_result.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/presentation/income_tax_controller.dart';
import 'income_tax_engine_test.dart' as fixtures;

Exact e(String text) => Exact.parse(text);
void main() {
  for (final year in TaxYear.values) {
    test(
        '${year.name} property limits intra/inter-head and disclosed unabsorbed loss',
        () {
      final values = {
        TaxAmountField.salary: '1500000',
        TaxAmountField.selfOccupiedInterest: '250000',
        TaxAmountField.grossAnnualValue: '300000',
        TaxAmountField.municipalTax: '20000',
        TaxAmountField.letOutInterest: '100000'
      };
      final flags = {
        TaxConfirmation.selfLoanAcquisitionConstruction,
        TaxConfirmation.selfLoanCompletedWithinFiveYears,
        TaxConfirmation.interestCertificate,
        TaxConfirmation.selfLoanAfterApril1999
      };
      final r = fixtures.compute(year, values, flags: flags);
      expect(r.oldRegime.totalIncome, e('1346000'));
      expect(r.newRegime.totalIncome, e('1521000'));
      final repair = fixtures.compute(year, values);
      expect(repair.oldRegime.totalIncome, e('1516000'));
      final loss = fixtures.compute(year, {
        ...values,
        TaxAmountField.selfOccupiedInterest: '0',
        TaxAmountField.letOutInterest: '600000'
      });
      expect(loss.oldRegime.totalIncome, e('1250000'));
      expect(loss.newRegime.totalIncome, e('1425000'));
      expect(
          loss.oldRegime.trace
              .firstWhere((r) =>
                  r.label == 'House-property loss unabsorbed / disallowed')
              .amount,
          e('204000'));
      expect(
          loss.newRegime.trace
              .firstWhere((r) =>
                  r.label == 'House-property loss unabsorbed / disallowed')
              .amount,
          e('404000'));
      final dateTest = fixtures.compute(
          year,
          {
            TaxAmountField.salary: '1500000',
            TaxAmountField.selfOccupiedInterest: '250000'
          },
          flags: flags.difference({TaxConfirmation.selfLoanAfterApril1999}));
      expect(dateTest.oldRegime.totalIncome,
          e(year == TaxYear.fy2025 ? '1420000' : '1250000'));
      final mixed = const IncomeTaxEngine().calculate(fixtures.input(
          year, {...values, TaxAmountField.equityStcg: '100000'},
          flags: flags));
      expect(mixed, isA<TaxNotYetVerified>());
      expect((mixed as TaxNotYetVerified).dependencies,
          contains('IT-PROPERTY-LOSS-ALLOCATION'));
    });
    test('${year.name} HRA city period and salary inclusion', () {
      HraPeriod period(
              {int first = 1, int last = 365, String city = 'Hyderabad'}) =>
          HraPeriod(
              firstDay: first,
              lastDay: last,
              city: city,
              basic: e('600000'),
              eligibleDa: e('0'),
              turnoverCommission: e('0'),
              actualHra: e('300000'),
              rent: e('400000'));
      expect(TaxExemptions.hra(period(), year),
          e(year == TaxYear.fy2025 ? '240000' : '300000'));
      expect(TaxExemptions.hra(period(city: 'Mumbai'), year), e('300000'));
      expect(TaxExemptions.hra(period(city: 'Other'), year), e('240000'));
      final r = const IncomeTaxEngine().calculate(TaxInput(
          year: year,
          age: TaxAge.below60,
          confirmations: fixtures.confirmed,
          amounts: {
            TaxAmountField.salary: e('1800000')
          },
          hraPeriods: [
            period(first: 1, last: 180),
            period(first: 181, last: 365, city: 'Mumbai')
          ])) as TaxComparison;
      expect(r.oldRegime.totalIncome,
          e(year == TaxYear.fy2025 ? '1210000' : '1150000'));
      expect(r.newRegime.totalIncome, e('1725000'));
      final overlap = const IncomeTaxEngine().calculate(TaxInput(
          year: year,
          age: TaxAge.below60,
          confirmations: fixtures.confirmed,
          amounts: {
            TaxAmountField.salary: e('1800000')
          },
          hraPeriods: [
            period(first: 1, last: 181),
            period(first: 181, last: 365)
          ]));
      expect(overlap, isA<TaxInvalidInput>());
    });
  }
  test(
      'controller mode equivalence retention staleness reconfirmation and reset',
      () {
    final c = IncomeTaxController();
    addTearDown(c.dispose);
    expect(
        c.year, TaxYear.ty2026); // Supported current tax year is the default.
    c.setYear(TaxYear.fy2025); // Exercise a real year transition below.
    for (final f in fixtures.confirmed) {
      c.setConfirmation(f, true);
    }
    c.setAmount(TaxAmountField.salary, '1500000');
    c.calculate();
    final normal = c.outcome as TaxComparison;
    c.setMode(TaxMode.advanced);
    c.calculate();
    expect((c.outcome as TaxComparison).newRegime.liability,
        normal.newRegime.liability);
    c.setAmount(TaxAmountField.dividends, '12345');
    expect(c.outcome, isNull);
    c.setMode(TaxMode.normal);
    expect(c.showAdvanced, isTrue);
    expect(c.value(TaxAmountField.dividends), '12345');
    c.setConfirmation(TaxConfirmation.employerNpsAlreadyInSalary, true);
    c.setYear(TaxYear.ty2026);
    expect(c.value(TaxAmountField.salary), '1500000');
    expect(c.confirmed(TaxConfirmation.employerNpsAlreadyInSalary), isTrue);
    c.calculate();
    expect(c.outcome, isA<TaxInvalidInput>());
    c.reset();
    expect(c.outcome, isNull);
    expect(c.showAdvanced, isFalse);
    expect(c.value(TaxAmountField.salary), isEmpty);
  });
  test('malformed HRA dates and amounts never disappear into zero', () {
    final c = IncomeTaxController();
    addTearDown(c.dispose);
    for (final f in fixtures.confirmed) {
      c.setConfirmation(f, true);
    }
    c.setAmount(TaxAmountField.salary, 'NaN');
    c.calculate();
    expect(c.outcome, isA<TaxInvalidInput>());
    c.setAmount(TaxAmountField.salary, '1500000');
    c.addHra();
    c.changeHra(c.hra.single.id, 'start', '2025-02-30');
    c.calculate();
    expect(c.outcome, isA<TaxInvalidInput>());
    c.removeHra(c.hra.single.id);
    c.setPending(PendingTaxFeature.additional80cInstruments, true);
    c.calculate();
    expect(c.outcome, isA<TaxNotYetVerified>());
    expect(() => c.hra.clear(), throwsUnsupportedError);
  });
  test(
      'unverified interest exemptions and separate employer limits fail closed',
      () {
    for (final feature in PendingTaxFeature.values) {
      final result = const IncomeTaxEngine().calculate(TaxInput(
          year: TaxYear.fy2025,
          age: TaxAge.below60,
          pending: {feature},
          amounts: {TaxAmountField.salary: e('1500000')}));
      expect(result, isA<TaxNotYetVerified>());
    }
    final c = IncomeTaxController();
    addTearDown(c.dispose);
    c.setMode(TaxMode.advanced);
    c.setPending(PendingTaxFeature.multipleEmployerNps, true);
    c.setMode(TaxMode.normal);
    expect(c.showAdvanced, isTrue);
  });
  test('employer NPS prevents selecting the nonemployee own-NPS percentage',
      () {
    final result =
        const IncomeTaxEngine().calculate(fixtures.input(TaxYear.fy2025, {
      TaxAmountField.salary: '1500000',
      TaxAmountField.employerNps: '100000',
      TaxAmountField.ownNpsTotal: '200000',
      TaxAmountField.employerSalaryBase: '1000000',
      TaxAmountField.npsSalaryBase: '1000000',
    }));
    expect(result, isA<TaxInvalidInput>());
  });
}
