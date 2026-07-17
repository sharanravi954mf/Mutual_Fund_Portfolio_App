import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../utils/finance.dart';
import 'factsheet_dialog.dart';

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  late Future<Map<String, dynamic>> _portfolioDataFuture;
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  final dateFormat = DateFormat('dd-MMM-yyyy');

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    final userId = Provider.of<AuthProvider>(context, listen: false).user?.id;
    setState(() {
      _portfolioDataFuture = _fetchClientPortfolioData(userId ?? '');
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

    final allFundsRes = await client
        .from('mutual_funds')
        .select()
        .order('scheme_name', ascending: true);

    final profileRes = await client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (portfolioRes == null) {
      return {
        'portfolio': null,
        'transactions': <Map<String, dynamic>>[],
        'all_funds': List<Map<String, dynamic>>.from(allFundsRes ?? []),
        'profile': profileRes,
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
      'transactions': List<Map<String, dynamic>>.from(transactionsRes ?? []),
      'all_funds': List<Map<String, dynamic>>.from(allFundsRes ?? []),
      'profile': profileRes,
    };
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0C20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151030),
        elevation: 0,
        title: Text(
          "Client Console",
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            tooltip: "Refresh Data",
            onPressed: _refreshData,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.grey),
            tooltip: "Logout",
            onPressed: () {
              Provider.of<AuthProvider>(context, listen: false).signOut();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _portfolioDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE94057)),
                ),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    "Error loading portfolio: ${snapshot.error}",
                    style: GoogleFonts.inter(color: Colors.redAccent),
                  ),
                ),
              );
            }

            final data = snapshot.data;
            final portfolio = data?['portfolio'] as Map<String, dynamic>?;
            final transactions = data?['transactions'] as List<Map<String, dynamic>>;
            final allFunds = data?['all_funds'] as List<Map<String, dynamic>>? ?? [];
            final profile = data?['profile'] as Map<String, dynamic>?;
            
            final clientName = profile != null && profile['full_name'] != null && (profile['full_name'] as String).trim().isNotEmpty
                ? profile['full_name'] as String
                : (user?.email?.split('@')[0] ?? 'Investor');

            final hour = DateTime.now().hour;
            String greeting;
            if (hour >= 3 && hour < 12) {
              greeting = "Good Morning";
            } else if (hour >= 12 && hour < 16) {
              greeting = "Good Afternoon";
            } else if (hour >= 16 && hour <= 23) {
              greeting = "Good Evening";
            } else {
              greeting = "Good Night";
            }

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

            // Remove zero or negative holdings
            final activeHoldings = holdings.values
                .where((h) => (h['units'] as double) > 0.0001)
                .toList();

            return RefreshIndicator(
              onRefresh: () async {
                _refreshData();
              },
              color: const Color(0xFFE94057),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: LayoutBuilder(builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth > 800;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Investor Console",
                                  style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "$greeting, $clientName",
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8A2387).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF8A2387).withOpacity(0.3)),
                            ),
                            child: Text(
                              "Verified Client",
                              style: GoogleFonts.inter(
                                color: const Color(0xFFC04BF0),
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
                                Expanded(child: _buildMetricCard("Total Invested", currencyFormat.format(invested), Icons.account_balance_wallet_outlined, const Color(0xFF8A2387))),
                                const SizedBox(width: 16),
                                Expanded(child: _buildMetricCard("Current Valuation", currencyFormat.format(current), Icons.trending_up, const Color(0xFFE94057))),
                                const SizedBox(width: 16),
                                Expanded(child: _buildMetricCard("Absolute Return", "${absReturn.toStringAsFixed(2)}%", Icons.pie_chart_outline, const Color(0xFFF27121), isReturn: true, returnValue: absReturn)),
                                const SizedBox(width: 16),
                                Expanded(child: _buildMetricCard("Annualized Return (XIRR)", "${xirrVal.toStringAsFixed(2)}%", Icons.offline_bolt_outlined, const Color(0xFF00C853), isReturn: true, returnValue: xirrVal)),
                              ],
                            )
                          : Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: _buildMetricCard("Total Invested", currencyFormat.format(invested), Icons.account_balance_wallet_outlined, const Color(0xFF8A2387))),
                                    const SizedBox(width: 12),
                                    Expanded(child: _buildMetricCard("Current Valuation", currencyFormat.format(current), Icons.trending_up, const Color(0xFFE94057))),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(child: _buildMetricCard("Absolute Return", "${absReturn.toStringAsFixed(2)}%", Icons.pie_chart_outline, const Color(0xFFF27121), isReturn: true, returnValue: absReturn)),
                                    const SizedBox(width: 12),
                                    Expanded(child: _buildMetricCard("Annualized (XIRR)", "${xirrVal.toStringAsFixed(2)}%", Icons.offline_bolt_outlined, const Color(0xFF00C853), isReturn: true, returnValue: xirrVal)),
                                  ],
                                ),
                              ],
                            ),
                      const SizedBox(height: 36),

                      // Search Mutual Funds section
                      Text(
                        "Search & Explore Fund Factsheets",
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Autocomplete<Map<String, dynamic>>(
                        displayStringForOption: (option) => option['scheme_name'] ?? '',
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty || textEditingValue.text.length < 2) {
                            return const Iterable<Map<String, dynamic>>.empty();
                          }
                          return allFunds.where((fund) {
                            final name = (fund['scheme_name'] ?? '').toString().toLowerCase();
                            final code = (fund['scheme_code'] ?? '').toString().toLowerCase();
                            final query = textEditingValue.text.toLowerCase();
                            return name.contains(query) || code.contains(query);
                          });
                        },
                        onSelected: (Map<String, dynamic> selection) {
                          showDialog(
                            context: context,
                            builder: (context) => FactsheetDialog(
                              fundId: selection['id'],
                              schemeName: selection['scheme_name'],
                              category: selection['category'] ?? 'Mutual Fund',
                              fundHouse: selection['fund_house'] ?? 'Sharan Fincorp',
                            ),
                          );
                        },
                        fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: "Enter at least 2 characters to search funds...",
                              hintStyle: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 13),
                              prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                              suffixIcon: textEditingController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                                      onPressed: () {
                                        textEditingController.clear();
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.03),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE94057)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            ),
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              color: const Color(0xFF151030),
                              borderRadius: BorderRadius.circular(12),
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                side: BorderSide(color: Colors.white.withOpacity(0.08)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Container(
                                width: isDesktop ? 600 : constraints.maxWidth - 48,
                                constraints: const BoxConstraints(maxHeight: 200),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (BuildContext context, int index) {
                                    final option = options.elementAt(index);
                                    return ListTile(
                                      title: Text(
                                        option['scheme_name'] ?? '',
                                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        "Code: ${option['scheme_code']} | ${option['category'] ?? 'N/A'}",
                                        style: GoogleFonts.inter(color: Colors.grey, fontSize: 11),
                                      ),
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 36),

                      // Holdings Header
                      // ignore: duplicate_ignore
                      // ignore: duplicate_nodes
                      // ignore: duplicate_ignore
                      // ignore: duplicate_nodes
                      // Holdings Header
                      Text(
                        "Your Portfolio Holdings",
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Holdings list/empty states
                      if (activeHoldings.isEmpty)
                        _buildEmptyStateCard(
                          "No Active Holdings",
                          "Your account does not have any active fund units logged yet. Check back once your financial advisor processes your CAMS/KFintech mailback statements.",
                          Icons.folder_open_outlined,
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.015),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: activeHoldings.length,
                            separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
                            itemBuilder: (context, index) {
                              final h = activeHoldings[index];
                              final units = h['units'] as double;
                              final nav = h['nav'] as double;
                              final curVal = units * nav;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE94057).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.insert_chart_outlined_rounded,
                                    color: Color(0xFFE94057),
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  h['name'],
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    "${units.toStringAsFixed(4)} Units  •  NAV: ₹${nav.toStringAsFixed(2)}",
                                    style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 12),
                                  ),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      currencyFormat.format(curVal),
                                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      h['code'],
                                      style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 11),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => FactsheetDialog(
                                      fundId: h['id'],
                                      schemeName: h['name'],
                                      category: h['category'],
                                      fundHouse: h['fund_house'],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 36),

                      // Transactions List
                      Text(
                        "Recent Transactions Log",
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (transactions.isEmpty)
                        _buildEmptyStateCard(
                          "No Transactions",
                          "We haven't found any historical transaction logs under this portfolio yet.",
                          Icons.history,
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.015),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: transactions.length,
                            separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
                            itemBuilder: (context, index) {
                              final tx = transactions[index];
                              final fund = tx['mutual_funds'] as Map<String, dynamic>?;
                              final type = tx['transaction_type'] as String;
                              final dateStr = tx['execution_date'] as String;
                              final date = DateTime.parse(dateStr);
                              final amt = (tx['amount'] as num).toDouble();
                              final units = (tx['units'] as num).toDouble();

                              final isBuy = type == 'BUY';

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isBuy
                                        ? const Color(0xFF00C853).withOpacity(0.1)
                                        : const Color(0xFFFF1744).withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isBuy ? Icons.add_shopping_cart : Icons.sell_outlined,
                                    color: isBuy ? const Color(0xFF00C853) : const Color(0xFFFF1744),
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                  fund?['scheme_name'] ?? 'Unknown Fund',
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    "${dateFormat.format(date)}  •  ${units.toStringAsFixed(4)} Units",
                                    style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 11),
                                  ),
                                ),
                                trailing: Text(
                                  "${isBuy ? '+' : '-'}${currencyFormat.format(amt)}",
                                  style: GoogleFonts.outfit(
                                    color: isBuy ? const Color(0xFF00C853) : const Color(0xFFFF1744),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
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

  Widget _buildMetricCard(String label, String value, IconData icon, Color accentColor, {bool isReturn = false, double returnValue = 0.0}) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    color: isReturn
                        ? (returnValue >= 0 ? const Color(0xFF00C853) : const Color(0xFFFF1744))
                        : Colors.white,
                    fontSize: 20,
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

  Widget _buildEmptyStateCard(String title, String description, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 36),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}
