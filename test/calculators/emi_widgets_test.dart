import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/amortization_schedule_pager.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/calculator_catalog.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/calculators_home_screen.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/emi_screen.dart';
import 'package:mutual_fund_portfolio_app/theme/app_theme.dart';

class _RejectNetwork extends HttpOverrides {
  int calls = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    calls++;
    throw StateError('EMI must not access the network');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> mount(WidgetTester tester,
      {Widget? home,
      Size size = const Size(1000, 1000),
      double scale = 1,
      bool dark = false}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: home ?? EmiScreen(clock: () => DateTime(2026, 10, 5)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 200);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester,
      {String principal = '1000000',
      String tenure = '120',
      String rate = '8.5'}) async {
    await enter(tester, 'principal', principal);
    await enter(tester, 'tenure', tenure);
    await enter(tester, 'annualRate', rate);
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

  Finder summary(String value) => find.descendant(
      of: find.byKey(const ValueKey('emi-summary')),
      matching: find.text(value));

  testWidgets(
      'catalog retains calculator one and adds unique EMI route with back',
      (tester) async {
    await mount(tester, home: const CalculatorsHomeScreen());
    expect(calculatorCatalog.map((e) => e.id),
        ['loan-part-payment', 'emi', 'sip']);
    expect(calculatorCatalog.map((e) => e.id).toSet().length, 3);
    expect(find.text('Loan Part Payment Calculator'), findsOneWidget);
    expect(find.text('EMI Calculator'), findsOneWidget);
    await press(tester, 'emi');
    expect(find.byType(EmiScreen), findsOneWidget);
    await fill(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorsHomeScreen), findsOneWidget);
    await press(tester, 'emi');
    expect(text(tester, 'principal'), isEmpty);
    expect(find.byType(AmortizationSchedulePager), findsNothing);
  });

