import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/portfolio/data/portfolio_repository.dart';
import 'package:mutual_fund_portfolio_app/features/portfolio/services/portfolio_dashboard_service.dart';

void main() {
  const service = PortfolioDashboardService();

  InvestorPortfolioData source({
    Map<String, dynamic>? portfolio,
    List<Map<String, dynamic>> transactions = const [],
  }) {
    return InvestorPortfolioData(
      portfolio: portfolio,
      transactions: transactions,
      allFunds: const [],
      profile: const {'full_name': 'Investor One'},
    );
  }

  Map<String, dynamic> transaction({
    required String type,
    required num amount,
    required num units,
    required String date,
    String fundId = 'fund-1',
    String scheme = 'Alpha Fund',
    String house = 'Alpha AMC',
    String category = 'Equity',
    num nav = 20,
  }) =>
      {
        'transaction_type': type,
        'amount': amount,
        'units': units,
        'execution_date': date,
        'mutual_funds': {
          'id': fundId,
          'scheme_code': fundId,
          'scheme_name': scheme,
          'fund_house': house,
          'category': category,
          'current_nav': nav,
        },
      };

  test('calculates summary values and a positive return from stored totals',
      () {
    final dashboard = service.build(source(
      portfolio: {
        'total_invested_value': 100000,
        'current_market_value': 125000,
        'last_updated': '2026-07-22T10:00:00Z',
      },
    ));

    expect(dashboard.summary.investedAmount, 100000);
    expect(dashboard.summary.currentValue, 125000);
    expect(dashboard.summary.gainLoss, 25000);
    expect(dashboard.summary.returnPercentage, 25);
    expect(dashboard.summary.lastUpdated, isNotNull);
  });

  test('represents a negative gain/loss and zero-investment return safely', () {
    final loss = service.build(source(portfolio: {
      'total_invested_value': 100,
      'current_market_value': 80,
    }));
    final noInvestment = service.build(source(portfolio: {
      'total_invested_value': 0,
      'current_market_value': 80,
    }));

    expect(loss.summary.gainLoss, -20);
    expect(loss.summary.returnPercentage, -20);
    expect(noInvestment.summary.returnPercentage, isNull);
  });

  test('reports an empty portfolio without fabricating metrics', () {
    final dashboard = service.build(source());

    expect(dashboard.isEmpty, isTrue);
    expect(dashboard.holdings, isEmpty);
    expect(dashboard.transactions, isEmpty);
  });

  test('aggregates buy and sell transactions into active holdings', () {
    final dashboard = service.build(source(transactions: [
      transaction(type: 'BUY', amount: 1000, units: 100, date: '2026-01-01'),
      transaction(type: 'SELL', amount: 300, units: 30, date: '2026-02-01'),
    ]));

    expect(dashboard.holdings, hasLength(1));
    expect(dashboard.holdings.single.units, 70);
    expect(dashboard.holdings.single.investedAmount, 700);
    expect(dashboard.holdings.single.currentValue, 1400);
  });

  test('uses stored AMC and category values for allocations', () {
    final dashboard = service.build(source(transactions: [
      transaction(
        type: 'BUY',
        amount: 1000,
        units: 10,
        date: '2026-01-01',
        fundId: 'one',
        house: 'AMC One',
        category: 'Equity',
        nav: 10,
      ),
      transaction(
        type: 'BUY',
        amount: 1000,
        units: 30,
        date: '2026-01-01',
        fundId: 'two',
        house: 'AMC Two',
        category: 'Debt',
        nav: 10,
      ),
    ]));

    expect(
        dashboard.amcAllocation
            .map((item) => item.percentage)
            .reduce((a, b) => a + b),
        closeTo(100, 0.001));
    expect(dashboard.categoryAllocation.first.label, 'Debt');
    expect(dashboard.categoryAllocation.first.percentage, 75);
  });

  test('orders transaction history newest first and flags switch partial data',
      () {
    final dashboard = service.build(source(transactions: [
      transaction(type: 'BUY', amount: 100, units: 10, date: '2026-01-01'),
      transaction(type: 'SWITCH', amount: 50, units: 5, date: '2026-03-01'),
    ]));

    expect(dashboard.transactions.first.type, 'SWITCH');
    expect(dashboard.warnings, isNotEmpty);
  });
}
