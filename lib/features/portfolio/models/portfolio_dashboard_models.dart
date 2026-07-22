class PortfolioSummary {
  const PortfolioSummary({
    required this.investedAmount,
    required this.currentValue,
    required this.gainLoss,
    required this.returnPercentage,
    required this.lastUpdated,
  });

  final double investedAmount;
  final double currentValue;
  final double gainLoss;
  final double? returnPercentage;
  final DateTime? lastUpdated;
}

class HoldingSummary {
  const HoldingSummary({
    required this.fundId,
    required this.schemeCode,
    required this.schemeName,
    required this.fundHouse,
    required this.category,
    required this.units,
    required this.nav,
    required this.currentValue,
    required this.investedAmount,
  });

  final String fundId;
  final String schemeCode;
  final String schemeName;
  final String? fundHouse;
  final String? category;
  final double units;
  final double nav;
  final double currentValue;
  final double investedAmount;

  double get gainLoss => currentValue - investedAmount;
  double? get returnPercentage =>
      investedAmount == 0 ? null : (gainLoss / investedAmount) * 100;
}

class TransactionSummary {
  const TransactionSummary({
    required this.schemeName,
    required this.type,
    required this.amount,
    required this.units,
    required this.executionDate,
  });

  final String schemeName;
  final String type;
  final double amount;
  final double units;
  final DateTime executionDate;
}

class AllocationSummary {
  const AllocationSummary({
    required this.label,
    required this.value,
    required this.percentage,
  });

  final String label;
  final double value;
  final double percentage;
}

class PortfolioDashboardData {
  const PortfolioDashboardData({
    required this.investorName,
    required this.summary,
    required this.holdings,
    required this.transactions,
    required this.amcAllocation,
    required this.categoryAllocation,
    required this.warnings,
    required this.hasPortfolio,
  });

  final String? investorName;
  final PortfolioSummary summary;
  final List<HoldingSummary> holdings;
  final List<TransactionSummary> transactions;
  final List<AllocationSummary> amcAllocation;
  final List<AllocationSummary> categoryAllocation;
  final List<String> warnings;
  final bool hasPortfolio;

  bool get isEmpty => !hasPortfolio && transactions.isEmpty;
}
