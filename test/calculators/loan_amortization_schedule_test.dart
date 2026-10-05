import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/domain/loan_part_payment_calculator.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/models/loan_part_payment.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/loan_amortization_schedule.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/loan_part_payment_screen.dart';

void main() {
  const calculator = LoanPartPaymentCalculator();
  final date = DateTime(2026, 10, 5);
  LoanPartPaymentResult result(int months,
          {double rate = 0, double payment = 0}) =>
      calculator.calculate(LoanPartPaymentInput(
          principal: 1000000,
          months: months,
          annualRatePercent: rate,
          partPayment: payment));

  Future<void> mount(WidgetTester tester, LoanPartPaymentResult value,
      {DateTime? calculatedAt, double width = 1440}) async {
    await tester.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: LoanAmortizationSchedule(
                    result: value, calculatedAt: calculatedAt ?? date)))));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String key) async {
    final button = find.byKey(ValueKey(key));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Finder rowLabels() => find.byWidgetPredicate((widget) =>
      widget is Text &&
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('schedule-month-'));

  for (final months in [1, 11, 12, 13, 25, 120, 600]) {
    testWidgets(
        '$months months: bounded pages, next/previous and final partial page',
        (tester) async {
      await mount(tester, result(months));
      final pages = (months / 12).ceil();
      for (var page = 0; page < pages; page++) {
        final start = page * 12 + 1;
        final end = (start + 11).clamp(0, months);
        expect(find.text('Months $start–$end of $months'), findsOneWidget);
        expect(rowLabels(), findsNWidgets(end - start + 1));
        expect(find.byKey(ValueKey('schedule-month-$start')), findsOneWidget);
        expect(find.byKey(ValueKey('schedule-month-$end')), findsOneWidget);
        expect(find.byKey(ValueKey('schedule-month-${end + 1}')), findsNothing);
        expect(
            tester
                    .widget<OutlinedButton>(
                        find.byKey(const ValueKey('schedule-previous')))
                    .onPressed ==
                null,
            page == 0);
        expect(
            tester
                    .widget<OutlinedButton>(
                        find.byKey(const ValueKey('schedule-next')))
                    .onPressed ==
                null,
            page == pages - 1);
        if (page < pages - 1) await press(tester, 'schedule-next');
      }
      if (pages > 1) {
        await press(tester, 'schedule-previous');
        final start = (pages - 2) * 12 + 1;
        expect(find.text('Months $start–${start + 11} of $months'),
            findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('scenario switch resets page and exposes the 103rd final payment',
      (tester) async {
    await mount(tester, result(120, rate: 8.5, payment: 100000));
    await press(tester, 'schedule-next');
    expect(find.text('Months 13–24 of 120'), findsOneWidget);
    await press(tester, 'schedule-tenure');
    expect(find.text('Months 1–12 of 103'), findsOneWidget);
    for (var page = 0; page < 8; page++) {
      await press(tester, 'schedule-next');
    }
    expect(find.text('Months 97–103 of 103'), findsOneWidget);
    expect(rowLabels(), findsNWidgets(7));
    expect(find.text('Month 103 · May 2035'), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-month-104')), findsNothing);
    expect(find.text('₹3,406.37'),
        findsNWidgets(3)); // Prior closing, last opening/principal.
    expect(find.text('₹3,430.50'), findsOneWidget);
    expect(find.text('₹24.13'), findsOneWidget);
    expect(find.text('₹0.00'), findsOneWidget);
    await press(tester, 'schedule-emi');
    expect(find.text('Months 1–12 of 120'), findsOneWidget);
  });

  testWidgets('calendar labels keep precise month numbers and roll over years',
      (tester) async {
    await mount(tester, result(25));
    expect(find.text('Month 1 · Nov 2026'), findsOneWidget);
    expect(find.text('Month 2 · Dec 2026'), findsOneWidget);
    expect(find.text('Month 3 · Jan 2027'), findsOneWidget);
    await press(tester, 'schedule-next');
    expect(find.text('Month 13 · Nov 2027'), findsOneWidget);
    await mount(tester, result(25), calculatedAt: DateTime(2026, 12, 31));
    expect(find.text('Month 1 · Jan 2027'), findsOneWidget);
    expect(find.text('Months 1–12 of 25'), findsOneWidget);
  });

  testWidgets(
      'replacement result clears old page and full payoff removes every row',
      (tester) async {
    await mount(tester, result(600));
    await press(tester, 'schedule-next');
    await mount(tester, result(1));
    expect(find.text('Months 1–1 of 1'), findsOneWidget);
    expect(rowLabels(), findsOneWidget);
    await mount(tester, result(600, payment: 1000000));
    expect(rowLabels(), findsNothing);
    expect(find.byKey(const ValueKey('schedule-next')), findsNothing);
    expect(
        find.text(
            'No future EMI schedule — the entered part payment fully repays the outstanding principal.'),
        findsOneWidget);
  });

  testWidgets(
      'mobile cards label every monetary field and controls have semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester, result(120, rate: 8.5, payment: 100000), width: 320);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Opening outstanding: ₹9,00,000.00'), findsOneWidget);
      expect(find.text('EMI / payment: ₹11,158.71'), findsNWidgets(12));
      expect(find.text('Interest: ₹6,375.00'), findsOneWidget);
      expect(find.text('Principal repaid: ₹4,783.71'), findsOneWidget);
      expect(find.text('Closing outstanding: ₹8,95,216.29'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Show reduced EMI schedule')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Show reduced tenure schedule')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Previous schedule page')),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp('Next schedule page')), findsOneWidget);
      await press(tester, 'schedule-tenure');
      expect(find.text('EMI / payment: ₹12,398.57'), findsNWidgets(12));
      expect(find.text('Principal repaid: ₹6,023.57'), findsOneWidget);
      expect(find.text('Closing outstanding: ₹8,93,976.43'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'screen captures injected clock once; paging/rebuild retains calendar labels',
      (tester) async {
    var now = DateTime(2026, 10, 5);
    var clockReads = 0;
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: LoanPartPaymentScreen(clock: () {
      clockReads++;
      return now;
    })));
    for (final (field, text) in [
      ('principal', '1000000'),
      ('months', '120'),
      ('annualRate', '8.5'),
      ('partPayment', '100000')
    ]) {
      await tester.enterText(find.byKey(ValueKey(field)), text);
      await tester.pumpAndSettle();
    }
    await press(tester, 'calculate');
    expect(clockReads, 1);
    expect(find.text('Month 1 · Nov 2026'), findsOneWidget);
    now = DateTime(2026, 12, 31);
    await press(tester, 'schedule-next');
    expect(find.text('Month 13 · Nov 2027'), findsOneWidget);
    await press(tester, 'schedule-tenure');
    expect(find.text('Month 1 · Nov 2026'), findsOneWidget);
    expect(clockReads, 1);
    await press(tester, 'calculate');
    expect(clockReads, 2);
    expect(find.text('Month 1 · Jan 2027'), findsOneWidget);
    expect(find.text('Months 1–12 of 120'), findsOneWidget);
  });
}
