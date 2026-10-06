import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/calculator_catalog.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/calculators_home_screen.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/sip_screen.dart';
import 'package:mutual_fund_portfolio_app/theme/app_theme.dart';

class _RejectNetwork extends HttpOverrides {
  int calls = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    calls++;
    throw StateError('SIP calculator must not access the network');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> mount(WidgetTester tester,
      {Widget? home,
      double width = 1000,
      double scale = 1,
      bool dark = false}) async {
    await tester.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: home ?? SipScreen(clock: () => DateTime(2026, 10, 5)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    if (finder.evaluate().isEmpty) await tester.scrollUntilVisible(finder, 200);
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
      {String initial = '100000',
      String monthly = '10000',
      String tenure = '120',
      String roi = '12',
      String lump = '200000',
      String date = '2031-10-20'}) async {
    for (final (key, value) in [
      ('initialInvestment', initial),
      ('monthlySip', monthly),
      ('tenure', tenure),
      ('annualRoi', roi),
      ('lumpSum', lump),
      ('lumpSumDate', date)
    ]) {
      await enter(tester, key, value);
    }
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
  Finder summary(String value) => find.descendant(
      of: find.byKey(const ValueKey('sip-summary')),
      matching: find.text(value));

  testWidgets(
      'catalog keeps both loan calculators and opens separate SIP route with Back',
      (tester) async {
    await mount(tester, home: const CalculatorsHomeScreen());
    expect(calculatorCatalog.map((e) => e.id),
        ['loan-part-payment', 'emi', 'sip', 'income-tax']);
    expect(calculatorCatalog.map((e) => e.id).toSet().length, 4);
    for (final title in [
      'Loan Part Payment Calculator',
      'EMI Calculator',
      'SIP Calculator'
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    await press(tester, 'sip');
    expect(find.byType(SipScreen), findsOneWidget);
    await fill(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorsHomeScreen), findsOneWidget);
    await press(tester, 'sip');
    expect(text(tester, 'monthlySip'), '');
    expect(text(tester, 'initialInvestment'), '0');
    expect(find.byKey(const ValueKey('sip-summary')), findsNothing);
  });

  testWidgets(
      'required fields, explicit Calculate and locked Indian-format summary',
      (tester) async {
    await mount(tester);
    expect(find.byType(TextField), findsNWidgets(6));
    for (final label in [
      'Initial Investment Amount',
      'Monthly SIP Amount',
      'SIP Tenure',
      'Months',
      'Years',
      'Expected ROI (% p.a.)',
      'Lump Sum Amount',
      'Lump Sum Investment Date'
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
    expect(find.byKey(const ValueKey('sip-summary')), findsNothing);
    await press(tester, 'calculate');
    for (final value in [
      '₹30,16,768.79',
      '₹15,00,000.00',
      '₹15,16,768.79',
      '120 months',
      'Plan: 05 Oct 2026 – 30 Sep 2036'
    ]) {
      expect(summary(value), findsOneWidget);
    }
    expect(find.textContaining('there is no daily proration'), findsOneWidget);
    expect(find.textContaining('not guaranteed'), findsOneWidget);
    expect(
        find.text(
            'Your entries stay on this screen and are not saved or sent.'),
        findsOneWidget);
  });

  testWidgets(
      'zero initial and lump require no date; zero ROI equals invested amount',
      (tester) async {
    await mount(tester);
    await fill(tester,
        initial: '0',
        monthly: '10000',
        tenure: '12',
        roi: '0',
        lump: '0',
        date: '');
    await press(tester, 'calculate');
    expect(summary('₹1,20,000.00'), findsNWidgets(2));
    expect(summary('₹0.00'), findsOneWidget);
    await enter(tester, 'lumpSumDate', 'irrelevant');
    await press(tester, 'calculate');
    expect(summary('₹0.00'), findsOneWidget);
    await enter(tester, 'lumpSum', '100');
    await press(tester, 'calculate');
    expect(find.byKey(const ValueKey('sip-summary')), findsNothing);
    expect(find.text('Enter a real date as YYYY-MM-DD.'), findsOneWidget);
  });

  testWidgets(
      'unit changes clear tenure and errors; 10 years matches 120 months',
      (tester) async {
    await mount(tester);
    await fill(tester);
    await press(tester, 'calculate');
    await press(tester, 'tenure-years');
    expect(text(tester, 'tenure'), '');
    expect(find.byKey(const ValueKey('sip-summary')), findsNothing);
    await press(tester, 'calculate');
    expect(find.text('This field is required.'), findsOneWidget);
    await press(tester, 'tenure-months');
    expect(find.text('This field is required.'), findsNothing);
    expect(text(tester, 'tenure'), '');
    await press(tester, 'tenure-years');
    await enter(tester, 'tenure', '10');
    await press(tester, 'calculate');
    expect(summary('10 years · 120 months'), findsOneWidget);
    expect(summary('₹30,16,768.79'), findsOneWidget);
    expect(summary('₹15,00,000.00'), findsOneWidget);
    expect(summary('₹15,16,768.79'), findsOneWidget);
  });

  testWidgets('safe validation preserves malformed and negative entries',
      (tester) async {
    await mount(tester);
    await press(tester, 'calculate');
    expect(find.text('This field is required.'), findsNWidgets(3));
    await fill(tester, monthly: 'NaN', tenure: '10.5', roi: 'Infinity');
    await press(tester, 'calculate');
    expect(find.text('Enter a plain number without commas or symbols.'),
        findsNWidgets(2));
    expect(text(tester, 'monthlySip'), 'NaN');
    expect(text(tester, 'tenure'), '10.5');
    expect(find.byKey(const ValueKey('sip-summary')), findsNothing);
    await fill(tester, initial: '-1', monthly: '0', lump: '-1');
    await press(tester, 'calculate');
    expect(find.text('Enter an amount of zero or more.'), findsNWidgets(2));
    expect(find.text('Enter a monthly SIP greater than zero.'), findsOneWidget);
  });

  testWidgets(
      'date is required for lump sum and bounded by actual start and final month',
      (tester) async {
    await mount(tester);
    await fill(tester, date: '');
    await press(tester, 'calculate');
    expect(find.text('Choose a date for the lump sum.'), findsOneWidget);
    for (final (date, error) in [
      ('2026-10-04', 'Date cannot be before the calculation date.'),
      ('2036-10-01', 'Date cannot be after the final month of the SIP tenure.'),
      ('2031-02-29', 'Enter a real date as YYYY-MM-DD.'),
    ]) {
      await enter(tester, 'lumpSumDate', date);
      await press(tester, 'calculate');
      expect(find.text(error), findsOneWidget);
      expect(text(tester, 'lumpSumDate'), date);
      expect(find.byKey(const ValueKey('sip-summary')), findsNothing);
    }
    await enter(tester, 'lumpSumDate', '2036-09-30');
    await press(tester, 'calculate');
    expect(find.byKey(const ValueKey('sip-summary')), findsOneWidget);
  });

  testWidgets(
      'editing every field invalidates result; Reset restores zero defaults',
      (tester) async {
    await mount(tester);
    await fill(tester);
    await press(tester, 'calculate');
    for (final (key, value) in [
      ('initialInvestment', '100001'),
      ('monthlySip', '10001'),
      ('tenure', '121'),
      ('annualRoi', '12.1'),
      ('lumpSum', '200001'),
      ('lumpSumDate', '2031-10-21'),
    ]) {
      await enter(tester, key, value);
      expect(find.byKey(const ValueKey('sip-summary')), findsNothing);
      await press(tester, 'calculate');
    }
    await press(tester, 'reset');
    expect(find.byKey(const ValueKey('sip-summary')), findsNothing);
    expect(text(tester, 'initialInvestment'), '0');
    expect(text(tester, 'lumpSum'), '0');
    for (final key in ['monthlySip', 'tenure', 'annualRoi', 'lumpSumDate']) {
      expect(text(tester, key), '');
    }
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('tenure-months')))
            .selected,
        isTrue);
  });

  testWidgets(
      'calendar picker updates date and clears result without recapturing plan clock',
      (tester) async {
    var reads = 0;
    await mount(tester, home: SipScreen(clock: () {
      reads++;
      return DateTime(2026, 10, 5);
    }));
    await fill(tester);
    await press(tester, 'calculate');
    expect(reads, 1);
    await press(tester, 'choose-lump-date');
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('21'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(text(tester, 'lumpSumDate'), '2031-10-21');
    expect(find.byKey(const ValueKey('sip-summary')), findsNothing);
    expect(reads, 1);
    await press(tester, 'calculate');
    expect(reads, 2);
    expect(summary('₹30,16,768.79'), findsOneWidget);
  });

  testWidgets(
      'rebuilds retain captured start; new Calculate revalidates the date',
      (tester) async {
    var now = DateTime(2026, 10, 5);
    var reads = 0;
    await mount(tester, home: SipScreen(clock: () {
      reads++;
      return now;
    }));
    await fill(tester, date: '2026-10-05');
    await press(tester, 'calculate');
    now = DateTime(2026, 10, 6);
    await tester.pump();
    expect(reads, 1);
    expect(summary('Plan: 05 Oct 2026 – 30 Sep 2036'), findsOneWidget);
    await press(tester, 'calculate');
    expect(reads, 2);
    expect(find.byKey(const ValueKey('sip-summary')), findsNothing);
    expect(find.text('Date cannot be before the calculation date.'),
        findsOneWidget);
  });

  testWidgets('semantic labels, choice state, keyboard and 48px controls',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester);
      expect(find.bySemanticsLabel('Monthly SIP Amount'), findsWidgets);
      await tester.ensureVisible(find.byKey(const ValueKey('lumpSumDate')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Lump Sum Investment Date')),
          findsWidgets);
      await tester.ensureVisible(find.byKey(const ValueKey('tenure-months')));
      await tester.pumpAndSettle();
      expect(
          tester
              .getSemantics(find.bySemanticsLabel(RegExp('Tenure in months')))
              .flagsCollection
              .isSelected,
          Tristate.isTrue);
      await press(tester, 'tenure-years');
      expect(
          tester
              .getSemantics(find.bySemanticsLabel(RegExp('Tenure in years')))
              .flagsCollection
              .isSelected,
          Tristate.isTrue);
      for (final key in [
        'initialInvestment',
        'monthlySip',
        'tenure',
        'annualRoi',
        'lumpSum',
        'lumpSumDate',
        'tenure-months',
        'tenure-years',
        'calculate',
        'reset',
        'choose-lump-date'
      ]) {
        expect(tester.getSize(find.byKey(ValueKey(key))).height,
            greaterThanOrEqualTo(48));
      }
      await enter(tester, 'initialInvestment', '100000');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('monthlySip')))
              .focusNode!
              .hasFocus,
          isTrue);
      await fill(tester, tenure: '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(summary('₹30,16,768.79'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets(
            'form/results/date picker/errors fit $width px, $scale text, dark $dark',
            (tester) async {
          await mount(tester,
              home: const CalculatorsHomeScreen(),
              width: width,
              scale: scale,
              dark: dark);
          expect(tester.takeException(), isNull);
          await press(tester, 'sip');
          await fill(tester,
              initial: '10000000000',
              monthly: '10000000000',
              tenure: '600',
              roi: '30',
              lump: '10000000000',
              date: '2031-10-20');
          await press(tester, 'calculate');
          expect(summary('600 months'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await press(tester, 'choose-lump-date');
          expect(find.byType(DatePickerDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          await enter(tester, 'monthlySip', '-1');
          await press(tester, 'calculate');
          expect(find.text('Enter a monthly SIP greater than zero.'),
              findsOneWidget);
          expect(find.byKey(const ValueKey('sip-summary')), findsNothing);
          expect(tester.takeException(), isNull);
          expect(
              tester
                  .widgetList<SingleChildScrollView>(
                      find.byType(SingleChildScrollView))
                  .every((view) => view.scrollDirection == Axis.vertical),
              isTrue);
        });
      }
    }
  }

  testWidgets(
      'standalone SIP works without providers, services, network or debug logs',
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
    expect(summary('₹30,16,768.79'), findsOneWidget);
    await press(tester, 'choose-lump-date');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await press(tester, 'tenure-years');
    await enter(tester, 'tenure', '10');
    await press(tester, 'calculate');
    await press(tester, 'reset');
    expect(network.calls, 0);
    expect(messages, isEmpty);
    debugPrint = oldPrint;
  });
}
