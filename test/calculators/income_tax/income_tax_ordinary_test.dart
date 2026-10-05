import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/domain/exact_amount.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/domain/income_tax_engine.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/models/tax_input.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/models/tax_result.dart';
import 'income_tax_guided_test.dart' as f;

// Independent hand vectors recorded before implementation in the source register:
// IT-ORDINARY-LOSS, IT-INTEREST-EXEMPTION. No production-generated expectations.
void main() {
  const engine = IncomeTaxEngine();
  for (final year in TaxYear.values) {
    for (final age in TaxAge.values) {
      test('${year.name} ${age.name} property loss preserves eligible interest',
          () {
        final r = engine.calculate(f.example(year, age: age, amounts: {
          TaxAmountField.savingsInterest: '12000',
          TaxAmountField.depositInterest: '60000',
          TaxAmountField.otherInterest: '5000',
          TaxAmountField.selfOccupiedInterest: '200000',
        }, flags: {
          TaxConfirmation.selfLoanAcquisitionConstruction,
          TaxConfirmation.selfLoanCompletedWithinFiveYears,
          TaxConfirmation.interestCertificate,
          TaxConfirmation.selfLoanAfterApril1999,
        })) as TaxComparison;
        final young = age == TaxAge.below60;
        expect(r.oldRegime.totalIncome, f.e(young ? '1317000' : '1277000'));
        expect(
            r.oldRegime.liability,
            f.e(switch (age) {
              TaxAge.below60 => '215900',
              TaxAge.from60to79 => '200820',
              TaxAge.atLeast80 => '190420'
            }));
        expect(r.newRegime.totalIncome, f.e('1502000'));
        expect(r.newRegime.liability, f.e('109510'));
      });
      for (final amount in [
        '0',
        '3499.99',
        '3500',
        '3500.01',
        '3504.99',
        '3505',
        '3505.01',
        '13500'
      ]) {
        test('${year.name} ${age.name} post-office exemption $amount', () {
          final r = engine.calculate(f.example(year,
                  age: age,
                  amounts: {TaxAmountField.postOfficeSavingsInterest: amount},
                  flags: {TaxConfirmation.individualPostOfficeAccount}))
              as TaxComparison;
          // Independent decimal comparison at the exemption / total-income boundary.
          final taxable = switch (amount) {
            '3500.01' => '0.01',
            '3504.99' => '4.99',
            '3505' => '5',
            '3505.01' => '5.01',
            '13500' => '10000',
            _ => '0'
          };
          final excluded = f.e(amount) - f.e(taxable);
          for (final estimate in [r.oldRegime, r.newRegime]) {
            expect(
                estimate.deductions
                    .singleWhere((d) => d.ruleId == 'IT-INTEREST-EXEMPTION')
                    .allowed,
                excluded);
          }
          expect(r.oldRegime.totalIncome, f.e('1450000'));
          expect(
              r.newRegime.totalIncome,
              f.e(switch (amount) {
                '3505' || '3505.01' => '1425010',
                '13500' => '1435000',
                _ => '1425000'
              }));
          expect(r.newRegime.liability,
              f.e(amount == '13500' ? '99060' : '97500'));
        });
      }
    }
    test(
        '${year.name} loss spills into interest only after other ordinary income',
        () {
      final r = engine.calculate(f.example(year, amounts: {
        TaxAmountField.salary: '0',
        TaxAmountField.savingsInterest: '20000',
        TaxAmountField.otherInterest: '15000',
        TaxAmountField.selfOccupiedInterest: '20000'
      })) as TaxComparison;
      expect(r.oldRegime.totalIncome, f.e('5000'));
      expect(r.newRegime.totalIncome, f.e('35000'));
      expect(
          r.oldRegime.deductions
              .singleWhere((d) => d.ruleId == 'IT-INTEREST-DEDUCTION')
              .allowed,
          f.e('10000'));
      expect(
          r.oldRegime.trace
              .singleWhere(
                  (d) => d.label == 'Loss allocated to eligible interest')
              .amount,
          f.e('5000'));
      expect(r.oldRegime.liability, Exact.zero);
    });
    test(
        '${year.name} salary loss and positive property net before interest deduction',
        () {
      final r = engine.calculate(f.example(year, amounts: {
        TaxAmountField.salary: '1000',
        TaxAmountField.professionalTax: '2000',
        TaxAmountField.savingsInterest: '100000',
        TaxAmountField.otherInterest: '600000',
        TaxAmountField.grossAnnualValue: '100000'
      })) as TaxComparison;
      expect(r.oldRegime.totalIncome, f.e('758000'));
      expect(r.oldRegime.liability, f.e('66660'));
      expect(r.newRegime.totalIncome, f.e('770000'));
      expect(r.newRegime.liability, Exact.zero);
    });
    test('${year.name} salary loss is limited to available positive heads', () {
      final r = engine.calculate(f.example(year, amounts: {
        TaxAmountField.salary: '1000',
        TaxAmountField.professionalTax: '2000',
        TaxAmountField.otherInterest: '1000'
      })) as TaxComparison;
      expect(r.oldRegime.totalIncome, Exact.zero);
      expect(
          r.oldRegime.trace
              .singleWhere((d) => d.label == 'Salary-head loss unabsorbed')
              .amount,
          f.e('1000'));
      expect(r.newRegime.totalIncome, f.e('1000'));
    });
    test(
        '${year.name} unresolved gain loss and account ownership suppress comparison',
        () {
      expect(
          engine.calculate(f.example(year, amounts: {
            TaxAmountField.salary: '1000',
            TaxAmountField.professionalTax: '2000',
            TaxAmountField.equityStcg: '100000'
          })),
          isA<TaxNotYetVerified>());
      expect(
          engine.calculate(f.example(year,
              amounts: {TaxAmountField.postOfficeSavingsInterest: '10000'})),
          isA<TaxInvalidInput>());
    });
  }
}
