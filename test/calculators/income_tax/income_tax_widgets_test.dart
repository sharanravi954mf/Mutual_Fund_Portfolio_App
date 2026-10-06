import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/models/tax_input.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/models/tax_result.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/presentation/income_tax_controller.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/income_tax/presentation/income_tax_screen.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/calculator_catalog.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/calculators_home_screen.dart';
import 'package:mutual_fund_portfolio_app/theme/app_theme.dart';
import 'income_tax_engine_test.dart' as fixtures;

class _NoNetwork extends HttpOverrides {
  int calls = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    calls++;
    throw StateError('Calculator network request');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  Future<void> mount(WidgetTester t,
      {double width = 1000,
      double scale = 1,
      bool dark = false,
      Widget home = const IncomeTaxScreen()}) async {
    await t.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: home));
    await t.pumpAndSettle();
  }

  IncomeTaxController controller(WidgetTester t) => t
      .widgetList<AnimatedBuilder>(find.byType(AnimatedBuilder))
      .map((b) => b.listenable)
      .whereType<IncomeTaxController>()
      .single;
  Future<void> press(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> enter(WidgetTester t, String key, String value) async {
    final f = find.byKey(ValueKey(key));
    await t.ensureVisible(f);
    await t.enterText(f, value);
    await t.pumpAndSettle();
  }

  testWidgets('catalog fourth route and leaving discards financial entries',
      (t) async {
    await mount(t, home: const CalculatorsHomeScreen());
    expect(calculatorCatalog.map((c) => c.id),
        ['loan-part-payment', 'emi', 'sip', 'income-tax']);
    await press(t, find.byKey(const ValueKey('income-tax')));
    expect(find.byType(IncomeTaxScreen), findsOneWidget);
    await enter(t, 'salary-0', '1500000');
    await t.pageBack();
    await t.pumpAndSettle();
    await press(t, find.byKey(const ValueKey('income-tax')));
    expect(controller(t).value(TaxAmountField.salary), isEmpty);
  });
  for (final spec in [
    (320.0, 2.0, false),
    (320.0, 1.0, true),
    (768.0, 1.0, true),
    (1280.0, 1.5, true),
    (1440.0, 1.0, false)
  ]) {
    testWidgets('responsive comparison ${spec.$1} ${spec.$2} dark=${spec.$3}',
        (t) async {
      final noNetwork = _NoNetwork();
      final old = HttpOverrides.current;
      HttpOverrides.global = noNetwork;
      addTearDown(() => HttpOverrides.global = old);
      await mount(t, width: spec.$1, scale: spec.$2, dark: spec.$3);
      final semantics = t.ensureSemantics();

      final c = controller(t);
      for (final f in fixtures.confirmed) {
        c.setConfirmation(f, true);
      }
      await enter(t, 'salary-0', '1500000');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect(c.outcome, isA<TaxComparison>());
      expect(
          find.text(
              'New Regime gives ₹1,59,900 lower estimated tax for the information entered.'),
          findsOneWidget);
      expect(find.textContaining('₹97,500'), findsWidgets);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      await enter(t, 'salary-0', '1285000');
      expect(c.outcome, isNull);
      expect(find.textContaining('₹97,500'), findsNothing);
      c.setMode(TaxMode.advanced);
      await t.pumpAndSettle();
      for (final title in [
        'Advanced salary and HRA',
        'House property',
        'Equity capital gains'
      ]) {
        await press(t, find.text(title));
        expect(t.takeException(), isNull);
      }
      await t.ensureVisible(find.byKey(const ValueKey('tax-calculate')));
      expect(t.getSemantics(find.byKey(const ValueKey('tax-calculate'))).label,
          contains('Calculate'));
      semantics.dispose();
      expect(noNetwork.calls, 0);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'retained advanced entries year invalidation reset and verification status',
      (t) async {
    await mount(t);
    final c = controller(t);
    expect(c.year, TaxYear.ty2026);
    c.setYear(TaxYear.fy2025);
    for (final f in fixtures.confirmed) {
      c.setConfirmation(f, true);
    }
    c.setMode(TaxMode.advanced);
    c.setAmount(TaxAmountField.equityLtcg, '5000800');
    c.calculate();
    await t.pumpAndSettle();
    expect(c.outcome, isA<TaxComparison>());
    c.setMode(TaxMode.normal);
    await t.pumpAndSettle();
    expect(
        find.textContaining('Advanced entries are retained'), findsOneWidget);
    expect(find.text('Equity capital gains'), findsOneWidget);
    c.setAmount(TaxAmountField.otherInterest, '100000');
    c.calculate();
    await t.pumpAndSettle();
    expect(
        find.text(
            'This combination is not supported in V1. No tax comparison has been calculated.'),
        findsOneWidget);
    expect(find.textContaining('lower estimated tax'), findsNothing);
    c.setYear(TaxYear.ty2026);
    await t.pumpAndSettle();
    expect(c.outcome, isNull);
    expect(find.textContaining('Income-tax Act, 2025'), findsOneWidget);
    c.calculate();
    await t.pumpAndSettle();
    expect(find.text('Check your inputs'), findsOneWidget);
    await press(t, find.text('Reset'));
    expect(c.value(TaxAmountField.equityLtcg), isEmpty);
    expect(c.outcome, isNull);
    await press(t, find.text('Rules & Assumptions'));
    expect(find.textContaining('in-2025-ty2026-27-v3'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });
  Future<void> check(WidgetTester t, String key) =>
      press(t, find.byKey(ValueKey(key)));
  Future<void> select(WidgetTester t, String key, String label) async {
    await press(t, find.byKey(ValueKey(key)));
    await press(t, find.text(label).last);
  }

  Future<void> eligibility(WidgetTester t) async {
    await press(t, find.text('Eligibility'));
    for (final key in [
      'residentOrdinarilyResidentIndividual',
      'ageForSelectedYear',
      'scopeChecklistReviewed'
    ]) {
      await check(t, key);
    }
    await press(t, find.text('Eligibility'));
  }

  for (final year in TaxYear.values) {
    testWidgets('${year.name} form-supported gains and blocked allocation',
        (t) async {
      await mount(t, width: 768);
      if (year == TaxYear.fy2025) {
        await select(t, 'year-0', 'FY 2025–26 / AY 2026–27');
      }
      await eligibility(t);
      await press(t, find.text('Advanced'));
      await enter(t, 'salary-0', '1175000');
      await check(t, 'salaryDefinition');
      await press(t, find.text('Equity capital gains'));
      await enter(t, 'equityStcg-0', '100000');
      await check(t, 'equityStcgEligible');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect((controller(t).outcome as TaxComparison).newRegime.liability,
          fixtures.e('20800'));
      await enter(t, 'equityLtcg-0', '200000');
      await check(t, 'equityLtcgEligible');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect(controller(t).outcome, isA<TaxComparison>());
      await enter(t, 'salary-0', '0');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect((controller(t).outcome as TaxNotYetVerified).dependencies,
          contains('IT-GAINS-ALLOCATION'));
      expect(find.textContaining('lower estimated tax'), findsNothing);
      await enter(t, 'equityStcg-0', '');
      await enter(t, 'equityLtcg-0', '5000800');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      final soleLtcg = controller(t).outcome as TaxComparison;
      expect(soleLtcg.newRegime.liability, fixtures.e('582580'));
      expect(soleLtcg.oldRegime.liability, fixtures.e('602080'));
      await select(
          t,
          'year-0',
          year == TaxYear.fy2025
              ? 'Tax Year 2026–27'
              : 'FY 2025–26 / AY 2026–27');
      expect(controller(t).outcome, isNull);
      expect(controller(t).value(TaxAmountField.equityLtcg), '5000800');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect(controller(t).outcome, isA<TaxInvalidInput>());
      await press(t, find.text('Reset'));
      expect(controller(t).value(TaxAmountField.equityLtcg), isEmpty);
      expect(t.takeException(), isNull);
    });
    testWidgets('${year.name} V1 guided deposits through actual controls',
        (t) async {
      await mount(t, width: 390, scale: 1.5);
      if (year == TaxYear.fy2025) {
        await select(t, 'year-0', 'FY 2025–26 / AY 2026–27');
      }
      await eligibility(t);
      await enter(t, 'salary-0', '1500000');
      await check(t, 'salaryDefinition');
      await press(t, find.text('Investments and own NPS'));
      await enter(t, 'bankFiveYearDeposit-0', '100000');
      await check(t, 'bankFiveYearEligible');
      await check(t, 'investmentEligibility');
      await check(t, 'investmentAmountsExclusive');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect((controller(t).outcome as TaxComparison).oldRegime.liability,
          fixtures.e('226200'));
      expect(find.textContaining('₹97,500'), findsWidgets);
      await enter(t, 'postFiveYearDeposit-0', '100000');
      expect(controller(t).outcome, isNull);
      expect(find.textContaining('lower estimated tax'), findsNothing);
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect(controller(t).outcome, isA<TaxInvalidInput>());
      await check(t, 'postFiveYearEligible');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect((controller(t).outcome as TaxComparison).oldRegime.liability,
          fixtures.e('210600'));
      await enter(t, 'scssDeposit-0', '100000');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect(controller(t).outcome, isA<TaxNotYetVerified>());
      expect(find.textContaining('lower estimated tax'), findsNothing);
      await press(t, find.text('Eligibility'));
      await select(t, 'age-0', '60–79');
      await check(t, 'ageForSelectedYear');
      await press(t, find.text('Eligibility'));
      await check(t, 'scssEligibleAtOpening');
      await enter(t, 'sukanyaChildOne-0', '25000');
      await check(t, 'sukanyaChildOneEligible');
      await enter(t, 'sukanyaChildTwo-0', '25000');
      await check(t, 'sukanyaChildTwoEligible');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect(controller(t).outcome, isA<TaxInvalidInput>());
      await check(t, 'sukanyaDistinctChildren');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect((controller(t).outcome as TaxComparison).oldRegime.liability,
          fixtures.e('208000'));
      await enter(t, 'bankFiveYearDeposit-0', '');
      expect(controller(t).outcome, isNull);
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect((controller(t).outcome as TaxComparison).oldRegime.liability,
          fixtures.e('208000'));
      await select(
          t,
          'year-0',
          year == TaxYear.fy2025
              ? 'Tax Year 2026–27'
              : 'FY 2025–26 / AY 2026–27');
      expect(controller(t).outcome, isNull);
      expect(controller(t).value(TaxAmountField.scssDeposit), '100000');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect(controller(t).outcome, isA<TaxInvalidInput>());
      await press(t, find.text('Reset'));
      expect(controller(t).year, TaxYear.ty2026);
      expect(controller(t).value(TaxAmountField.scssDeposit), isEmpty);
      expect(t.takeException(), isNull);
    });
    testWidgets('${year.name} IT-REVIEW-001 actual own NPS controls',
        (t) async {
      await mount(t);
      if (year == TaxYear.fy2025) {
        await select(t, 'year-0', 'FY 2025–26 / AY 2026–27');
      }
      await eligibility(t);
      await enter(t, 'salary-0', '1500000');
      await check(t, 'salaryDefinition');
      await press(t, find.text('Investments and own NPS'));
      await enter(t, 'ownNpsTotal-0', '200000');
      await check(t, 'npsEmployee');
      await check(t, 'npsEligibility');
      Future<void> calculate() =>
          press(t, find.byKey(const ValueKey('tax-calculate')));
      Future<void> invalid() async {
        await calculate();
        expect(controller(t).outcome, isA<TaxInvalidInput>());
        expect(find.textContaining('Own-NPS salary base'), findsWidgets);
        expect(find.textContaining('lower estimated tax'), findsNothing);
      }

      await invalid(); // Omitted, never touched.
      await enter(t, 'npsSalaryBase-0', '0');
      await calculate();
      expect((controller(t).outcome as TaxComparison).oldRegime.liability,
          fixtures.e('241800'));
      await enter(t, 'npsSalaryBase-0', '800000');
      await calculate();
      expect((controller(t).outcome as TaxComparison).oldRegime.liability,
          fixtures.e('216840'));
      await enter(t, 'npsSalaryBase-0', '');
      expect(controller(t).outcome, isNull);
      expect(find.textContaining('lower estimated tax'), findsNothing);
      await invalid(); // Cleared after success.
      await enter(t, 'npsSalaryBase-0', '   ');
      await invalid(); // Whitespace is missing, not zero.
      await check(t, 'npsEmployee');
      await calculate();
      expect((controller(t).outcome as TaxComparison).oldRegime.liability,
          fixtures.e('195000'));
      await check(t, 'npsEmployee');
      expect(controller(t).outcome, isNull);
      await invalid();
      await enter(t, 'ownNpsTotal-0', '50000');
      await calculate();
      expect(controller(t).outcome, isA<TaxComparison>());
      await enter(t, 'ownNpsTotal-0', '200000');
      await enter(t, 'epf-0', '150000');
      await check(t, 'investmentEligibility');
      await calculate();
      expect((controller(t).outcome as TaxComparison).oldRegime.liability,
          fixtures.e('195000'));
      await enter(t, 'epf-0', '149999');
      await invalid();
    });
    testWidgets(
        '${year.name} browser controls: guided investments, two employers, reset',
        (t) async {
      await mount(t, width: 320, scale: 1.5);
      if (year == TaxYear.fy2025) {
        await select(t, 'year-0', 'FY 2025–26 / AY 2026–27');
      }
      await eligibility(t);
      await enter(t, 'salary-0', '1500000');
      await check(t, 'salaryDefinition');
      await press(t, find.text('Investments and own NPS'));
      await check(t, 'investmentEligibility');
      await enter(t, 'epf-0', '20000');
      await press(t, find.byKey(const ValueKey('add-life-policy')));
      await enter(t, 'policy-0-paid-0', '25000');
      await enter(t, 'policy-0-assured-0', '100000');
      await enter(t, 'policy-0-issued-0', '2013-04-01');
      await check(t, 'policy-0-family');
      await check(t, 'policy-0-special');
      await enter(t, 'tuitionChildOne-0', '40000');
      await check(t, 'tuitionChildOneEligible');
      await enter(t, 'tuitionChildTwo-0', '30000');
      await check(t, 'tuitionChildTwoEligible');
      await enter(t, 'housingPrincipal-0', '60000');
      await select(t, 'housing-kind-0', 'Government / bank');
      await check(t, 'housingPurchaseEligible');
      await enter(t, 'nscSubscription-0', '20000');
      await check(t, 'nscEligibility');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect(find.textContaining('₹2,10,600'), findsWidgets);
      expect(find.textContaining('₹97,500'), findsWidgets);
      await check(t, 'tuitionChildOneEligible');
      expect(find.textContaining('lower estimated tax'), findsNothing);
      await check(t, 'tuitionChildOneEligible');
      await press(t, find.text('Advanced'));
      await press(t, find.text('Advanced salary and HRA'));
      await enter(t, 'employerNps-0', '90000');
      await enter(t, 'employerSalaryBase-0', '500000');
      await check(t, 'employerNpsAlreadyInSalary');
      await check(t, 'governmentEmployer');
      await press(t, find.byKey(const ValueKey('add-employer')));
      await enter(t, 'employer-1-contribution-0', '50000');
      await enter(t, 'employer-1-base-0', '200000');
      await check(t, 'taxablePerquisitesIncluded');
      await check(t, 'npsEligibility');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect(controller(t).outcome, isA<TaxComparison>());
      final r = controller(t).outcome as TaxComparison;
      expect(r.oldRegime.totalIncome, fixtures.e('1260000'));
      expect(r.newRegime.liability, fixtures.e('90010'));
      await press(t, find.text('Normal'));
      expect(
          find.textContaining('Advanced entries are retained'), findsOneWidget);
      await press(t, find.byKey(const ValueKey('remove-employer-1')));
      expect(controller(t).outcome, isNull);
      await press(t, find.byKey(const ValueKey('remove-policy-0')));
      await press(t, find.text('Reset'));
      expect(find.textContaining('lower estimated tax'), findsNothing);
      expect(controller(t).policies, isEmpty);
      expect(controller(t).employers, isEmpty);
      expect(t.takeException(), isNull);
    });
    testWidgets(
        '${year.name} browser controls: changing HRA periods and cities, year and eligibility',
        (t) async {
      await mount(t);
      if (year == TaxYear.fy2025) {
        await select(t, 'year-0', 'FY 2025–26 / AY 2026–27');
      }
      final start = year == TaxYear.fy2025 ? 2025 : 2026;
      await eligibility(t);
      await enter(t, 'salary-0', '1500000');
      await check(t, 'salaryDefinition');
      await press(t, find.text('Advanced'));
      await press(t, find.text('Advanced salary and HRA'));
      await press(t, find.text('Add HRA period'));
      await enter(t, 'hra-0-end-0', '$start-09-30');
      await enter(t, 'hra-0-basic-0', '300000');
      await enter(t, 'hra-0-commission-0', '50000');
      await enter(t, 'hra-0-hra-0', '200000');
      await enter(t, 'hra-0-rent-0', '300000');
      await select(t, 'hra-0-city-0', 'Hyderabad');
      await press(t, find.text('Add HRA period'));
      await enter(t, 'hra-1-start-0', '$start-10-01');
      await enter(t, 'hra-1-basic-0', '300000');
      await enter(t, 'hra-1-commission-0', '50000');
      await enter(t, 'hra-1-hra-0', '200000');
      await enter(t, 'hra-1-rent-0', '300000');
      await select(t, 'hra-1-city-0', 'Delhi');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      final r = controller(t).outcome as TaxComparison;
      expect(r.oldRegime.totalIncome,
          fixtures.e(year == TaxYear.fy2025 ? '1135000' : '1100000'));
      expect(r.newRegime.liability, fixtures.e('97500'));
      await enter(t, 'hra-1-rent-0', '40000');
      expect(find.textContaining('lower estimated tax'), findsNothing);
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect((controller(t).outcome as TaxComparison).oldRegime.totalIncome,
          fixtures.e(year == TaxYear.fy2025 ? '1305000' : '1270000'));
      await press(t, find.byKey(const ValueKey('remove-hra-0')));
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect((controller(t).outcome as TaxComparison).oldRegime.totalIncome,
          fixtures.e('1445000'));
      expect(find.byKey(const ValueKey('hra-1-rent-0')), findsOneWidget);
      await press(t, find.text('Normal'));
      expect(
          find.textContaining('Advanced entries are retained'), findsOneWidget);
      await press(t, find.text('Eligibility'));
      await select(t, 'age-0', '80 or above');
      expect(controller(t).outcome, isNull);
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect(find.text('Check your inputs'), findsOneWidget);
      await check(t, 'ageForSelectedYear');
      await press(t, find.text('Unsupported cases and limitations'));
      await check(t, 'unsupported-nonResidentOrRnor');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect(
          find.text(
              'This combination is not supported in V1. No tax comparison has been calculated.'),
          findsOneWidget);
      await check(t, 'unsupported-nonResidentOrRnor');
      await select(
          t,
          'year-0',
          year == TaxYear.fy2025
              ? 'Tax Year 2026–27'
              : 'FY 2025–26 / AY 2026–27');
      expect(controller(t).outcome, isNull);
      expect(controller(t).hra.single.values['rent'], '40000');
      await press(t, find.byKey(const ValueKey('tax-calculate')));
      expect(find.text('Check your inputs'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
