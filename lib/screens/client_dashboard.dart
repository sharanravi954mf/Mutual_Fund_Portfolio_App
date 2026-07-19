import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/language_provider.dart';
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
  TextEditingController? _autocompleteTextController;
  int _selectedTab = 0; // 0: Portfolio, 1: Factsheets, 2: Settings, 3: About Us, 4: Contact Us

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
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode(context);
    final colors = AppThemeColors(isDark);
    final t = languageProvider.translate;

    return FutureBuilder<Map<String, dynamic>>(
      future: _portfolioDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: colors.background,
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              ),
            ),
          );
        } else if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: colors.background,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  "Error loading portfolio: ${snapshot.error}",
                  style: GoogleFonts.inter(color: Colors.redAccent),
                ),
              ),
            ),
          );
        }

        final data = snapshot.data;
        final portfolio = data?['portfolio'] as Map<String, dynamic>?;
        final transactions = data?['transactions'] as List<Map<String, dynamic>>? ?? [];
        final allFunds = data?['all_funds'] as List<Map<String, dynamic>>? ?? [];
        final profile = data?['profile'] as Map<String, dynamic>?;
        
        final clientName = profile != null && profile['full_name'] != null && (profile['full_name'] as String).trim().isNotEmpty
            ? profile['full_name'] as String
            : (user?.email?.split('@')[0] ?? 'Investor');

        final hour = DateTime.now().hour;
        String greeting;
        if (hour >= 3 && hour < 12) {
          greeting = t('logout') == 'लॉगआउट' ? "शुभ प्रभात" : "Good Morning";
        } else if (hour >= 12 && hour < 16) {
          greeting = t('logout') == 'लॉगआउट' ? "शुभ दोपहर" : "Good Afternoon";
        } else if (hour >= 16 && hour <= 23) {
          greeting = t('logout') == 'लॉगआउट' ? "शुभ संध्या" : "Good Evening";
        } else {
          greeting = t('logout') == 'लॉगआउट' ? "शुभ रात्रि" : "Good Night";
        }

        // Calculations
        final double invested = portfolio != null ? (portfolio['total_invested_value'] as num).toDouble() : 0.0;
        final double current = portfolio != null ? (portfolio['current_market_value'] as num).toDouble() : 0.0;
        final double absReturn = calculateAbsoluteReturn(invested, current);

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

        // Group holdings
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
        final activeHoldings = holdings.values.where((h) => (h['units'] as double) > 0.0001).toList();

        // Responsive Sidebar Flag
        final showSidebar = MediaQuery.of(context).size.width > 900;

        // Dynamic Main Panel AppBar Title
        String appBarTitle = '';
        if (_selectedTab == 0) {
          appBarTitle = "$greeting, $clientName";
        } else if (_selectedTab == 1) {
          appBarTitle = t('search_explore_factsheets');
        } else if (_selectedTab == 2) {
          appBarTitle = t('settings');
        } else if (_selectedTab == 3) {
          appBarTitle = t('about_us');
        } else if (_selectedTab == 4) {
          appBarTitle = t('contact_us');
        }

        // Active Body Content Selection
        Widget tabContent;
        if (_selectedTab == 0) {
          tabContent = _buildPortfolioContent(
            portfolio: portfolio,
            transactions: transactions,
            invested: invested,
            current: current,
            absReturn: absReturn,
            xirrVal: xirrVal,
            activeHoldings: activeHoldings,
            colors: colors,
            t: t,
            showSidebar: showSidebar,
          );
        } else if (_selectedTab == 1) {
          tabContent = _buildFactsheetsContent(
            allFunds: allFunds,
            colors: colors,
            t: t,
            showSidebar: showSidebar,
          );
        } else if (_selectedTab == 2) {
          tabContent = _buildSettingsContent(
            colors: colors,
            t: t,
          );
        } else if (_selectedTab == 3) {
          tabContent = _buildAboutUsContent(
            colors: colors,
            t: t,
          );
        } else {
          tabContent = _buildContactUsContent(
            colors: colors,
            t: t,
          );
        }

        return Scaffold(
          backgroundColor: colors.background,
          body: Row(
            children: [
              // Sidebar left panel (Desktop only)
              if (showSidebar)
                Container(
                  width: 260,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border(right: BorderSide(color: colors.border)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Row(
                          children: [
                            Icon(Icons.shield_outlined, color: colors.primary, size: 28),
                            const SizedBox(width: 12),
                            Text(
                              t('investor_console').split(' ')[0] + " Central",
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(color: colors.border, height: 1),
                      const SizedBox(height: 16),
                      _buildSidebarItem(0, t('portfolio'), Icons.account_balance_wallet_outlined, colors),
                      _buildSidebarItem(1, t('search_explore_factsheets').split(' ')[0] + " Factsheets", Icons.document_scanner_outlined, colors),
                      _buildSidebarItem(2, t('settings'), Icons.settings_outlined, colors),
                      _buildSidebarItem(3, t('about_us_nav'), Icons.info_outline, colors),
                      _buildSidebarItem(4, t('contact_us'), Icons.contact_support_outlined, colors),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          "v1.0.2 - Premium",
                          style: GoogleFonts.inter(color: colors.textMuted, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),

              // Main content panel
              Expanded(
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    backgroundColor: colors.surface,
                    elevation: 0,
                    iconTheme: IconThemeData(color: colors.textPrimary),
                    title: Text(
                      appBarTitle,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    actions: [
                      IconButton(
                        icon: Icon(Icons.refresh, color: colors.textSecondary),
                        tooltip: t('refresh_data'),
                        onPressed: _refreshData,
                      ),
                      const SizedBox(width: 8),
                      // My Account Profile dropdown menu button
                      PopupMenuButton<int>(
                        icon: CircleAvatar(
                          radius: 16,
                          backgroundColor: colors.primary.withOpacity(0.15),
                          child: Text(
                            clientName.isNotEmpty ? clientName[0].toUpperCase() : 'U',
                            style: GoogleFonts.outfit(
                              color: colors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        offset: const Offset(0, 48),
                        color: colors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colors.border),
                        ),
                        onSelected: (val) {
                          if (val == 1) {
                            authProvider.signOut();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            enabled: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  clientName,
                                  style: GoogleFonts.outfit(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  user?.email ?? '',
                                  style: GoogleFonts.inter(
                                    color: colors.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 1,
                            child: Row(
                              children: [
                                Icon(Icons.logout, color: colors.primary, size: 18),
                                const SizedBox(width: 10),
                                Text(
                                  t('logout'),
                                  style: GoogleFonts.inter(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                  bottomNavigationBar: !showSidebar
                      ? BottomNavigationBar(
                          currentIndex: _selectedTab,
                          backgroundColor: colors.surface,
                          selectedItemColor: colors.primary,
                          unselectedItemColor: colors.textSecondary,
                          type: BottomNavigationBarType.fixed,
                          onTap: (index) {
                            setState(() {
                              _selectedTab = index;
                            });
                          },
                          items: [
                            BottomNavigationBarItem(icon: const Icon(Icons.account_balance_wallet_outlined), label: t('portfolio').split(' ')[0]),
                            BottomNavigationBarItem(icon: const Icon(Icons.document_scanner_outlined), label: "Factsheets"),
                            BottomNavigationBarItem(icon: const Icon(Icons.settings_outlined), label: t('settings')),
                            BottomNavigationBarItem(icon: const Icon(Icons.info_outline), label: t('about_us_nav').split(' ')[0]),
                            BottomNavigationBarItem(icon: const Icon(Icons.contact_support_outlined), label: t('contact_us').split(' ')[0]),
                          ],
                        )
                      : null,
                  body: SafeArea(
                    child: tabContent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebarItem(int index, String title, IconData icon, AppThemeColors colors) {
    final isSelected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTab = index;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? colors.primary.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? colors.primary : colors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: isSelected ? colors.primary : colors.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPortfolioContent({
    required Map<String, dynamic>? portfolio,
    required List<Map<String, dynamic>> transactions,
    required double invested,
    required double current,
    required double absReturn,
    required double xirrVal,
    required List<dynamic> activeHoldings,
    required AppThemeColors colors,
    required String Function(String) t,
    required bool showSidebar,
  }) {
    return RefreshIndicator(
      onRefresh: () async {
        _refreshData();
      },
      color: colors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Metric Cards Grid
            showSidebar
                ? Row(
                    children: [
                      Expanded(child: _buildMetricCard(colors, t('total_invested'), currencyFormat.format(invested), Icons.account_balance_wallet_outlined, const Color(0xFF8A2387))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildMetricCard(colors, t('current_valuation'), currencyFormat.format(current), Icons.trending_up, const Color(0xFFE94057))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildMetricCard(colors, t('absolute_return'), "${absReturn.toStringAsFixed(2)}%", Icons.pie_chart_outline, const Color(0xFFF27121), isReturn: true, returnValue: absReturn)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildMetricCard(colors, t('annualized_return'), "${xirrVal.toStringAsFixed(2)}%", Icons.offline_bolt_outlined, const Color(0xFF00C853), isReturn: true, returnValue: xirrVal)),
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildMetricCard(colors, t('total_invested'), currencyFormat.format(invested), Icons.account_balance_wallet_outlined, const Color(0xFF8A2387))),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricCard(colors, t('current_valuation'), currencyFormat.format(current), Icons.trending_up, const Color(0xFFE94057))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildMetricCard(colors, t('absolute_return'), "${absReturn.toStringAsFixed(2)}%", Icons.pie_chart_outline, const Color(0xFFF27121), isReturn: true, returnValue: absReturn)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricCard(colors, t('annualized_return').split(' ')[0], "${xirrVal.toStringAsFixed(2)}%", Icons.offline_bolt_outlined, const Color(0xFF00C853), isReturn: true, returnValue: xirrVal)),
                        ],
                      ),
                    ],
                  ),
            const SizedBox(height: 36),

            // Holdings Header
            Text(
              t('active_portfolio_holdings'),
              style: GoogleFonts.outfit(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            if (activeHoldings.isEmpty)
              _buildEmptyStateCard(
                colors,
                "No Active Holdings",
                "Your account does not have any active fund units logged yet. Check back once your financial advisor processes your CAMS/KFintech mailback statements.",
                Icons.folder_open_outlined,
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: colors.cardShadow,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
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
                        style: GoogleFonts.outfit(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          "${units.toStringAsFixed(4)} Units  •  NAV: ₹${nav.toStringAsFixed(2)}",
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
                          const SizedBox(height: 4),
                          Text(
                            h['code'],
                            style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 11),
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
              t('transaction_history'),
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
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: colors.cardShadow,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
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
        ),
      ),
    );
  }

  Widget _buildFactsheetsContent({
    required List<Map<String, dynamic>> allFunds,
    required AppThemeColors colors,
    required String Function(String) t,
    required bool showSidebar,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('search_explore_factsheets'),
                style: GoogleFonts.outfit(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t('fund_facts_finder_sub'),
                style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),

              // Search Bar block
              RawAutocomplete<Map<String, dynamic>>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.length < 2) {
                    return const Iterable<Map<String, dynamic>>.empty();
                  }
                  return allFunds.where((Map<String, dynamic> fund) {
                    final name = (fund['scheme_name'] ?? '').toString().toLowerCase();
                    final code = (fund['scheme_code'] ?? '').toString().toLowerCase();
                    final query = textEditingValue.text.toLowerCase();
                    return name.contains(query) || code.contains(query);
                  });
                },
                onSelected: (Map<String, dynamic> selection) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _autocompleteTextController?.clear();
                  });
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
                  _autocompleteTextController = textEditingController;
                  return TextField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    style: GoogleFonts.inter(color: colors.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: t('search_funds_placeholder_client'),
                      hintStyle: GoogleFonts.inter(color: colors.textMuted, fontSize: 13),
                      prefixIcon: Icon(Icons.search, color: colors.textSecondary, size: 20),
                      suffixIcon: textEditingController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: colors.textSecondary, size: 18),
                              onPressed: () {
                                textEditingController.clear();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: colors.surfaceAccent,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: colors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Container(
                        width: showSidebar ? 600 : constraints.maxWidth - 48,
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
                                style: GoogleFonts.inter(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                "Code: ${option['scheme_code']} | ${option['category'] ?? 'N/A'}",
                                style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 11),
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
            ],
          ),
        );
      }
    );
  }

  Widget _buildSettingsContent({
    required AppThemeColors colors,
    required String Function(String) t,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('display_settings'),
            style: GoogleFonts.outfit(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            t('display_settings_sub'),
            style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                _buildSettingsThemeTile(
                  title: t('light_mode'),
                  subtitle: t('light_mode_sub'),
                  icon: Icons.light_mode_outlined,
                  option: ThemeModeOption.light,
                  themeProvider: themeProvider,
                  colors: colors,
                ),
                Divider(color: colors.border, height: 1),
                _buildSettingsThemeTile(
                  title: t('dark_mode'),
                  subtitle: t('dark_mode_sub'),
                  icon: Icons.dark_mode_outlined,
                  option: ThemeModeOption.dark,
                  themeProvider: themeProvider,
                  colors: colors,
                ),
                Divider(color: colors.border, height: 1),
                _buildSettingsThemeTile(
                  title: t('system_preference'),
                  subtitle: t('system_preference_sub'),
                  icon: Icons.brightness_auto_outlined,
                  option: ThemeModeOption.system,
                  themeProvider: themeProvider,
                  colors: colors,
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          Text(
            t('language_settings'),
            style: GoogleFonts.outfit(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            t('language_settings_sub'),
            style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                _buildSettingsLanguageRadio(
                  title: "English",
                  subtitle: "Default interface language",
                  langCode: "en",
                  languageProvider: languageProvider,
                  colors: colors,
                ),
                Divider(color: colors.border, height: 1),
                _buildSettingsLanguageRadio(
                  title: "हिन्दी (Hindi)",
                  subtitle: "हिन्दी इंटरफ़ेस भाषा",
                  langCode: "hi",
                  languageProvider: languageProvider,
                  colors: colors,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsThemeTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required ThemeModeOption option,
    required ThemeProvider themeProvider,
    required AppThemeColors colors,
  }) {
    final isSelected = themeProvider.themeModeOption == option;
    return InkWell(
      onTap: () => themeProvider.setThemeMode(option),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? colors.primary : colors.textSecondary, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: colors.primary, size: 20)
            else
              Icon(Icons.circle_outlined, color: colors.border, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsLanguageRadio({
    required String title,
    required String subtitle,
    required String langCode,
    required LanguageProvider languageProvider,
    required AppThemeColors colors,
  }) {
    final isSelected = languageProvider.currentLanguage == langCode;
    return InkWell(
      onTap: () => languageProvider.setLanguage(langCode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.language, color: isSelected ? colors.primary : colors.textSecondary, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: colors.primary, size: 20)
            else
              Icon(Icons.circle_outlined, color: colors.border, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutUsContent({
    required AppThemeColors colors,
    required String Function(String) t,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Container(
        padding: const EdgeInsets.all(28.0),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.cardShadow,
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: colors.primary, size: 26),
                const SizedBox(width: 12),
                Text(
                  t('about_us'),
                  style: GoogleFonts.outfit(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              t('about_us_content'),
              style: GoogleFonts.inter(
                color: colors.textSecondary,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.primary.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_outlined, color: colors.primary, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    "15+ Years Trust & Excellence",
                    style: GoogleFonts.outfit(
                      color: colors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactUsContent({
    required AppThemeColors colors,
    required String Function(String) t,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Container(
        padding: const EdgeInsets.all(28.0),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.cardShadow,
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.contact_support_outlined, color: colors.primary, size: 26),
                const SizedBox(width: 12),
                Text(
                  t('contact_us'),
                  style: GoogleFonts.outfit(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined, color: colors.accent, size: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Office Address",
                        style: GoogleFonts.outfit(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Corporate Office, Kankarbagh,\nPatna - 800020, Bihar",
                        style: GoogleFonts.inter(
                          color: colors.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.phone_android_outlined, color: colors.accent, size: 22),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Phone Number",
                      style: GoogleFonts.outfit(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "+91 9876543210",
                      style: GoogleFonts.inter(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.mail_outline, color: colors.accent, size: 22),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Email Support",
                      style: GoogleFonts.outfit(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "support@sharanfincorp.com",
                      style: GoogleFonts.inter(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(AppThemeColors colors, String label, String value, IconData icon, Color accentColor, {bool isReturn = false, double returnValue = 0.0}) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.cardShadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
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
                  style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    color: isReturn
                        ? (returnValue >= 0 ? const Color(0xFF00C853) : const Color(0xFFFF1744))
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.cardShadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: colors.textMuted, size: 36),
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
