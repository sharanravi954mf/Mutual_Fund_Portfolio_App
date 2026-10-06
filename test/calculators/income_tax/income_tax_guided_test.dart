import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/domain/exact_amount.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/domain/income_tax_engine.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/domain/tax_exemptions.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/models/guided_deductions.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/models/tax_input.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/models/tax_result.dart';
import 'income_tax_engine_test.dart' as f;

Exact e(String text) => Exact.parse(text);
const engine = IncomeTaxEngine();
TaxInput example(
  TaxYear year, {
  TaxAge age = TaxAge.below60,
  Map<TaxAmountField, String> amounts = const {},
  List<LifePremium> policies = const [],
  List<EmployerNps> employers = const [],
  Set<TaxConfirmation> flags = const {},
  HousingPaymentKind housing = HousingPaymentKind.governmentOrBank,
}) =>
    TaxInput(
        year: year,
        age: age,
        confirmations: {...f.confirmed, ...flags},
        amounts: {
          TaxAmountField.salary: e('1500000'),
          ...amounts.map((k, v) => MapEntry(k, e(v)))
        },
        lifePremiums: policies,
        additionalEmployers: employers,
        housingPaymentKind: housing);

void main() {
  for (final year in TaxYear.values) {
    test(
        '${year.name} declared deferred conditions atomically withhold both regimes',
        () {
      final nearby = engine.calculate(example(year));
      expect(nearby, isA<TaxComparison>());
      for (final pending in [
        PendingTaxFeature.additional80cInstruments,
        PendingTaxFeature.postOfficeSavingsExemption,
        PendingTaxFeature.deductionRecapture,
      ]) {
        final entered = example(year);
        final result = engine.calculate(TaxInput(
          year: year,
          age: TaxAge.below60,
          amounts: entered.amounts,
          confirmations: entered.confirmations,
          pending: {pending},
        ));
        expect(result, isA<TaxNotYetVerified>());
      }
    });
    for (final item in [
      (
        TaxAmountField.bankFiveYearDeposit,
        TaxConfirmation.bankFiveYearEligible,
        'IT-INVEST-BANK5'
      ),
      (
        TaxAmountField.postFiveYearDeposit,
        TaxConfirmation.postFiveYearEligible,
        'IT-INVEST-POST5'
      ),
      (
        TaxAmountField.scssDeposit,
        TaxConfirmation.scssEligibleAtOpening,
        'IT-INVEST-SCSS'
      ),
      (
        TaxAmountField.sukanyaChildOne,
        TaxConfirmation.sukanyaChildOneEligible,
        'IT-INVEST-SUKANYA'
      ),
    ]) {
      test('${year.name} ${item.$3} independently expected Old/New tax', () {
        final r = engine.calculate(example(year,
                age: item.$1 == TaxAmountField.scssDeposit
                    ? TaxAge.from60to79
                    : TaxAge.below60,
                amounts: {item.$1: '100000'},
                flags: {item.$2, TaxConfirmation.investmentAmountsExclusive}))
            as TaxComparison;
        expect(r.oldRegime.liability,
            e(item.$1 == TaxAmountField.scssDeposit ? '223600' : '226200'));
        expect(r.newRegime.liability, e('97500'));
      });
      test('${year.name} ${item.$3} missing eligibility fails closed', () {
        final outcome = engine.calculate(example(year,
            age: item.$1 == TaxAmountField.scssDeposit
                ? TaxAge.from60to79
                : TaxAge.below60,
            amounts: {item.$1: '100000'}));
        expect(outcome, isA<TaxInvalidInput>());
      });
    }
    test(
        '${year.name} four instruments share one Old cap and are denied in New',
        () {
      final r =
          engine.calculate(example(year, age: TaxAge.from60to79, amounts: {
        TaxAmountField.bankFiveYearDeposit: '100000',
        TaxAmountField.postFiveYearDeposit: '100000',
        TaxAmountField.scssDeposit: '100000',
        TaxAmountField.sukanyaChildOne: '100000',
      }, flags: {
        TaxConfirmation.bankFiveYearEligible,
        TaxConfirmation.postFiveYearEligible,
        TaxConfirmation.scssEligibleAtOpening,
        TaxConfirmation.sukanyaChildOneEligible,
        TaxConfirmation.investmentAmountsExclusive,
      })) as TaxComparison;
      expect(
          r.oldRegime.deductions
              .where((d) => d.ruleId.startsWith('IT-INVEST'))
              .fold(Exact.zero, (sum, d) => sum + d.allowed),
          e('150000'));
      expect(
          r.newRegime.deductions
              .where((d) => d.ruleId.startsWith('IT-INVEST'))
              .fold(Exact.zero, (sum, d) => sum + d.allowed),
          Exact.zero);
    });
    test('${year.name} Sukanya second child needs separate beneficiary', () {
      final r = engine.calculate(example(year, amounts: {
        TaxAmountField.sukanyaChildOne: '25000',
        TaxAmountField.sukanyaChildTwo: '25000',
      }, flags: {
        TaxConfirmation.sukanyaChildOneEligible,
        TaxConfirmation.sukanyaChildTwoEligible,
        TaxConfirmation.investmentAmountsExclusive
      }));
      expect(r, isA<TaxInvalidInput>());
    });
    for (final (field, amount, confirmation) in [
      (
        TaxAmountField.bankFiveYearDeposit,
        '99',
        TaxConfirmation.bankFiveYearEligible
      ),
      (
        TaxAmountField.bankFiveYearDeposit,
        '101',
        TaxConfirmation.bankFiveYearEligible
      ),
      (
        TaxAmountField.bankFiveYearDeposit,
        '150100',
        TaxConfirmation.bankFiveYearEligible
      ),
      (
        TaxAmountField.postFiveYearDeposit,
        '999',
        TaxConfirmation.postFiveYearEligible
      ),
      (
        TaxAmountField.postFiveYearDeposit,
        '1050',
        TaxConfirmation.postFiveYearEligible
      ),
      (
        TaxAmountField.scssDeposit,
        '999',
        TaxConfirmation.scssEligibleAtOpening
      ),
      (
        TaxAmountField.scssDeposit,
        '3001000',
        TaxConfirmation.scssEligibleAtOpening
      ),
      (
        TaxAmountField.sukanyaChildOne,
        '249',
        TaxConfirmation.sukanyaChildOneEligible
      ),
      (
        TaxAmountField.sukanyaChildOne,
        '275',
        TaxConfirmation.sukanyaChildOneEligible
      ),
      (
        TaxAmountField.sukanyaChildOne,
        '150050',
        TaxConfirmation.sukanyaChildOneEligible
      ),
    ]) {
      test('${year.name} ${field.name} rejects scheme amount $amount', () {
        final result = engine.calculate(example(year,
            age: field == TaxAmountField.scssDeposit
                ? TaxAge.from60to79
                : TaxAge.below60,
            amounts: {field: amount},
            flags: {confirmation, TaxConfirmation.investmentAmountsExclusive}));
        expect(result, isA<TaxInvalidInput>());
      });
    }
    test(
        '${year.name} bank scheme contribution and deposit interest remain separate',
        () {
      final result = engine.calculate(example(year, amounts: {
        TaxAmountField.bankFiveYearDeposit: '100000',
        TaxAmountField.depositInterest: '10000',
      }, flags: {
        TaxConfirmation.bankFiveYearEligible,
        TaxConfirmation.investmentAmountsExclusive,
      })) as TaxComparison;
      expect(result.oldRegime.liability, e('229320'));
      expect(result.newRegime.liability, e('99060'));
    });
    test(
        '${year.name} new scheme shares the EPF cap and eligible-income ceiling',
        () {
      final capped = engine.calculate(example(year, amounts: {
        TaxAmountField.epf: '100000',
        TaxAmountField.bankFiveYearDeposit: '100000',
      }, flags: {
        TaxConfirmation.bankFiveYearEligible,
        TaxConfirmation.investmentAmountsExclusive,
      })) as TaxComparison;
      expect(capped.oldRegime.totalIncome, e('1300000'));
      expect(capped.oldRegime.liability, e('210600'));
      expect(capped.newRegime.liability, e('97500'));
      final noEligibleIncome = engine.calculate(example(year, amounts: {
        TaxAmountField.salary: '0',
        TaxAmountField.bankFiveYearDeposit: '100000',
      }, flags: {
        TaxConfirmation.bankFiveYearEligible,
        TaxConfirmation.investmentAmountsExclusive,
      })) as TaxComparison;
      expect(noEligibleIncome.oldRegime.totalIncome, Exact.zero);
      expect(noEligibleIncome.oldRegime.liability, Exact.zero);
      expect(
          noEligibleIncome.oldRegime.deductions
              .where((d) => d.ruleId == 'IT-INVEST-BANK5')
              .single
              .allowed,
          Exact.zero);
    });
    test('${year.name} SCSS below60 exception is withheld', () {
      final r = engine.calculate(example(year, amounts: {
        TaxAmountField.scssDeposit: '100000',
      }, flags: {
        TaxConfirmation.scssEligibleAtOpening,
        TaxConfirmation.investmentAmountsExclusive
      }));
      expect(r, isA<TaxNotYetVerified>());
    });
  }
  for (final year in TaxYear.values) {
    test('${year.name} IT-REVIEW-001 dependent own NPS base is required', () {
      final outcome = engine.calculate(example(year, amounts: {
        TaxAmountField.ownNpsTotal: '200000',
      }, flags: {
        TaxConfirmation.npsEmployee
      }));
      expect(outcome, isA<TaxInvalidInput>());
      expect((outcome as TaxInvalidInput).issues.join(' '),
          contains('Own-NPS salary base'));
    });
    test('${year.name} IT-REVIEW-001 employer base cannot supply own base', () {
      final outcome = engine.calculate(example(year, amounts: {
        TaxAmountField.ownNpsTotal: '200000',
        TaxAmountField.employerNps: '10000',
        TaxAmountField.employerSalaryBase: '800000',
      }, flags: {
        TaxConfirmation.npsEmployee
      }));
      expect(outcome, isA<TaxInvalidInput>());
      expect((outcome as TaxInvalidInput).issues.join(' '),
          contains('Own-NPS salary base'));
    });
    for (final base in ['0', '800000']) {
      test('${year.name} IT-REVIEW-001 explicit base $base', () {
        final r = engine.calculate(example(year, amounts: {
          TaxAmountField.ownNpsTotal: '200000',
          TaxAmountField.npsSalaryBase: base,
        }, flags: {
          TaxConfirmation.npsEmployee
        })) as TaxComparison;
        expect(r.oldRegime.totalIncome, e(base == '0' ? '1400000' : '1320000'));
        expect(r.oldRegime.liability, e(base == '0' ? '241800' : '216840'));
      });
    }
    for (final scenario in [
      'additional-only',
      'exhausted-group',
      'nonemployee',
      'no-income'
    ]) {
      test('${year.name} IT-REVIEW-001 independent $scenario needs no base',
          () {
        final r = engine.calculate(example(year, amounts: {
          TaxAmountField.ownNpsTotal:
              scenario == 'additional-only' ? '50000' : '200000',
          if (scenario == 'exhausted-group') TaxAmountField.epf: '150000',
          if (scenario == 'no-income') TaxAmountField.salary: '0',
        }, flags: {
          if (scenario != 'nonemployee') TaxConfirmation.npsEmployee
        })) as TaxComparison;
        expect(
            r.oldRegime.liability,
            e(scenario == 'no-income'
                ? '0'
                : scenario == 'additional-only'
                    ? '241800'
                    : '195000'));
      });
    }
    test(
        '${year.name} own salary base cannot substitute for a missing employer base',
        () {
      expect(
          engine.calculate(example(year, amounts: {
            TaxAmountField.employerNps: '100000',
            TaxAmountField.npsSalaryBase: '1000000',
          })),
          isA<TaxInvalidInput>());
      final r = engine.calculate(example(year, amounts: {
        TaxAmountField.employerNps: '100000',
        TaxAmountField.employerSalaryBase: '200000',
        TaxAmountField.npsSalaryBase: '1000000',
      })) as TaxComparison;
      expect(
          r.oldRegime.deductions
              .firstWhere((d) => d.label == 'Employer NPS')
              .allowed,
          e('20000'));
      expect(
          r.newRegime.deductions
              .firstWhere((d) => d.label == 'Employer NPS')
              .allowed,
          e('28000'));
    });

    for (final age in TaxAge.values) {
      test(
          '${year.name} ${age.name} guided instruments share one cap with salary',
          () {
        final r = engine.calculate(example(year, age: age, amounts: {
          TaxAmountField.epf: '20000',
          TaxAmountField.tuitionChildOne: '40000',
          TaxAmountField.tuitionChildTwo: '30000',
          TaxAmountField.housingPrincipal: '60000',
          TaxAmountField.housingTransferCharges: '10000',
          TaxAmountField.nscSubscription: '20000',
        }, flags: {
          TaxConfirmation.tuitionChildOneEligible,
          TaxConfirmation.tuitionChildTwoEligible,
          TaxConfirmation.housingPurchaseEligible,
          TaxConfirmation.nscEligibility
        }, policies: [
          LifePremium(
              paid: e('25000'),
              assured: e('100000'),
              issued: DateTime.utc(2013, 4, 1),
              selfSpouseOrChild: true,
              qualifyingDisabilityOrAilment: true)
        ])) as TaxComparison;
        expect(r.oldRegime.totalIncome, e('1300000'));
        expect(
            r.oldRegime.liability,
            e(switch (age) {
              TaxAge.below60 => '210600',
              TaxAge.from60to79 => '208000',
              TaxAge.atLeast80 => '197600'
            }));
        expect(r.newRegime.liability, e('97500'));
        expect(
            r.oldRegime.deductions
                .where((d) => d.ruleId.startsWith('IT-INVEST'))
                .fold(Exact.zero, (sum, d) => sum + d.allowed),
            e('150000'));
      });
      test(
          '${year.name} ${age.name} separate government and other employer limits',
          () {
        final r = engine.calculate(example(year, age: age, employers: [
          EmployerNps(
              contribution: e('90000'),
              salaryBase: e('500000'),
              government: true,
              alreadyInGrossSalary: true),
          EmployerNps(
              contribution: e('50000'),
              salaryBase: e('200000'),
              government: false,
              alreadyInGrossSalary: false),
        ])) as TaxComparison;
        expect(r.oldRegime.totalIncome, e('1410000'));
        expect(r.newRegime.totalIncome, e('1377000'));
        expect(
            r.oldRegime.liability,
            e(switch (age) {
              TaxAge.below60 => '244920',
              TaxAge.from60to79 => '242320',
              TaxAge.atLeast80 => '231920'
            }));
        expect(r.newRegime.liability, e('90010'));
        final old =
            r.oldRegime.deductions.where((d) => d.ruleId == 'IT-NPS').toList();
        expect(old[0].allowed, e('70000'));
        expect(old[1].allowed, e('20000'));
        expect(
            r.newRegime.deductions
                .where((d) => d.ruleId == 'IT-NPS')
                .toList()[1]
                .allowed,
            e('28000'));
      });
    }
    test('${year.name} policy issue boundaries and ineligible beneficiary', () {
      final dates = [
        DateTime.utc(2012, 3, 31),
        DateTime.utc(2012, 4, 1),
        DateTime.utc(2013, 3, 31),
        DateTime.utc(2013, 4, 1)
      ];
      final r = engine.calculate(example(year, policies: [
        for (final date in dates)
          LifePremium(
              paid: e('25000'),
              assured: e('100000'),
              issued: date,
              selfSpouseOrChild: true,
              qualifyingDisabilityOrAilment: true),
        LifePremium(
            paid: e('25000'),
            assured: e('100000'),
            issued: DateTime.utc(2015),
            selfSpouseOrChild: false),
      ])) as TaxComparison;
      expect(
          r.oldRegime.deductions
              .where((d) => d.ruleId == 'IT-INVEST-LIFE')
              .map((d) => d.allowed),
          ['20000', '10000', '10000', '15000', '0'].map(e));
      expect(
          r.newRegime.deductions
              .where((d) => d.ruleId == 'IT-INVEST-LIFE')
              .every((d) => d.allowed.isZero),
          isTrue);
      final bad = engine.calculate(example(year, policies: [
        LifePremium(
            paid: e('10'),
            assured: e('0'),
            issued: DateTime.utc(2030),
            selfSpouseOrChild: true)
      ]));
      expect(bad, isA<TaxInvalidInput>());
    });
    test(
        '${year.name} tuition and housing eligibility never become an unrestricted amount',
        () {
      final r = engine.calculate(example(year,
          amounts: {
            TaxAmountField.tuitionChildOne: '40000',
            TaxAmountField.tuitionChildTwo: '30000',
            TaxAmountField.housingPrincipal: '60000',
            TaxAmountField.housingTransferCharges: '10000'
          },
          flags: {
            TaxConfirmation.tuitionChildOneEligible,
            TaxConfirmation.housingPurchaseEligible
          },
          housing: HousingPaymentKind.otherLender)) as TaxComparison;
      expect(r.oldRegime.totalIncome,
          e('1400000')); // 40k tuition +10k transfer only.
      expect(
          r.oldRegime.deductions
              .firstWhere((d) => d.label == 'Tuition child 2')
              .allowed,
          Exact.zero);
      expect(
          r.oldRegime.deductions
              .firstWhere(
                  (d) => d.label == 'Housing principal / qualifying instalment')
              .allowed,
          Exact.zero);
    });
    test(
        '${year.name} NSC interest enters income once; final interest not reinvested',
        () {
      final r = engine.calculate(example(year, amounts: {
        TaxAmountField.nscSubscription: '20000',
        TaxAmountField.nscReinvestedInterest: '4000',
        TaxAmountField.nscFinalInterest: '6000'
      }, flags: {
        TaxConfirmation.nscEligibility
      })) as TaxComparison;
      expect(r.oldRegime.totalIncome, e('1436000'));
      expect(r.newRegime.totalIncome, e('1435000'));
      expect(
          r.oldRegime.deductions
              .firstWhere((d) => d.ruleId == 'IT-INVEST-NSC')
              .allowed,
          e('24000'));
      final combined = engine.calculate(example(year, amounts: {
        TaxAmountField.epf: '150000',
        TaxAmountField.nscReinvestedInterest: '4000'
      }, flags: {
        TaxConfirmation.nscEligibility
      })) as TaxComparison;
      expect(combined.oldRegime.liability, e('211850'));
      expect(combined.newRegime.liability, e('98120'));
      final senior = engine.calculate(example(year,
          age: TaxAge.from60to79,
          amounts: {TaxAmountField.nscReinvestedInterest: '4000'},
          flags: {TaxConfirmation.nscEligibility}));
      expect(senior,
          isA<TaxNotYetVerified>()); // Safety only, not implemented senior classification.
    });
    test('${year.name} fixed turnover commission and all HRA cities', () {
      for (final city in [
        'Mumbai',
        'Kolkata',
        'Delhi',
        'Chennai',
        'Hyderabad',
        'Pune',
        'Ahmedabad',
        'Bengaluru',
        'Other'
      ]) {
        final p = HraPeriod(
            firstDay: 1,
            lastDay: 365,
            city: city,
            basic: e('600000'),
            eligibleDa: e('0'),
            turnoverCommission: e('100000'),
            actualHra: e('400000'),
            rent: e('600000'));
        final metro =
            ['Mumbai', 'Kolkata', 'Delhi', 'Chennai'].contains(city) ||
                year == TaxYear.ty2026 && city != 'Other';
        expect(TaxExemptions.hra(p, year), e(metro ? '350000' : '280000'));
        final r = engine.calculate(TaxInput(
            year: year,
            age: TaxAge.below60,
            amounts: {TaxAmountField.salary: e('1500000')},
            confirmations: f.confirmed,
            hraPeriods: [p])) as TaxComparison;
        expect(r.oldRegime.totalIncome, e(metro ? '1100000' : '1170000'));
        expect(r.newRegime.totalIncome, e('1425000'));
      }
    });
  }
  test('guided records immutable and employer salary cannot be counted twice',
      () {
    final employers = [
      EmployerNps(
          contribution: e('100000'),
          salaryBase: e('900000'),
          government: false,
          alreadyInGrossSalary: true)
    ];
    final i = example(TaxYear.fy2025, employers: employers);
    employers.clear();
    expect(i.employers.length, 1);
    expect(() => i.additionalEmployers.clear(), throwsUnsupportedError);
    expect(
        engine.calculate(example(TaxYear.fy2025,
            employers: [...i.employers, ...i.employers])),
        isA<TaxInvalidInput>());
  });
}
