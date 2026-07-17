import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/utils/finance.dart';

void main() {
  group('Finance Calculations', () {
    group('Absolute Return', () {
      test('calculates correct absolute return for gains', () {
        final result = calculateAbsoluteReturn(100000, 110000);
        expect(result, closeTo(10.0, 0.001));
      });

      test('calculates correct absolute return for losses', () {
        final result = calculateAbsoluteReturn(100000, 90000);
        expect(result, closeTo(-10.0, 0.001));
      });

      test('returns 0.0 if invested value is zero', () {
        final result = calculateAbsoluteReturn(0, 50000);
        expect(result, equals(0.0));
      });
    });

    group('XIRR (Internal Rate of Return)', () {
      test('returns 0.0 for less than 2 cash flows', () {
        final result = calculateXIRR([]);
        expect(result, equals(0.0));
      });

      test('calculates correct XIRR for a simple 1-year investment', () {
        final cashFlows = [
          CashFlow(-100000, DateTime(2025, 1, 1)),
          CashFlow(110000, DateTime(2026, 1, 1)),
        ];
        final result = calculateXIRR(cashFlows);
        expect(result, closeTo(10.0, 0.01));
      });

      test('calculates correct XIRR for irregular multiple cash flows', () {
        // Simple test case with known XIRR
        final cashFlows = [
          CashFlow(-10000, DateTime(2025, 1, 1)),
          CashFlow(-5000, DateTime(2025, 7, 1)),
          CashFlow(16000, DateTime(2026, 1, 1)),
        ];
        final result = calculateXIRR(cashFlows);
        // Mathematically correct XIRR is ~8.02%
        expect(result, greaterThan(0.0));
        expect(result, closeTo(8.02, 0.05));
      });
    });
  });
}
