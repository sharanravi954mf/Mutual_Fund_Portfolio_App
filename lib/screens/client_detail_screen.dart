import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/theme_provider.dart';
import '../utils/finance.dart';
import 'factsheet_dialog.dart';

class ClientDetailScreen extends StatefulWidget {
  final String clientId;
  final String clientName;
  final String clientPan;

  const ClientDetailScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.clientPan,
  });

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  late Future<Map<String, dynamic>> _portfolioDataFuture;
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  final dateFormat = DateFormat('dd-MMM-yyyy');

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _portfolioDataFuture = _fetchClientPortfolioData(widget.clientId);
    });
  }

  Future<Map<String, dynamic>> _fetchClientPortfolioData(String userId) async {
    final client = Supabase.instance.client;

    // 1. Fetch portfolio metrics
    final portfolioRes = await client
        .from('portfolios')
        .select()
        .eq('client_id', userId)
        .maybeSingle();

    if (portfolioRes == null) {
      return {
        'portfolio': null,
        'transactions': <Map<String, dynamic>>[],
      };
    }

    // 2. Fetch transactions joined with mutual_funds
    final transactionsRes = await client
        .from('transactions')
        .select('*, mutual_funds(*)')
        .eq('portfolio_id', portfolioRes['id'])
        .order('execution_date', ascending: false);

    return {
      'portfolio': portfolioRes,
      'transactions': List<Map<String, dynamic>>.from(transactionsRes),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode(context);
    final colors = AppThemeColors(isDark);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        title: Text(
          widget.clientName,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: colors.textSecondary),
            tooltip: "Refresh Data",
            onPressed: _refreshData,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _portfolioDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                ),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    "Error loading portfolio: ${snapshot.error}",
                    style: GoogleFonts.inter(color: colors.error),
                  ),
                ),
              );
            }

            final data = snapshot.data;
            final portfolio = data?['portfolio'] as Map<String, dynamic>?;
            final transactions = data?['transactions'] as List<Map<String, dynamic>>;

            final double invested = portfolio != null
                ? (portfolio['total_invested_value'] as num).toDouble()
                : 0.0;
            final double current = portfolio != null
                ? (portfolio['current_market_value'] as num).toDouble()
                : 0.0;
            final double absReturn = calculateAbsoluteReturn(invested, current);

            // Calculate XIRR
            final cashFlows = <CashFlow>[];
            for (var tx in transactions) {
              final type = tx['transaction_type'] as String;
              final amount = (tx['amount'] as num).toDouble();
              final date = DateTime.parse(tx['execution_date'] as String);
              if (type == 'BUY') {
                cashFlows.add(CashFlow(-amount, date));
              } else if (type == 'SELL') {
                cashFlows.add(CashFlow(amount, date));
              }
            }
            if (current > 0) {
              cashFlows.add(CashFlow(current, DateTime.now()));
            }
            final double xirrVal = calculateXIRR(cashFlows);

            // Group transactions by mutual fund code to calculate holdings
            final holdings = <String, Map<String, dynamic>>{};
            for (var tx in transactions) {
              final fund = tx['mutual_funds'] as Map<String, dynamic>?;
              if (fund == null) continue;
              final code = fund['scheme_code'] as String;
              final name = fund['scheme_name'] as String;
              final type = tx['transaction_type'] as String;
              final units = (tx['units'] as num).toDouble();
              final nav = (fund['current_nav'] as num).toDouble();
              final txAmount = (tx['amount'] as num).toDouble();

              if (!holdings.containsKey(code)) {
                holdings[code] = {
                  'id': fund['id'] ?? '',
                  'code': code,
                  'name': name,
                  'units': 0.0,
                  'invested': 0.0,
                  'nav': nav,
                  'category': fund['category'] ?? 'Mutual Fund',
                  'fund_house': fund['fund_house'] ?? 'Sharan Fincorp',
                };
              }

              if (type == 'BUY') {
                holdings[code]!['units'] += units;
                holdings[code]!['invested'] += txAmount;
              } else if (type == 'SELL') {
                holdings[code]!['units'] -= units;
                holdings[code]!['invested'] -= txAmount;
              }
            }

            final activeHoldings = holdings.values
                .where((h) => (h['units'] as double) > 0.0001)
                .toList();

            return RefreshIndicator(
              onRefresh: () async {
                _refreshData();
              },
              color: colors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: LayoutBuilder(builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth > 800;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header info
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "PAN: ${widget.clientPan.toUpperCase()}",
                                style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Client Portfolio Analysis",
                                style: GoogleFonts.outfit(
                                  color: colors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: colors.activeBackground,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: colors.border),
                            ),
                            child: Text(
                              "Active Portfolio",
                              style: GoogleFonts.inter(
                                color: colors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Metric Cards Grid
                      isDesktop
                          ? Row(
                              children: [
                                Expanded(child: _buildMetricCard(colors, "Total Invested", currencyFormat.format(invested), Icons.account_balance_wallet_outlined, colors.primary)),
                                const SizedBox(width: 16),
                                Expanded(child: _buildMetricCard(colors, "Current Valuation", currencyFormat.format(current), Icons.trending_up, colors.primary)),
                                const SizedBox(width: 16),
                                Expanded(child: _buildMetricCard(colors, "Absolute Return", "${absReturn.toStringAsFixed(2)}%", Icons.pie_chart_outline, colors.profit, isReturn: true, returnValue: absReturn)),
                                const SizedBox(width: 16),
                                Expanded(child: _buildMetricCard(colors, "Annualized (XIRR)", "${xirrVal.toStringAsFixed(2)}%", Icons.offline_bolt_outlined, colors.profit, isReturn: true, returnValue: xirrVal)),
                              ],
                            )
                          : Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: _buildMetricCard(colors, "Total Invested", currencyFormat.format(invested), Icons.account_balance_wallet_outlined, colors.primary)),
                                    const SizedBox(width: 12),
                                    Expanded(child: _buildMetricCard(colors, "Current Valuation", currencyFormat.format(current), Icons.trending_up, colors.primary)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(child: _buildMetricCard(colors, "Absolute Return", "${absReturn.toStringAsFixed(2)}%", Icons.pie_chart_outline, colors.profit, isReturn: true, returnValue: absReturn)),
                                    const SizedBox(width: 12),
                                    Expanded(child: _buildMetricCard(colors, "Annualized (XIRR)", "${xirrVal.toStringAsFixed(2)}%", Icons.offline_bolt_outlined, colors.profit, isReturn: true, returnValue: xirrVal)),
                                  ],
                                ),
                              ],
                            ),
                      const SizedBox(height: 36),

                      // Holdings Header
                      Text(
                        "Portfolio Holdings",
                        style: GoogleFonts.outfit(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Holdings list/empty states
                      if (activeHoldings.isEmpty)
                        _buildEmptyStateCard(
                          colors,
                          "No Active Holdings",
                          "This client does not have any active fund units logged yet.",
                          Icons.folder_open_outlined,
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.border, width: 1),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: activeHoldings.length,
                            separatorBuilder: (context, index) => Divider(color: colors.border, height: 1),
                            itemBuilder: (context, index) {
                              final h = activeHoldings[index];
                              final units = h['units'] as double;
                              final nav = h['nav'] as double;
                              final curVal = units * nav;

                              return Container(
                                color: index % 2 == 1 ? colors.tableRowAlt : colors.surface,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: colors.activeBackground,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.insert_chart_outlined_rounded,
                                      color: colors.primary,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    h['name'] as String,
                                    style: GoogleFonts.outfit(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      "Code: ${h['code']}  •  ${units.toStringAsFixed(4)} Units  •  NAV: ₹${nav.toStringAsFixed(2)}",
                                      style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 12),
                                    ),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        currencyFormat.format(curVal),
                                        style: GoogleFonts.outfit(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Invested: ${currencyFormat.format(h['invested'])}",
                                        style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => FactsheetDialog(
                                        fundId: h['id'] as String,
                                        schemeName: h['name'] as String,
                                        category: h['category'] as String,
                                        fundHouse: h['fund_house'] as String,
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 36),

                      // Transactions Header
                      Text(
                        "Transaction History",
                        style: GoogleFonts.outfit(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (transactions.isEmpty)
                        _buildEmptyStateCard(
                          colors,
                          "No Transactions",
                          "We haven't found any historical transaction logs under this portfolio yet.",
                          Icons.history,
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.border, width: 1),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: transactions.length,
                            separatorBuilder: (context, index) => Divider(color: colors.border, height: 1),
                            itemBuilder: (context, index) {
                              final tx = transactions[index];
                              final fund = tx['mutual_funds'] as Map<String, dynamic>?;
                              final type = tx['transaction_type'] as String;
                              final dateStr = tx['execution_date'] as String;
                              final date = DateTime.parse(dateStr);
                              final amt = (tx['amount'] as num).toDouble();
                              final units = (tx['units'] as num).toDouble();

                              final isBuy = type == 'BUY';

                              return Container(
                                color: index % 2 == 1 ? colors.tableRowAlt : colors.surface,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isBuy
                                          ? colors.profit.withValues(alpha: 0.1)
                                          : colors.error.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isBuy ? Icons.add_shopping_cart : Icons.sell_outlined,
                                      color: isBuy ? colors.profit : colors.error,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    fund?['scheme_name'] ?? 'Unknown Fund',
                                    style: GoogleFonts.outfit(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      "${dateFormat.format(date)}  •  ${units.toStringAsFixed(4)} Units",
                                      style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 11),
                                    ),
                                  ),
                                  trailing: Text(
                                    "${isBuy ? '+' : '-'}${currencyFormat.format(amt)}",
                                    style: GoogleFonts.outfit(
                                      color: isBuy ? colors.profit : colors.error,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                }),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMetricCard(AppThemeColors colors, String label, String value, IconData icon, Color accentColor, {bool isReturn = false, double returnValue = 0.0}) {
    return Container(
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.activeBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    color: isReturn
                        ? (returnValue >= 0 ? colors.profit : colors.error)
                        : colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStateCard(AppThemeColors colors, String title, String description, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Column(
        children: [
          Icon(icon, color: colors.textSecondary, size: 36),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.outfit(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}
