import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_animate/flutter_animate.dart';
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
  int _selectedTab = 0; // 0: Portfolio, 1: Factsheets, 2: Settings, 3: About Us, 4: Contact Us
  bool _isSidebarExpanded = true;

  // Real-time factsheet search state variables
  final TextEditingController _fundSearchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _searchingFunds = false;
  bool _fetchingFundDetails = false;
  Map<String, dynamic>? _selectedFundDetails;
  String? _fundSearchError;
  String _selectedChartRange = "1Y"; // default 1 Year
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  @override
  void dispose() {
    _fundSearchController.dispose();
    _debounce?.cancel();
    super.dispose();
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

  void _onSearchQueryChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performFundSearch(query.trim());
    });
  }

  Future<void> _performFundSearch(String query) async {
    final cleanQuery = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanQuery.isEmpty) return;

    final keywords = cleanQuery.toLowerCase().split(' ').where((k) => k.isNotEmpty).toList();

    // Check if it's a numeric scheme code
    final isNumeric = RegExp(r'^\d+$').hasMatch(cleanQuery);
    
    if (cleanQuery.length < 3 && !isNumeric) {
      setState(() {
        _searchResults = [];
        _fundSearchError = null;
      });
      return;
    }

    setState(() {
      _searchingFunds = true;
      _fundSearchError = null;
    });

    try {
      List<dynamic> results = [];
      
      // If it is numeric, construct a virtual search result directly
      if (isNumeric && cleanQuery.length >= 5 && cleanQuery.length <= 6) {
        results = [
          {
            "schemeCode": int.parse(cleanQuery),
            "schemeName": "Fetch Scheme Code: $cleanQuery",
          }
        ];
      } else {
        // Query search API with the ENTIRE cleanQuery
        final response = await Supabase.instance.client.functions.invoke(
          'sign-stamp-invoice',
          body: {
            "action": "proxy-get",
            "url": "https://api.mfapi.in/mf/search?q=${Uri.encodeComponent(cleanQuery)}",
          },
        ).timeout(const Duration(seconds: 15));

        if (response.status == 200 && response.data != null) {
          results = response.data is String
              ? jsonDecode(response.data as String)
              : List<dynamic>.from(response.data as List);
        } else {
          throw Exception("Failed to search funds through proxy.");
        }
      }

      // Perform client-side case-insensitive multi-keyword filtering on name and code
      final filtered = results.where((item) {
        final name = (item['schemeName'] as String? ?? '').toLowerCase();
        final code = (item['schemeCode'] ?? '').toString().toLowerCase();
        return keywords.every((kw) => name.contains(kw) || code.contains(kw));
      }).toList();

      setState(() {
        _searchResults = filtered;
        _searchingFunds = false;
        if (filtered.isEmpty) {
          _fundSearchError = "No funds found matching '$cleanQuery'.";
        }
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
        _searchingFunds = false;
        _fundSearchError = "Failed to search funds: Network error.";
      });
    }
  }


  String _getRangeLabel(String range) {
    switch (range) {
      case "YTD":
        return "Year to Date";
      case "1Y":
        return "Last 1 Year";
      case "2Y":
        return "2 Years";
      case "3Y":
        return "3 Years";
      case "5Y":
        return "5 Years";
      case "Since Launch":
      default:
        return "Since Launch";
    }
  }

  DateTime? parseDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  List<dynamic> filterNavDataByRange(List<dynamic> allData, String rangeOption) {
    if (allData.isEmpty) return [];
    
    final latestDateObj = parseDate(allData.first['date'] ?? '');
    if (latestDateObj == null) return allData;
    
    DateTime cutoff;
    switch (rangeOption) {
      case "YTD":
        cutoff = DateTime(latestDateObj.year, 1, 1);
        break;
      case "1Y":
        cutoff = latestDateObj.subtract(const Duration(days: 365));
        break;
      case "2Y":
        cutoff = latestDateObj.subtract(const Duration(days: 2 * 365));
        break;
      case "3Y":
        cutoff = latestDateObj.subtract(const Duration(days: 3 * 365));
        break;
      case "5Y":
        cutoff = latestDateObj.subtract(const Duration(days: 5 * 365));
        break;
      case "Since Launch":
      default:
        return allData;
    }
    
    return allData.where((item) {
      final d = parseDate(item['date'] ?? '');
      return d != null && (d.isAfter(cutoff) || d.isAtSameMomentAs(cutoff));
    }).toList();
  }

  Future<void> _fetchFundDetails(String schemeCode) async {
    setState(() {
      _fetchingFundDetails = true;
      _fundSearchError = null;
      _searchResults = []; // Close the dropdown
      _fundSearchController.clear(); // Clear search field
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'sign-stamp-invoice',
        body: {
          "action": "proxy-get",
          "url": "https://api.mfapi.in/mf/$schemeCode",
        },
      ).timeout(const Duration(seconds: 20));

      if (response.status == 200 && response.data != null) {
        final Map<String, dynamic> details = response.data is String
            ? jsonDecode(response.data as String)
            : Map<String, dynamic>.from(response.data as Map);
        setState(() {
          _selectedFundDetails = details;
          _fetchingFundDetails = false;
        });
      } else {
        throw Exception("Failed to fetch fund details through proxy.");
      }
    } catch (e) {
      setState(() {
        _fetchingFundDetails = false;
        _fundSearchError = "Failed to fetch fund details: Network error.";
      });
    }
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

        final mainScaffold = Scaffold(
          backgroundColor: showSidebar ? Colors.transparent : colors.background,
          drawer: showSidebar
              ? null
              : Drawer(
                  backgroundColor: colors.sidebarBackground,
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Close row
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: colors.sidebarActive,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.shield_outlined, color: Colors.white, size: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    "Sharan Fincorp",
                                    style: GoogleFonts.outfit(
                                      color: colors.sidebarTextPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                color: colors.sidebarTextSecondary,
                                tooltip: "Close Menu",
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ),
                        Divider(color: colors.sidebarBorder, height: 1),

                        // 1. User Profile Header
                        Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colors.sidebarSurface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colors.sidebarBorder),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: colors.sidebarActive,
                                  child: Text(
                                    clientName.isNotEmpty ? clientName[0].toUpperCase() : 'U',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        clientName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.outfit(
                                          color: colors.sidebarTextPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        user?.email ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          color: colors.sidebarTextSecondary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ).animate()
                          .fadeIn(duration: 800.ms, curve: Curves.easeOutCubic)
                          .blur(begin: const Offset(8, 8), end: Offset.zero, duration: 800.ms, curve: Curves.easeOutCubic)
                          .slide(begin: const Offset(-0.15, 0), end: Offset.zero, duration: 800.ms, curve: Curves.easeOutCubic),

                        Divider(color: colors.sidebarBorder, height: 1),
                        const SizedBox(height: 16),

                        // 2. Navigation items
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              _buildDrawerItem(0, t('portfolio'), Icons.account_balance_wallet_outlined, colors, context),
                              _buildDrawerItem(1, "Factsheets", Icons.document_scanner_outlined, colors, context),
                              _buildDrawerItem(2, t('settings'), Icons.settings_outlined, colors, context),
                              _buildDrawerItem(3, t('about_us_nav'), Icons.info_outline, colors, context),
                              _buildDrawerItem(4, t('contact_us'), Icons.contact_support_outlined, colors, context),
                            ],
                          ),
                        ),

                        Divider(color: colors.border, height: 1),

                        // 3. Logout List Tile at the bottom
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(context); // Close the drawer
                              authProvider.signOut();
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: colors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.logout, color: colors.primary, size: 20),
                                  const SizedBox(width: 16),
                                  Text(
                                    t('logout'),
                                    style: GoogleFonts.inter(
                                      color: colors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ).animate(delay: const Duration(milliseconds: 6 * 80))
                          .fadeIn(duration: 800.ms, curve: Curves.easeOutCubic)
                          .blur(begin: const Offset(8, 8), end: Offset.zero, duration: 800.ms, curve: Curves.easeOutCubic)
                          .slide(begin: const Offset(-0.15, 0), end: Offset.zero, duration: 800.ms, curve: Curves.easeOutCubic),
                      ],
                    ),
                  ),
                ),
          appBar: AppBar(
            backgroundColor: colors.surface,
            elevation: 0,
            iconTheme: IconThemeData(color: colors.textPrimary),
            leading: showSidebar
                ? null
                : Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
            title: Row(
              children: [
                if (showSidebar) ...[
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "Sharan Fincorp",
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: colors.textPrimary,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0),
                    child: Text(
                      "/",
                      style: GoogleFonts.inter(color: colors.border, fontSize: 20),
                    ),
                  ),
                ],
                Text(
                  appBarTitle,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.refresh, color: colors.textSecondary),
                tooltip: t('refresh_data'),
                onPressed: _refreshData,
              ),
              const SizedBox(width: 8),
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
          body: SafeArea(
            child: tabContent,
          ).animate().fadeIn(duration: 1000.ms, curve: Curves.easeInOutCubic),
        );

        if (!showSidebar) {
          return mainScaffold;
        }

        return Scaffold(
          backgroundColor: colors.background,
          body: Row(
            children: [
              _buildDesktopSidebar(colors, t, clientName, user, authProvider),
              Expanded(
                child: mainScaffold,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDrawerItem(int index, String title, IconData icon, AppThemeColors colors, BuildContext context) {
    final isSelected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.pop(context); // Close the drawer natively
          setState(() {
            _selectedTab = index;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? colors.sidebarActive : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? colors.sidebarTextPrimary : colors.sidebarTextSecondary,
                size: 20,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: isSelected ? colors.sidebarTextPrimary : colors.sidebarTextSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate(delay: Duration(milliseconds: (index + 1) * 80))
      .fadeIn(duration: 800.ms, curve: Curves.easeOutCubic)
      .blur(begin: const Offset(8, 8), end: Offset.zero, duration: 800.ms, curve: Curves.easeOutCubic)
      .slide(begin: const Offset(-0.15, 0), end: Offset.zero, duration: 800.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildDesktopSidebar(AppThemeColors colors, String Function(String) t, String clientName, User? user, AuthProvider authProvider) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: _isSidebarExpanded ? 260 : 72,
      decoration: BoxDecoration(
        color: colors.sidebarBackground,
        border: Border(right: BorderSide(color: colors.sidebarBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Row (App Logo + Brand Name)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colors.sidebarActive,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.shield_outlined, color: colors.sidebarTextPrimary, size: 20),
                ),
                if (_isSidebarExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Sharan Fincorp",
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: colors.sidebarTextPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(color: colors.sidebarBorder, height: 1),
          const SizedBox(height: 16),

          // 2. Profile Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: _isSidebarExpanded
                ? Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.sidebarSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.sidebarBorder),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: colors.sidebarActive,
                          child: Text(
                            clientName.isNotEmpty ? clientName[0].toUpperCase() : 'U',
                            style: GoogleFonts.outfit(
                              color: colors.sidebarTextPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                clientName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: colors.sidebarTextPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                user?.email ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: colors.sidebarTextSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Tooltip(
                      message: clientName,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: colors.sidebarActive,
                        child: Text(
                          clientName.isNotEmpty ? clientName[0].toUpperCase() : 'U',
                          style: GoogleFonts.outfit(
                            color: colors.sidebarTextPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Divider(color: colors.sidebarBorder, height: 1),
          const SizedBox(height: 16),

          // 3. Navigation Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildSidebarItem(0, t('portfolio'), Icons.account_balance_wallet_outlined, colors),
                _buildSidebarItem(1, "Factsheets", Icons.document_scanner_outlined, colors),
                _buildSidebarItem(2, t('settings'), Icons.settings_outlined, colors),
                _buildSidebarItem(3, t('about_us_nav'), Icons.info_outline, colors),
                _buildSidebarItem(4, t('contact_us'), Icons.contact_support_outlined, colors),
              ],
            ),
          ),

          Divider(color: colors.sidebarBorder, height: 1),

          // 4. Bottom Footer: Collapse Toggle (arrow_back) & Logout Tile
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                // Collapse Toggle
                Tooltip(
                  message: _isSidebarExpanded ? 'Shrink Menu' : 'Expand Menu',
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _isSidebarExpanded = !_isSidebarExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: colors.sidebarSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.sidebarBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: _isSidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isSidebarExpanded ? Icons.arrow_back : Icons.menu,
                            color: colors.sidebarTextSecondary,
                            size: 20,
                          ),
                          if (_isSidebarExpanded) ...[
                            const SizedBox(width: 12),
                            Text(
                              "Collapse Menu",
                              style: GoogleFonts.inter(
                                color: colors.sidebarTextSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Logout Tile
                Tooltip(
                  message: _isSidebarExpanded ? '' : t('logout'),
                  child: InkWell(
                    onTap: () => authProvider.signOut(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: colors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: _isSidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout, color: colors.error, size: 20),
                          if (_isSidebarExpanded) ...[
                            const SizedBox(width: 12),
                            Text(
                              t('logout'),
                              style: GoogleFonts.inter(
                                color: colors.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(int index, String title, IconData icon, AppThemeColors colors) {
    final isSelected = _selectedTab == index;

    if (!_isSidebarExpanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Tooltip(
          message: title,
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedTab = index;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? colors.sidebarActive : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: isSelected ? colors.sidebarTextPrimary : colors.sidebarTextSecondary,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTab = index;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? colors.sidebarActive : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? colors.sidebarTextPrimary : colors.sidebarTextSecondary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: isSelected ? colors.sidebarTextPrimary : colors.sidebarTextSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 15,
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
                      Expanded(child: _buildMetricCard(colors, t('total_invested'), currencyFormat.format(invested), Icons.account_balance_wallet_outlined, const Color(0xFF8A2387)).premiumReveal(index: 0)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildMetricCard(colors, t('current_valuation'), currencyFormat.format(current), Icons.trending_up, const Color(0xFFE94057)).premiumReveal(index: 1)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildMetricCard(colors, t('absolute_return'), "${absReturn.toStringAsFixed(2)}%", Icons.pie_chart_outline, const Color(0xFFF27121), isReturn: true, returnValue: absReturn).premiumReveal(index: 2)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildMetricCard(colors, t('annualized_return'), "${xirrVal.toStringAsFixed(2)}%", Icons.offline_bolt_outlined, const Color(0xFF00C853), isReturn: true, returnValue: xirrVal).premiumReveal(index: 3)),
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildMetricCard(colors, t('total_invested'), currencyFormat.format(invested), Icons.account_balance_wallet_outlined, const Color(0xFF8A2387)).premiumReveal(index: 0)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricCard(colors, t('current_valuation'), currencyFormat.format(current), Icons.trending_up, const Color(0xFFE94057)).premiumReveal(index: 1)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildMetricCard(colors, t('absolute_return'), "${absReturn.toStringAsFixed(2)}%", Icons.pie_chart_outline, const Color(0xFFF27121), isReturn: true, returnValue: absReturn).premiumReveal(index: 2)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricCard(colors, t('annualized_return').split(' ')[0], "${xirrVal.toStringAsFixed(2)}%", Icons.offline_bolt_outlined, const Color(0xFF00C853), isReturn: true, returnValue: xirrVal).premiumReveal(index: 3)),
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
            ).premiumReveal(index: 4),
            const SizedBox(height: 16),

            (activeHoldings.isEmpty
                ? _buildEmptyStateCard(
                    colors,
                    "No Active Holdings",
                    "Your account does not have any active fund units logged yet. Check back once your financial advisor processes your CAMS/KFintech mailback statements.",
                    Icons.folder_open_outlined,
                  )
                : Container(
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
                  )).premiumReveal(index: 5),

            const SizedBox(height: 36),

            // Transactions List
            Text(
              t('transaction_history'),
              style: GoogleFonts.outfit(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ).premiumReveal(index: 6),
            const SizedBox(height: 16),

            (transactions.isEmpty
                ? _buildEmptyStateCard(
                    colors,
                    "No Transactions",
                    "We haven't found any historical transaction logs under this portfolio yet.",
                    Icons.history,
                  )
                : Container(
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
                  )).premiumReveal(index: 7),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('fund_facts_finder'),
            style: GoogleFonts.outfit(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ).premiumReveal(index: 0),
          const SizedBox(height: 8),
          Text(
            t('fund_facts_finder_sub'),
            style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 13),
          ).premiumReveal(index: 1),
          const SizedBox(height: 24),

          // Search Bar Container
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                ),
                child: TextFormField(
                  controller: _fundSearchController,
                  style: GoogleFonts.inter(color: colors.textPrimary, fontSize: 14),
                  onChanged: _onSearchQueryChanged,
                  decoration: InputDecoration(
                    hintText: t('search_funds_placeholder'),
                    hintStyle: GoogleFonts.inter(color: colors.textMuted, fontSize: 13),
                    prefixIcon: Icon(Icons.search, color: colors.textSecondary),
                    suffixIcon: _searchingFunds
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE94057)),
                            ),
                          )
                        : (_fundSearchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, color: colors.textSecondary),
                                onPressed: () {
                                  _fundSearchController.clear();
                                  setState(() {
                                    _searchResults = [];
                                  });
                                },
                              )
                            : null),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                ),
              ),

              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                    boxShadow: [
                      BoxShadow(
                        color: colors.cardShadow,
                        blurRadius: 12,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final item = _searchResults[index];
                      final schemeName = item['schemeName'] as String? ?? '';
                      final schemeCode = (item['schemeCode'] ?? '').toString();

                      return ListTile(
                        title: Text(
                          schemeName,
                          style: GoogleFonts.inter(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          "Scheme Code: $schemeCode",
                          style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 11),
                        ),
                        hoverColor: colors.surfaceAccent,
                        onTap: () => _fetchFundDetails(schemeCode),
                      );
                    },
                    separatorBuilder: (context, index) => Divider(color: colors.border, height: 1),
                  ),
                ),
              ],
            ],
          ).premiumReveal(index: 2),

          if (_fundSearchError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _fundSearchError!,
                      style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Detail Display Card
          (_fetchingFundDetails
              ? const Padding(
                  padding: EdgeInsets.only(top: 40.0),
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE94057)),
                    ),
                  ),
                )
              : (_selectedFundDetails != null
                  ? _buildSelectedFundCard(colors, t)
                  : Container(
                      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colors.border),
                        boxShadow: [
                          BoxShadow(
                            color: colors.cardShadow,
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.search_outlined, color: colors.textMuted, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              t('no_fund_selected'),
                              style: GoogleFonts.outfit(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t('no_fund_selected_sub'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ))).premiumReveal(index: 3),
        ],
      ),
    );
  }

  Widget _buildSelectedFundCard(AppThemeColors colors, String Function(String) t) {
    final meta = _selectedFundDetails!['meta'] as Map<String, dynamic>? ?? {};
    final data = _selectedFundDetails!['data'] as List<dynamic>? ?? [];

    final fundHouse = meta['fund_house'] ?? 'N/A';
    final schemeName = meta['scheme_name'] ?? 'N/A';
    final schemeCode = (meta['scheme_code'] ?? 'N/A').toString();
    final schemeType = meta['scheme_type'] ?? 'N/A';
    final schemeCategory = meta['scheme_category'] ?? 'N/A';
    final isin = meta['isin_div_payout'] ?? meta['isin_div_reinvestment'] ?? 'N/A';

    String latestDate = 'N/A';
    String latestNav = 'N/A';
    if (data.isNotEmpty) {
      latestDate = data[0]['date'] ?? 'N/A';
      latestNav = data[0]['nav'] ?? 'N/A';
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.cardShadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fundHouse.toUpperCase(),
                      style: GoogleFonts.inter(
                        color: colors.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      schemeName,
                      style: GoogleFonts.outfit(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Scheme Code: $schemeCode",
                      style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // NAV Tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE94057).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE94057).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "LATEST NAV",
                      style: GoogleFonts.inter(
                        color: const Color(0xFFE94057),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "₹$latestNav",
                      style: GoogleFonts.outfit(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      latestDate,
                      style: GoogleFonts.inter(
                        color: colors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ).premiumReveal(index: 0),
          Divider(color: colors.border, height: 40),
          
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('scheme_specifications'),
                style: GoogleFonts.outfit(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 600;
                  return GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: isWide ? 3 : 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: isWide ? 2.5 : 2.0,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildSpecTile(colors, "Scheme Type", schemeType),
                      _buildSpecTile(colors, "Category", schemeCategory),
                      _buildSpecTile(colors, "ISIN", isin),
                    ],
                  );
                },
              ),
            ],
          ).premiumReveal(index: 1),
          
          Divider(color: colors.border, height: 40),

          // Custom Timeline Chart
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              final filteredData = filterNavDataByRange(data, _selectedChartRange);
              
              double growthPercent = 0.0;
              if (filteredData.isNotEmpty) {
                final double latest = double.tryParse(filteredData.first['nav'].toString()) ?? 0.0;
                final double oldest = double.tryParse(filteredData.last['nav'].toString()) ?? 0.0;
                growthPercent = oldest == 0.0 ? 0.0 : ((latest - oldest) / oldest) * 100;
              }
              
              final chartCol = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${t('nav_growth_trend')} (${_getRangeLabel(_selectedChartRange)})",
                        style: GoogleFonts.outfit(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      // Growth Percent Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: growthPercent >= 0 
                              ? Colors.green.withOpacity(0.15) 
                              : Colors.redAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: growthPercent >= 0 
                                ? Colors.green.withOpacity(0.3) 
                                : Colors.redAccent.withOpacity(0.3)
                          ),
                        ),
                        child: Text(
                          "${growthPercent >= 0 ? '+' : ''}${growthPercent.toStringAsFixed(2)}%",
                          style: GoogleFonts.inter(
                            color: growthPercent >= 0 ? Colors.green : Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  NavGrowthChart(navData: filteredData),
                ],
              );
              
              final selectorCol = Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceAccent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t('time_range'),
                      style: GoogleFonts.outfit(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...["YTD", "1Y", "2Y", "3Y", "5Y", "Since Launch"].map((range) {
                      final isSelected = _selectedChartRange == range;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedChartRange = range;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? colors.primary : colors.textSecondary,
                                    width: isSelected ? 5 : 2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _getRangeLabel(range),
                                style: GoogleFonts.inter(
                                  color: isSelected ? colors.textPrimary : colors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              );
              
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: chartCol),
                    const SizedBox(width: 24),
                    SizedBox(width: 180, child: selectorCol),
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    chartCol,
                    const SizedBox(height: 20),
                    selectorCol,
                  ],
                );
              }
            },
          ).premiumReveal(index: 2),
          
          Divider(color: colors.border, height: 40),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('recent_historical_navs'),
                style: GoogleFonts.outfit(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              if (data.isEmpty)
                Text(
                  "No historical NAV details available.",
                  style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 13),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: data.length > 10 ? 10 : data.length,
                    separatorBuilder: (context, index) => Divider(color: colors.border, height: 1),
                    itemBuilder: (context, index) {
                      final row = data[index];
                      final date = row['date'] ?? 'N/A';
                      final nav = row['nav'] ?? 'N/A';
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        title: Text(
                          date,
                          style: GoogleFonts.inter(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        trailing: Text(
                          "₹$nav",
                          style: GoogleFonts.outfit(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ).premiumReveal(index: 3),
        ],
      ),
    );
  }

  Widget _buildSpecTile(AppThemeColors colors, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAccent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
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
          Column(
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
            ],
          ).premiumReveal(index: 0),
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
          ).premiumReveal(index: 1),
          const SizedBox(height: 36),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('language_settings'),
                style: GoogleFonts.outfit(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                t('language_settings_sub'),
                style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 12),
              ),
            ],
          ).premiumReveal(index: 2),
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
          ).premiumReveal(index: 3),
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
      ).premiumReveal(index: 0),
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
      ).premiumReveal(index: 0),
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