  testWidgets('required fields, explicit calculation, locked Indian summaries',
      (tester) async {
    await mount(tester);
    expect(find.byType(TextField), findsNWidgets(3));
    for (final label in [
      'Loan amount',
      'Loan tenure',
      'Tenure unit',
      'Months',
      'Years',
      'Rate of interest (% p.a.)'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tenure')))
            .keyboardType
            .decimal,
        isFalse);
    await fill(tester);
    expect(find.byKey(const ValueKey('emi-summary')), findsNothing);
    expect(find.byType(AmortizationSchedulePager), findsNothing);
    await press(tester, 'calculate');
    for (final value in [
      '₹12,398.57',
      '₹4,87,828.27',
      '₹14,87,828.27',
      '120 months'
    ]) {
      expect(summary(value), findsOneWidget);
    }
    expect(find.text('Month-wise repayment schedule'), findsOneWidget);
    expect(
        find.text(
            "Calendar months are illustrative. The first row represents the next monthly EMI; your lender's actual EMI date may differ."),
        findsOneWidget);
    expect(
        find.text(
            'This estimate is not lender advice or a binding repayment schedule.'),
        findsOneWidget);
  });

  testWidgets(
      'unit switch clears input/error/result/schedule; years give identical summaries',
      (tester) async {
    await mount(tester);
    await fill(tester);
    await press(tester, 'calculate');
    await press(tester, 'schedule-next');
    await press(tester, 'tenure-years');
    expect(text(tester, 'tenure'), '');
    expect(find.byKey(const ValueKey('emi-summary')), findsNothing);
    expect(find.byType(AmortizationSchedulePager), findsNothing);
    await press(tester, 'calculate');
    expect(find.text('This field is required.'), findsOneWidget);
    await press(tester, 'tenure-months');
    expect(find.text('This field is required.'), findsNothing);
    expect(text(tester, 'tenure'), '');
    await press(tester, 'tenure-years');
    await enter(tester, 'tenure', '10');
    await press(tester, 'calculate');
    for (final value in [
      '₹12,398.57',
      '₹4,87,828.27',
      '₹14,87,828.27',
      '10 years · 120 months'
    ]) {
      expect(summary(value), findsOneWidget);
    }
    expect(find.text('Months 1–12 of 120'), findsOneWidget);
    await press(tester, 'tenure-months');
    expect(text(tester, 'tenure'), '');
    expect(find.byType(AmortizationSchedulePager), findsNothing);
  });

  testWidgets(
      'validation preserves malformed entries and never displays stale results',
      (tester) async {
    await mount(tester);
    await press(tester, 'calculate');
    expect(find.text('This field is required.'), findsNWidgets(3));
    await fill(tester, principal: 'NaN', tenure: '12.5', rate: 'Infinity');
    await press(tester, 'calculate');
    expect(text(tester, 'principal'), 'NaN');
    expect(text(tester, 'tenure'), '12.5');
    expect(text(tester, 'annualRate'), 'Infinity');
    expect(find.text('Enter a plain number without commas or symbols.'),
        findsNWidgets(2));
    expect(find.text('Enter a whole number from 1 to 600 months.'),
        findsOneWidget);
    expect(find.byType(AmortizationSchedulePager), findsNothing);
    await press(tester, 'tenure-years');
    await fill(tester, tenure: '10.5');
    await press(tester, 'calculate');
    expect(
        find.text('Enter a whole number from 1 to 50 years.'), findsOneWidget);
    expect(text(tester, 'tenure'), '10.5');
  });

  testWidgets(
      'zero interest renders principal-only repayment and reset clears everything',
      (tester) async {
    await mount(tester);
    await fill(tester, principal: '100000', tenure: '12', rate: '0');
    await press(tester, 'calculate');
    for (final value in ['₹8,333.33', '₹0.00', '₹1,00,000.00']) {
      expect(summary(value), findsOneWidget);
    }
    expect(find.text('Months 1–12 of 12'), findsOneWidget);
    await press(tester, 'reset');
    for (final key in ['principal', 'tenure', 'annualRate']) {
      expect(text(tester, key), '');
    }
    expect(find.byType(AmortizationSchedulePager), findsNothing);
    expect(find.byKey(const ValueKey('emi-summary')), findsNothing);
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('tenure-months')))
            .selected,
        isTrue);
  });

  testWidgets(
      'clock captured once; paging/rebuild fixed; edits clear; recalculation starts first page',
      (tester) async {
    var now = DateTime(2026, 10, 5);
    var reads = 0;
    await mount(tester, home: EmiScreen(clock: () {
      reads++;
      return now;
    }));
    await fill(tester);
    await press(tester, 'calculate');
    expect(reads, 1);
    for (final label in [
      'Month 1 · Nov 2026',
      'Month 2 · Dec 2026',
      'Month 3 · Jan 2027'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    now = DateTime(2026, 12, 31);
    await press(tester, 'schedule-next');
    await tester.pump();
    expect(find.text('Month 13 · Nov 2027'), findsOneWidget);
    expect(reads, 1);
    await press(tester, 'calculate');
    expect(reads, 2);
    expect(find.text('Months 1–12 of 120'), findsOneWidget);
    expect(find.text('Month 1 · Jan 2027'), findsOneWidget);
    for (final (key, value) in [
      ('principal', '100000'),
      ('tenure', '1'),
      ('annualRate', '0')
    ]) {
      await enter(tester, key, value);
      expect(find.byType(AmortizationSchedulePager), findsNothing);
      expect(find.byKey(const ValueKey('emi-summary')), findsNothing);
      await press(tester, 'calculate');
    }
    expect(find.text('Months 1–1 of 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-month-2')), findsNothing);
    expect(reads, 5);
  });

  testWidgets('semantics, selected unit, touch targets and keyboard operation',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester);
      expect(find.bySemanticsLabel('Loan amount'), findsWidgets);
      expect(find.bySemanticsLabel('Rate of interest (% p.a.)'), findsWidgets);
      final months = find.bySemanticsLabel(RegExp('Tenure in months'));
      expect(
          tester.getSemantics(months).flagsCollection.isSelected ==
              Tristate.isTrue,
          isTrue);
      await press(tester, 'tenure-years');
      expect(
          tester
                  .getSemantics(
                      find.bySemanticsLabel(RegExp('Tenure in years')))
                  .flagsCollection
                  .isSelected ==
              Tristate.isTrue,
          isTrue);
      for (final key in [
        'principal',
        'tenure',
        'annualRate',
        'tenure-months',
        'tenure-years',
        'calculate',
        'reset'
      ]) {
        expect(tester.getSize(find.byKey(ValueKey(key))).height,
            greaterThanOrEqualTo(48));
      }
      await enter(tester, 'principal', '100000');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('tenure')))
              .focusNode!
              .hasFocus,
          isTrue);
      await fill(tester, tenure: '1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emi-summary')), findsOneWidget);
      for (final key in ['schedule-next', 'schedule-previous']) {
        expect(tester.getSize(find.byKey(ValueKey(key))).height,
            greaterThanOrEqualTo(48));
      }
    } finally {
      semantics.dispose();
    }
  });

  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets(
            'hub/form/results/errors fit $width px / $scale text / dark $dark',
            (tester) async {
          await mount(tester,
              home: const CalculatorsHomeScreen(),
              size: Size(width, 1000),
              scale: scale,
              dark: dark);
          expect(tester.takeException(), isNull);
          await press(tester, 'emi');
          await fill(tester,
              principal: '10000000000', tenure: '600', rate: '30');
          await press(tester, 'calculate');
          expect(summary('600 months'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await press(tester, 'schedule-next');
          expect(find.text('Months 13–24 of 600'), findsOneWidget);
          expect(find.byKey(const ValueKey('schedule-month-25')), findsNothing);
          await press(tester, 'schedule-previous');
          expect(find.text('Months 1–12 of 600'), findsOneWidget);
          expect(tester.takeException(), isNull);
          // Horizontal overflow is contained inside the desktop table only.
          for (final scroll in tester.widgetList<SingleChildScrollView>(
              find.byType(SingleChildScrollView))) {
            if (scroll.scrollDirection == Axis.horizontal) {
              expect(scroll.child, isA<DataTable>());
            }
          }
          await press(tester, 'tenure-years');
          await enter(tester, 'tenure', '51');
          await press(tester, 'calculate');
          expect(find.text('Enter a whole number from 1 to 50 years.'),
              findsOneWidget);
          expect(find.byType(AmortizationSchedulePager), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
      'standalone EMI and paging need no services, network, storage or logs',
      (tester) async {
    final network = _RejectNetwork();
    final previous = HttpOverrides.current;
    final oldPrint = debugPrint;
    final messages = <String>[];
    HttpOverrides.global = network;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() {
      HttpOverrides.global = previous;
      debugPrint = oldPrint;
    });
    await mount(tester);
    await fill(tester);
    await press(tester, 'calculate');
    expect(summary('₹12,398.57'), findsOneWidget);
    await press(tester, 'schedule-next');
    await press(tester, 'tenure-years');
    await enter(tester, 'tenure', '10');
    await press(tester, 'calculate');
    await press(tester, 'reset');
    expect(network.calls, 0);
    expect(messages, isEmpty);
    debugPrint = oldPrint;
  });
}
