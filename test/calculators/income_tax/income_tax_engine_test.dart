import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/domain/exact_amount.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/domain/income_tax_engine.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/domain/tax_rules.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/models/tax_input.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/models/tax_result.dart';

const confirmed = {
  TaxConfirmation.residentOrdinarilyResidentIndividual,
  TaxConfirmation.scopeChecklistReviewed,
  TaxConfirmation.ageForSelectedYear,
  TaxConfirmation.salaryDefinition,
  TaxConfirmation.equityStcgEligible,
  TaxConfirmation.equityLtcgEligible,
  TaxConfirmation.depositEligibility,
  TaxConfirmation.investmentEligibility,
  TaxConfirmation.npsEligibility,
  TaxConfirmation.healthEligiblePayments,
  TaxConfirmation.educationEligible,
  TaxConfirmation.taxablePerquisitesIncluded,
  TaxConfirmation.ordinaryCompanyDividends,
  TaxConfirmation.completedFullyOwnedProperties,
  TaxConfirmation.annualValueVerified,
};
Exact e(String value) {
  final p = value.split('/');
  return p.length == 2
      ? Exact(BigInt.parse(p[0]), BigInt.parse(p[1]))
      : (RegExp(r'^\d+$').hasMatch(value)
          ? Exact(BigInt.parse(value))
          : Exact.parse(value));
}

TaxInput input(TaxYear year, Map<TaxAmountField, String> amounts,
        {TaxAge age = TaxAge.below60,
        Set<TaxConfirmation> flags = const {},
        int educationYear = 1}) =>
    TaxInput(
        year: year,
        age: age,
        amounts: amounts.map((k, v) => MapEntry(k, e(v))),
        confirmations: {...confirmed, ...flags},
        educationRepaymentYear: educationYear);
TaxComparison compute(TaxYear year, Map<TaxAmountField, String> amounts,
        {TaxAge age = TaxAge.below60,
        Set<TaxConfirmation> flags = const {},
        int educationYear = 1}) =>
    const IncomeTaxEngine().calculate(input(year, amounts,
        age: age, flags: flags, educationYear: educationYear)) as TaxComparison;

