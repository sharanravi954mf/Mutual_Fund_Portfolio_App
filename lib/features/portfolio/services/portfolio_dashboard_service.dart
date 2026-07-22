import '../data/portfolio_repository.dart';
import '../models/portfolio_dashboard_models.dart';

class PortfolioDashboardService {
  const PortfolioDashboardService();

  PortfolioDashboardData build(InvestorPortfolioData source) {
    final portfolio = source.portfolio;
    final summary = PortfolioSummary(
      investedAmount: _number(portfolio?['total_invested_value']),
      currentValue: _number(portfolio?['current_market_value']),
      gainLoss: _number(portfolio?['current_market_value']) -
          _number(portfolio?['total_invested_value']),
      returnPercentage: _returnPercentage(
        _number(portfolio?['total_invested_value']),
        _number(portfolio?['current_market_value']),
      ),
      lastUpdated: _date(portfolio?['last_updated']),
    );

    final hasSwitches = source.transactions.any(
      (transaction) => transaction['transaction_type'] == 'SWITCH',
    );
    final holdings = _buildHoldings(source.transactions);
    final transactions = _buildTransactions(source.transactions);

    return PortfolioDashboardData(
      investorName: source.profile?['full_name'] as String?,
      summary: summary,
      holdings: holdings,
      transactions: transactions,
      amcAllocation: _buildAllocation(
        holdings,
        (holding) => holding.fundHouse?.trim().isNotEmpty == true
            ? holding.fundHouse!.trim()
            : 'Not classified',
      ),
      categoryAllocation: _buildAllocation(
        holdings,
        (holding) => holding.category?.trim().isNotEmpty == true
            ? holding.category!.trim()
            : 'Not classified',
      ),
      warnings: hasSwitches
          ? const [
              'Some switch transactions are shown in your history but are not used in holdings totals.',
            ]
          : const [],
      hasPortfolio: portfolio != null,
    );
  }

  List<HoldingSummary> _buildHoldings(
    List<Map<String, dynamic>> source,
  ) {
    final holdings = <String, _MutableHolding>{};
    for (final transaction in source) {
      final fund = transaction['mutual_funds'] as Map<String, dynamic>?;
      if (fund == null) continue;
      final type = transaction['transaction_type'] as String?;
      if (type != 'BUY' && type != 'SELL') continue;

      final key = (fund['id'] ?? fund['scheme_code']).toString();
      final holding = holdings.putIfAbsent(
        key,
        () => _MutableHolding(
          fundId: fund['id']?.toString() ?? '',
          schemeCode: fund['scheme_code']?.toString() ?? '',
          schemeName: fund['scheme_name']?.toString() ?? 'Unknown fund',
          fundHouse: fund['fund_house'] as String?,
          category: fund['category'] as String?,
          nav: _number(fund['current_nav']),
        ),
      );
      final direction = type == 'BUY' ? 1 : -1;
      holding.units += direction * _number(transaction['units']);
      holding.investedAmount += direction * _number(transaction['amount']);
    }

    return holdings.values
        .where((holding) => holding.units > 0.0001)
        .map((holding) => HoldingSummary(
              fundId: holding.fundId,
              schemeCode: holding.schemeCode,
              schemeName: holding.schemeName,
              fundHouse: holding.fundHouse,
              category: holding.category,
              units: holding.units,
              nav: holding.nav,
              currentValue: holding.units * holding.nav,
              investedAmount: holding.investedAmount,
            ))
        .toList()
      ..sort((a, b) => b.currentValue.compareTo(a.currentValue));
  }

  List<TransactionSummary> _buildTransactions(
    List<Map<String, dynamic>> source,
  ) {
    final transactions = source
        .map((transaction) {
          final fund = transaction['mutual_funds'] as Map<String, dynamic>?;
          final date = _date(transaction['execution_date']);
          if (date == null) return null;
          return TransactionSummary(
            schemeName: fund?['scheme_name']?.toString() ?? 'Unknown fund',
            type: transaction['transaction_type']?.toString() ?? 'Unknown',
            amount: _number(transaction['amount']),
            units: _number(transaction['units']),
            executionDate: date,
          );
        })
        .whereType<TransactionSummary>()
        .toList()
      ..sort((a, b) => b.executionDate.compareTo(a.executionDate));
    return transactions;
  }

  List<AllocationSummary> _buildAllocation(
    List<HoldingSummary> holdings,
    String Function(HoldingSummary) labelFor,
  ) {
    final total =
        holdings.fold<double>(0, (sum, holding) => sum + holding.currentValue);
    if (total <= 0) return const [];
    final values = <String, double>{};
    for (final holding in holdings) {
      final label = labelFor(holding);
      values[label] = (values[label] ?? 0) + holding.currentValue;
    }
    final allocation = values.entries
        .map((entry) => AllocationSummary(
              label: entry.key,
              value: entry.value,
              percentage: (entry.value / total) * 100,
            ))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return allocation;
  }

  double _number(Object? value) => value is num ? value.toDouble() : 0;

  DateTime? _date(Object? value) => value is String
      ? DateTime.tryParse(value)
      : value is DateTime
          ? value
          : null;

  double? _returnPercentage(double invested, double current) =>
      invested == 0 ? null : ((current - invested) / invested) * 100;
}

class _MutableHolding {
  _MutableHolding({
    required this.fundId,
    required this.schemeCode,
    required this.schemeName,
    required this.fundHouse,
    required this.category,
    required this.nav,
  });

  final String fundId;
  final String schemeCode;
  final String schemeName;
  final String? fundHouse;
  final String? category;
  final double nav;
  double units = 0;
  double investedAmount = 0;
}
