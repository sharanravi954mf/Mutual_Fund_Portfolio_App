import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/domain/loan_part_payment_calculator.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/calculator_catalog.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/calculators_home_screen.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/loan_part_payment_screen.dart';
import 'package:mutual_fund_portfolio_app/theme/app_theme.dart';

class RejectNetwork extends HttpOverrides {
  int calls = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    calls++;
    throw StateError('Calculator must not access the network');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> mount(WidgetTester tester,
      {Widget home = const LoanPartPaymentScreen(),
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
      home: home,
    ));
    await tester.pumpAndSettle();
  }

  Future<void> enter(
      WidgetTester tester, LoanInputField field, String value) async {
    final finder = find.byKey(ValueKey(field.name));
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester,
      {String principal = '1000000',
      String months = '120',
      String rate = '8.5',
      String payment = '100000'}) async {
    for (final entry in {
      LoanInputField.principal: principal,
      LoanInputField.months: months,
      LoanInputField.annualRate: rate,
      LoanInputField.partPayment: payment
    }.entries) {
      await enter(tester, entry.key, entry.value);
    }
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

  testWidgets('catalog entry opens calculator and back returns to hub',
      (tester) async {
    await mount(tester, home: const CalculatorsHomeScreen());
    expect(calculatorCatalog.map((entry) => entry.id).toSet().length,
        calculatorCatalog.length);
    expect(find.text('Loan Part Payment Calculator'), findsOneWidget);
    await press(tester, 'loan-part-payment');
    expect(find.byType(LoanPartPaymentScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorsHomeScreen), findsOneWidget);
    await press(tester, 'loan-part-payment');
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => field.controller!.text.isEmpty),
        isTrue);
  });

  testWidgets(
      'four labelled fields, units, keyboard hints and explicit calculation',
      (tester) async {
    await mount(tester);
    expect(find.byType(TextField), findsNWidgets(4));
    for (final label in [
      'Loan outstanding amount',
      'Loan outstanding months',
      'Rate of interest (% p.a.)',
      'Part payment amount'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('₹ '), findsNWidgets(2));
    expect(find.text('months'), findsOneWidget);
    expect(find.text('% p.a.'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('months')))
            .keyboardType
            .decimal,
        isFalse);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('principal')))
            .keyboardType
            .decimal,
        isTrue);
    await fill(tester);
    expect(find.text('Reduce EMI'), findsNothing);
    await press(tester, 'calculate');
    expect(find.text('Reduce EMI'), findsOneWidget);
    expect(find.text('Reduce tenure'), findsOneWidget);
    expect(find.text('₹12,398.57'), findsOneWidget);
    expect(find.text('₹11,158.71'), findsOneWidget);
    expect(find.text('Monthly EMI reduction: ₹1,239.86'), findsOneWidget);
    expect(find.text('After part payment: Remaining principal ₹9,00,000.00'),
        findsOneWidget);
    expect(find.text('103 months'), findsOneWidget);
    expect(find.text('Tenure reduced by: 17 months'), findsOneWidget);
    expect(find.text('Estimated final payment: ₹3,430.50'), findsOneWidget);
  });

  testWidgets(
      'empty, malformed and excessive values fail safely without clearing entries',
      (tester) async {
    await mount(tester);
    await press(tester, 'calculate');
    expect(find.text('This field is required.'), findsNWidgets(4));
    await fill(tester,
        principal: 'NaN', months: '12.5', rate: '-1', payment: '1000001');
    await press(tester, 'calculate');
    expect(find.text('Enter a plain number without commas or symbols.'),
        findsOneWidget);
    expect(find.text('Enter a whole number from 1 to 600 months.'),
        findsOneWidget);
    expect(find.text('Your estimated results'), findsNothing);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('principal')))
            .controller!
            .text,
        'NaN');
    await fill(tester, rate: '-1', payment: '1000001');
    await press(tester, 'calculate');
    expect(find.text('Enter a rate from 0 to 30% p.a.'), findsOneWidget);
    expect(find.text('Part payment cannot exceed the outstanding amount.'),
        findsOneWidget);
    await fill(tester, principal: '10000000001', months: '601', rate: '31');
    await press(tester, 'calculate');
    expect(find.text('Enter a whole number from 1 to 600 months.'),
        findsOneWidget);
    await enter(tester, LoanInputField.months, '600');
    await press(tester, 'calculate');
    expect(find.text('Maximum supported amount is ₹10,00,00,00,000.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'zero rate, zero payment and full payment render correct scenarios',
      (tester) async {
    await mount(tester);
    await fill(tester,
        principal: '100000', months: '12', rate: '0', payment: '10000');
    await press(tester, 'calculate');
    expect(find.text('₹7,500.00'), findsOneWidget);
    expect(find.text('11 months'), findsOneWidget);
    expect(find.text('Estimated final payment: ₹6,666.67'), findsOneWidget);
    await enter(tester, LoanInputField.partPayment, '0');
    await press(tester, 'calculate');
    expect(find.text('₹8,333.33'), findsNWidgets(2));
    expect(find.text('Monthly EMI reduction: ₹0.00'), findsOneWidget);
    expect(find.text('12 months'), findsOneWidget);
    expect(find.text('Tenure reduced by: 0 months'), findsOneWidget);
    await enter(tester, LoanInputField.partPayment, '100000');
    await press(tester, 'calculate');
    expect(
        find.text(
            'Your entered part payment would fully repay the outstanding principal.'),
        findsOneWidget);
    expect(find.text('₹0.00'), findsOneWidget);
    expect(find.text('0 months'), findsOneWidget);
    expect(find.text('Remaining tenure: 0 months'), findsOneWidget);
    expect(find.text('No further monthly payments.'), findsOneWidget);
  });

  testWidgets(
      'editing, recalculating, failure and reset cannot retain misleading results',
      (tester) async {
    await mount(tester);
    await fill(tester);
    await press(tester, 'calculate');
    await enter(tester, LoanInputField.partPayment, '200000');
    expect(find.text('Your estimated results'), findsNothing);
    await press(tester, 'calculate');
    expect(find.text('After part payment: Remaining principal ₹8,00,000.00'),
        findsOneWidget);
    expect(find.text('103 months'), findsNothing);
    await enter(tester, LoanInputField.partPayment, '-1');
    await press(tester, 'calculate');
    expect(find.text('Your estimated results'), findsNothing);
    expect(find.text('Enter a part payment of zero or more.'), findsOneWidget);
    await press(tester, 'reset');
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => field.controller!.text.isEmpty),
        isTrue);
    expect(find.text('Enter a part payment of zero or more.'), findsNothing);
    expect(find.text('Your estimated results'), findsNothing);
  });

  testWidgets(
      'numeric paste preserves text and tab traversal follows field order',
      (tester) async {
    await mount(tester);
    final principal = find.byKey(const ValueKey('principal'));
    await tester.tap(principal);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '1000000.25', selection: TextSelection.collapsed(offset: 10)));
    await tester.pump();
    final field = tester.widget<TextField>(principal);
    expect(field.controller!.text, '1000000.25');
    expect(field.controller!.selection.baseOffset, 10);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('months')))
            .focusNode!
            .hasFocus,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('annualRate')))
            .focusNode!
            .hasFocus,
        isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('partPayment')))
            .focusNode!
            .hasFocus,
        isTrue);
  });

  testWidgets('semantic labels and minimum action touch targets',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    expect(find.bySemanticsLabel('Loan outstanding amount'), findsWidgets);
    expect(find.bySemanticsLabel('Rate of interest (% p.a.)'), findsWidgets);
    expect(tester.getSize(find.byKey(const ValueKey('calculate'))).height,
        greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byKey(const ValueKey('reset'))).height,
        greaterThanOrEqualTo(48));
    semantics.dispose();
  });

  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1440, 1000)
  ]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'hub/form/results/errors fit ${size.width}px scale $scale dark $dark',
            (tester) async {
          await mount(tester,
              home: const CalculatorsHomeScreen(),
              size: size,
              scale: scale,
              dark: dark);
          expect(tester.takeException(), isNull);
          await press(tester, 'loan-part-payment');
          expect(tester.takeException(), isNull);
          await fill(tester, principal: '10000000000', payment: '100000.25');
          await press(tester, 'calculate');
          expect(find.text('Reduce EMI'), findsOneWidget);
          expect(find.text('Reduce tenure'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await enter(tester, LoanInputField.partPayment, '10000000001');
          await press(tester, 'calculate');
          expect(
              find.text('Part payment cannot exceed the outstanding amount.'),
              findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
      'standalone calculation needs no providers, Supabase, network or input logs',
      (tester) async {
    final network = RejectNetwork();
    final previous = HttpOverrides.current;
    HttpOverrides.global = network;
    final messages = <String>[];
    final oldDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() {
      HttpOverrides.global = previous;
      debugPrint = oldDebugPrint;
    });
    await mount(tester);
    await fill(tester);
    await press(tester, 'calculate');
    expect(find.text('103 months'), findsOneWidget);
    expect(network.calls, 0);
    expect(messages, isEmpty);
    debugPrint = oldDebugPrint;
  });
}