void main() {
  final fixtures = jsonDecode(
      File('test/calculators/income_tax/fixtures/statutory_goldens.json')
          .readAsStringSync()) as Map<String, dynamic>;
  for (final year in TaxYear.values) {
    group(year.name, () {
      for (final row in fixtures['vectors'] as List<dynamic>) {
        test('independent golden ${row['id']}', () {
          final comparison = compute(year, {
            row['kind'] == 'ltcg'
                ? TaxAmountField.equityLtcg
                : TaxAmountField.otherInterest: row['input'] as String,
          });
          final result = row['regime'] == 'old'
              ? comparison.oldRegime
              : comparison.newRegime;
          final actual = {
            'totalIncome': result.totalIncome,
            'tax': result.incomeTax,
            'rebate': result.rebate,
            'rebateRelief': result.rebateRelief,
            'surcharge': result.surcharge,
            'surchargeRelief': result.surchargeRelief,
            'cess': result.cess,
            'liability': result.liability
          };
          for (final entry in actual.entries) {
            expect(entry.value, e(row[entry.key] as String), reason: entry.key);
          }
          expect(result.ordinaryIncome + result.stcg + result.ltcg,
              result.totalIncome);
          expect(
              result.incomeTax -
                  result.rebate -
                  result.rebateRelief +
                  result.surcharge +
                  result.cess,
              result.exactLiability);
          expect(result.trace.map((t) => t.stage).toSet(),
              containsAll(TaxStage.values));
        });
      }
      test('salary acceptance vectors and one standard deduction', () {
        final c = compute(year, {TaxAmountField.salary: '1500000'});
        expect(c.oldRegime.liability, e('257400'));
        expect(c.newRegime.liability, e('97500'));
        expect(
            compute(year, {TaxAmountField.salary: '1275000'})
                .newRegime
                .liability,
            e('0'));
        final r = compute(year, {TaxAmountField.salary: '1285000'}).newRegime;
        expect(r.totalIncome, e('1210000'));
        expect(r.liability, e('10400'));
        for (final amount in ['0', '100', '49999', '50000', '74999', '75000']) {
          final low = compute(year, {TaxAmountField.salary: amount});
          expect(low.oldRegime.totalIncome.isNegative, isFalse);
          expect(low.newRegime.totalIncome, e('0'));
        }
      });
      test('special tax survives new rebate; old ST and LT restrictions differ',
          () {
        expect(
            compute(year, {
              TaxAmountField.otherInterest: '1100000',
              TaxAmountField.equityStcg: '100000'
            }).newRegime.liability,
            e('20800'));
        final st = compute(year, {TaxAmountField.equityStcg: '300000'});
        expect(st.oldRegime.incomeTax, e('10000'));
        expect(st.oldRegime.liability, e('0'));
        final lt = compute(year, {TaxAmountField.equityLtcg: '500000'});
        expect(lt.oldRegime.rebate, e('0'));
        expect(lt.oldRegime.liability, e('16250'));
        final both = compute(year, {
          TaxAmountField.otherInterest: '600000',
          TaxAmountField.equityStcg: '100000',
          TaxAmountField.equityLtcg: '200000'
        });
        expect(both.newRegime.liability, e('30550'));
      });
      test('age bands, family versus employment pension', () {
        expect(
            compute(year, {TaxAmountField.otherInterest: '600000'},
                    age: TaxAge.below60)
                .oldRegime
                .liability,
            e('33800'));
        expect(
            compute(year, {TaxAmountField.otherInterest: '600000'},
                    age: TaxAge.from60to79)
                .oldRegime
                .liability,
            e('31200'));
        expect(
            compute(year, {TaxAmountField.otherInterest: '600000'},
                    age: TaxAge.atLeast80)
                .oldRegime
                .liability,
            e('20800'));
        final r = compute(year, {
          TaxAmountField.salary: '40000',
          TaxAmountField.familyPension: '90000'
        });
        expect(r.oldRegime.totalIncome, e('75000'));
        expect(r.newRegime.totalIncome, e('65000'));
      });
      test('deductions combined cap and restricted income', () {
        final r = compute(year, {
          TaxAmountField.salary: '1500000',
          TaxAmountField.epf: '80000',
          TaxAmountField.ppf: '80000'
        });
        expect(r.oldRegime.totalIncome, e('1300000'));
        expect(r.newRegime.totalIncome, e('1425000'));
        final pure = compute(year, {
          TaxAmountField.equityLtcg: '1000000',
          TaxAmountField.ppf: '150000'
        });
        expect(pure.oldRegime.totalIncome, e('1000000'));
        expect(
            pure.oldRegime.deductions
                .firstWhere((d) => d.label == 'ppf')
                .allowed,
            e('0'));
      });
      test('NPS included once; employer percentage and own allocations', () {
        final raw = {
          TaxAmountField.salary: '1500000',
          TaxAmountField.employerNps: '140000',
          TaxAmountField.employerSalaryBase: '1000000'
        };
        final private = compute(year, raw);
        expect(private.oldRegime.totalIncome, e('1490000'));
        expect(private.newRegime.totalIncome, e('1425000'));
        final gov =
            compute(year, raw, flags: {TaxConfirmation.governmentEmployer});
        expect(gov.oldRegime.totalIncome, e('1450000'));
        final included = compute(
            year, {...raw, TaxAmountField.salary: '1640000'},
            flags: {TaxConfirmation.employerNpsAlreadyInSalary});
        expect(included.oldRegime.liability, private.oldRegime.liability);
        expect(included.newRegime.liability, private.newRegime.liability);
        final own = compute(year, {
          TaxAmountField.salary: '1500000',
          TaxAmountField.npsSalaryBase: '800000',
          TaxAmountField.ownNpsTotal: '200000'
        }, flags: {
          TaxConfirmation.npsEmployee
        });
        expect(own.oldRegime.totalIncome, e('1320000'));
        final ownRows = own.oldRegime.deductions.where((d) =>
            d.label.contains('own NPS') || d.label.startsWith('Own NPS'));
        expect(
            ownRows.fold(Exact.zero, (sum, d) => sum + d.entered), e('200000'));
        expect(
            ownRows.fold(Exact.zero, (sum, d) => sum + d.allowed), e('130000'));
      });
      test('health shared checkup ceiling and uninsured senior medical', () {
        final r = compute(year, {
          TaxAmountField.salary: '1500000',
          TaxAmountField.familyInsurance: '24000',
          TaxAmountField.familyCheckup: '4000',
          TaxAmountField.parentInsurance: '24000',
          TaxAmountField.parentCheckup: '4000'
        });
        expect(r.oldRegime.totalIncome, e('1400000'));
        final shared = compute(year, {
          TaxAmountField.salary: '1500000',
          TaxAmountField.familyCheckup: '4000',
          TaxAmountField.parentCheckup: '4000'
        });
        expect(shared.oldRegime.totalIncome, e('1445000'));
        final med = {
          TaxAmountField.salary: '1500000',
          TaxAmountField.familyMedical: '60000'
        };
        expect(
            compute(year, med,
                    flags: {TaxConfirmation.familyUninsuredResidentSenior})
                .oldRegime
                .totalIncome,
            e('1400000'));
        expect(compute(year, med).oldRegime.totalIncome, e('1450000'));
      });
      test('education year eight/nine and eligible interest categories', () {
        final ed = {
          TaxAmountField.salary: '1500000',
          TaxAmountField.educationInterest: '50000'
        };
        expect(compute(year, ed, educationYear: 8).oldRegime.totalIncome,
            e('1400000'));
        expect(compute(year, ed, educationYear: 9).oldRegime.totalIncome,
            e('1450000'));
        final interest = {
          TaxAmountField.savingsInterest: '20000',
          TaxAmountField.depositInterest: '60000',
          TaxAmountField.otherInterest: '70000'
        };
        expect(compute(year, interest).oldRegime.totalIncome, e('140000'));
        expect(
            compute(year, interest, age: TaxAge.from60to79)
                .oldRegime
                .totalIncome,
            e('100000'));
        expect(
            compute(year, interest, age: TaxAge.atLeast80)
                .newRegime
                .totalIncome,
            e('150000'));
      });
      test('credits balance refund and zero', () {
        final r = compute(year, {
          TaxAmountField.salary: '1500000',
          TaxAmountField.tds: '95000'
        }).newRegime;
        expect(r.payable, e('2500'));
        expect(r.refund, e('0'));
        expect(
            compute(year, {
              TaxAmountField.salary: '1500000',
              TaxAmountField.tds: '100000'
            }).newRegime.refund,
            e('2500'));
        expect(
            compute(year, {
              TaxAmountField.salary: '1500000',
              TaxAmountField.tcs: '50000',
              TaxAmountField.advanceTax: '40000',
              TaxAmountField.selfAssessmentTax: '7500'
            }).newRegime.balance,
            e('0'));
      });
      test('unverified dependencies suppress the entire comparison', () {
        for (final pair in [
          (
            {
              TaxAmountField.otherInterest: '100000',
              TaxAmountField.equityStcg: '250000',
              TaxAmountField.equityLtcg: '200000'
            },
            'IT-GAINS-ALLOCATION'
          ),
          (
            {
              TaxAmountField.salary: '2000000',
              TaxAmountField.equityLtcg: '4000000'
            },
            'IT-SURCHARGE-MIXED'
          ),
          (
            {
              TaxAmountField.salary: '25000000',
              TaxAmountField.dividends: '100000'
            },
            'IT-DIVIDEND-SURCHARGE'
          ),
          ({TaxAmountField.municipalTax: '100000'}, 'IT-PROPERTY-NEGATIVE-NAV'),
          (
            {
              TaxAmountField.otherInterest: '0.01',
              TaxAmountField.equityLtcg: '800003'
            },
            'IT-ROUND-COMPONENTS'
          ),
        ]) {
          final r = const IncomeTaxEngine().calculate(input(year, pair.$1));
          expect(r, isA<TaxNotYetVerified>());
          expect((r as TaxNotYetVerified).dependencies, contains(pair.$2));
        }
      });
    });
  }
  test('exact arithmetic, paise rounding, India formatting, immutable models',
      () {
    for (final pair in [
      ('4.99', '0'),
      ('5', '10'),
      ('14.99', '10'),
      ('15', '20'),
      ('999999999999.99', '1000000000000')
    ]) {
      expect(e(pair.$1).statutoryTen(), e(pair.$2));
    }
    expect(e('100').ratio(1, 3).ratio(3), e('100'));
    expect(e('999999999999.99').ratio(999999, 100).ratio(100, 999999),
        e('999999999999.99'));
    expect(e('12345678.12').inr, '₹1,23,45,678.12');
    for (final bad in [
      '-1',
      'NaN',
      'Infinity',
      '1e9',
      '1,000',
      '1.001',
      '1000000000000'
    ]) {
      expect(() => Exact.parse(bad), throwsFormatException);
    }
    final r = compute(TaxYear.fy2025, {TaxAmountField.salary: '1500000'});
    expect(() => r.oldRegime.trace.clear(), throwsUnsupportedError);
    expect(() => r.oldRegime.deductions.clear(), throwsUnsupportedError);
    expect(TaxRulePack.fy2025.version, isNot(TaxRulePack.ty2026.version));
    expect(TaxRulePack.fy2025.period, '1 April 2025 – 31 March 2026');
  });
  test('typed unsupported and invalid input', () {
    for (final c in UnsupportedTaxCase.values) {
      expect(
          const IncomeTaxEngine().calculate(TaxInput(
              year: TaxYear.fy2025, age: TaxAge.below60, unsupported: {c})),
          isA<TaxUnsupported>());
    }
    expect(
        const IncomeTaxEngine()
            .calculate(TaxInput(year: TaxYear.fy2025, age: TaxAge.below60)),
        isA<TaxInvalidInput>());
    expect(
        const IncomeTaxEngine().calculate(TaxInput(
            year: TaxYear.fy2025,
            age: TaxAge.below60,
            confirmations: confirmed,
            amounts: {TaxAmountField.salary: -e('1')})),
        isA<TaxInvalidInput>());
  });
  test(
      'B2 static formula reproduction remains separate from statutory acceptance',
      () {
    // STATIC_FORMULA_REPRODUCTION: inspected I303 omits P3, not a workbook execution.
    // Fixed cell inputs from retained v1.3/v1.4 formula chains; no cached values.
    for (final pair in [('400000', '598830'), ('250000', '618330')]) {
      final income = e('5000800'), cut = e('5000000'), basic = e(pair.$1);
      final current = (income - basic - e('125000')).ratio(1, 8);
      final staticCutoff = (cut - basic).ratio(1, 8);
      final staticPrecess =
          current.ratio(110, 100).min(staticCutoff + income - cut);
      expect(staticPrecess.ratio(104, 100).statutoryTen(), e(pair.$2));
    }
    final law = compute(TaxYear.fy2025, {TaxAmountField.equityLtcg: '5000800'});
    expect(law.newRegime.liability, e('582580'));
    expect(law.oldRegime.liability, e('602080'));
  });
}
