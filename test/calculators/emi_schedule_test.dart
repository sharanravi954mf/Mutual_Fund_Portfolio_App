import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/domain/emi_calculator.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/models/emi.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/amortization_schedule_pager.dart';

void main() {
  const calculator = EmiCalculator();
  final date = DateTime(2026, 10, 5);
  EmiResult result(int months, {double rate = 0}) =>
      calculator.calculate(EmiInput(
          principal: 1000000,
          tenure: months,
          tenureUnit: TenureUnit.months,
          annualRatePercent: rate));

  Future<void> mount(WidgetTester tester, EmiResult value,
      {DateTime? calculatedAt, double width = 1440}) async {
    await tester.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AmortizationSchedulePager(
                    schedule: value.schedule,
                    calculatedAt: calculatedAt ?? date)))));
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

  testWidgets(
      'calendar labels and new schedules reset paging without stale rows',
      (tester) async {
    final value = result(25);
    await mount(tester, value);
    expect(find.text('Month 1 · Nov 2026'), findsOneWidget);
    expect(find.text('Month 2 · Dec 2026'), findsOneWidget);
    expect(find.text('Month 3 · Jan 2027'), findsOneWidget);
    await press(tester, 'schedule-next');
    expect(find.text('Month 13 · Nov 2027'), findsOneWidget);
    await mount(tester, value);
    expect(find.text('Months 13–24 of 25'), findsOneWidget);
    await mount(tester, result(1), calculatedAt: DateTime(2026, 12, 31));
    expect(find.text('Months 1–1 of 1'), findsOneWidget);
    expect(find.text('Month 1 · Jan 2027'), findsOneWidget);
    expect(rowLabels(), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-month-13')), findsNothing);
  });

  testWidgets('320px cards label all five money fields', (tester) async {
    await mount(tester, result(120, rate: 8.5), width: 320);
    expect(find.byType(DataTable), findsNothing);
    for (final label in [
      'Opening outstanding: ₹10,00,000.00',
      'EMI / payment: ₹12,398.57',
      'Interest: ₹7,083.33',
      'Principal repaid: ₹5,315.24',
      'Closing outstanding: ₹9,94,684.76',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(rowLabels(), findsNWidgets(12));
    expect(tester.takeException(), isNull);
  });
}