class NavGrowthChart extends StatelessWidget {
  final List<dynamic> navData;

  const NavGrowthChart({super.key, required this.navData});

  @override
  Widget build(BuildContext context) {
    if (navData.isEmpty) return const SizedBox.shrink();

    // Reverse list to go in chronological order (left to right)
    final pointsList = navData.reversed.toList();

    List<double> navs = pointsList.map((item) {
      return double.tryParse((item['nav'] ?? '0').toString()) ?? 0.0;
    }).toList();

    if (navs.isEmpty) return const SizedBox.shrink();

    // Downsample if there are more than 100 points for smooth canvas rendering
    if (navs.length > 100) {
      navs = _downsample(navs, 100);
    }

    final double maxVal = navs.reduce((a, b) => a > b ? a : b);
    final double minVal = navs.reduce((a, b) => a < b ? a : b);
    final double range = maxVal - minVal == 0 ? 1.0 : maxVal - minVal;

    final firstDate = pointsList.first['date'] ?? '';
    final lastDate = pointsList.last['date'] ?? '';

    final isDark = Provider.of<ThemeProvider>(context).isDarkMode(context);
    final colors = AppThemeColors(isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 180,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceAccent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: CustomPaint(
            painter: LineChartPainter(
              values: navs,
              minVal: minVal,
              maxVal: maxVal,
              range: range,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              firstDate,
              style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 10),
            ),
            Text(
              "Range: ₹${minVal.toStringAsFixed(2)} - ₹${maxVal.toStringAsFixed(2)}",
              style: GoogleFonts.inter(
                color: const Color(0xFFF27121),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              lastDate,
              style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  List<double> _downsample(List<double> input, int maxPoints) {
    if (input.length <= maxPoints) return input;
    final List<double> result = [];
    final double step = (input.length - 1) / (maxPoints - 1);
    for (int i = 0; i < maxPoints; i++) {
      final int index = (i * step).round().clamp(0, input.length - 1);
      result.add(input[index]);
    }
    return result;
  }
}

class LineChartPainter extends CustomPainter {
  final List<double> values;
  final double minVal;
  final double maxVal;
  final double range;

  LineChartPainter({
    required this.values,
    required this.minVal,
    required this.maxVal,
    required this.range,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final double width = size.width;
    final double height = size.height;
    final double stepX = width / (values.length - 1);

    // Draw horizontal grid lines
    final Paint gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.05)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (int i = 1; i <= 3; i++) {
      final double y = height * (i / 4.0);
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    // Prepare points
    final List<Offset> points = [];
    for (int i = 0; i < values.length; i++) {
      final double x = i * stepX;
      final double normalized = (values[i] - minVal) / range;
      final double y = height - (normalized * (height - 30) + 15);
      points.add(Offset(x, y));
    }

    // Draw area path (gradient fill below line)
    final Path areaPath = Path()
      ..moveTo(0, height);
    for (final pt in points) {
      areaPath.lineTo(pt.dx, pt.dy);
    }
    areaPath.lineTo(width, height);
    areaPath.close();

    final Paint areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFE94057).withOpacity(0.2),
          const Color(0xFF8A2387).withOpacity(0.01),
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height));
    canvas.drawPath(areaPath, areaPaint);

    // Draw path line (smooth connecting curves)
    final Path linePath = Path()
      ..moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final controlPoint1 = Offset(p1.dx + stepX / 2.0, p1.dy);
      final controlPoint2 = Offset(p2.dx - stepX / 2.0, p2.dy);
      linePath.cubicTo(
        controlPoint1.dx, controlPoint1.dy,
        controlPoint2.dx, controlPoint2.dy,
        p2.dx, p2.dy,
      );
    }

    final Paint linePaint = Paint()
      ..color = const Color(0xFFE94057)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // Draw circles at endpoints or critical points
    final Paint dotPaint = Paint()
      ..color = const Color(0xFFF27121)
      ..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final lastPt = points.last;
    canvas.drawCircle(lastPt, 5.0, dotPaint);
    canvas.drawCircle(lastPt, 5.0, borderPaint);
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

extension PremiumRevealExtension on Widget {
  Widget premiumReveal({required int index, int staggerMs = 150}) {
    return this.animate(delay: Duration(milliseconds: index * staggerMs))
        .fadeIn(duration: 1000.ms, curve: Curves.easeInOutCubic)
        .blur(begin: const Offset(10, 10), end: Offset.zero, duration: 1000.ms, curve: Curves.easeInOutCubic)
        .slide(begin: const Offset(0, 0.2), end: Offset.zero, duration: 1000.ms, curve: Curves.easeInOutCubic);
  }
}
