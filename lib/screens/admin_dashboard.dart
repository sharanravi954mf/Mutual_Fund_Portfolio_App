import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import 'client_detail_screen.dart';
import '../services/supabase_service.dart';
import '../utils/file_picker_helper.dart' as fph;
import 'dart:typed_data';
import 'dart:convert';
import 'package:archive/archive.dart' as archive;

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedTab = 0;
  String _searchQuery = "";
  bool _isIngesting = false;
  bool _isSyncingNAV = false;
  bool _isLoading = true;
  
  final TextEditingController _searchController = TextEditingController();
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  List<Map<String, dynamic>> _allClients = [];
  List<Map<String, dynamic>> _filteredClients = [];

  // Factsheet Management variables
  final SupabaseService _supabaseService = SupabaseService();
  List<Map<String, dynamic>> _fundsList = [];
  String? _selectedFundId;
  bool _savingFactsheet = false;
  final TextEditingController _factsheetPdfController = TextEditingController();
  final TextEditingController _factsheetHoldingsUrlController = TextEditingController();
  final TextEditingController _factsheetManagersController = TextEditingController();
  final TextEditingController _factsheetTopHoldingsController = TextEditingController();
  final TextEditingController _factsheetMonthController = TextEditingController(
    text: "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-01",
  );

  // Invoice Signer variables
  fph.PickedFileData? _selectedInvoicePdf;
  fph.PickedFileData? _selectedSignaturePng;
  fph.PickedFileData? _selectedStampPng;
  double _stampX = 400;
  double _stampY = 102;
  double _sigX = 420;
  double _sigY = 72;
  bool _signingInvoice = false;

  @override
  void initState() {
    super.initState();
    _refreshClients();
  }

  Future<void> _refreshClients() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final client = Supabase.instance.client;
      // Fetch profiles with client role, joining portfolios to display market values
      final response = await client
          .from('profiles')
          .select('*, portfolios(total_invested_value, current_market_value)')
          .eq('role', 'client');

      final List<Map<String, dynamic>> loaded = List<Map<String, dynamic>>.from(response ?? []);
      
      setState(() {
        _allClients = loaded;
        _applyFilter(_searchQuery);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error fetching client profiles: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _onSearchChanged(String query) {
    _searchQuery = query;
    _applyFilter(query);
  }

  void _applyFilter(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filteredClients = _allClients;
      } else {
        final q = query.toLowerCase();
        _filteredClients = _allClients.where((client) {
          final name = (client['full_name'] ?? '').toString().toLowerCase();
          final email = (client['email'] ?? '').toString().toLowerCase(); // fallback email
          final pan = (client['pan'] ?? '').toString().toLowerCase();
          final id = (client['id'] ?? '').toString().toLowerCase();

          return name.contains(q) || email.contains(q) || pan.contains(q) || id.contains(q);
        }).toList();
      }
    });
  }

  Future<void> _triggerManualIngestion() async {
    setState(() {
      _isIngesting = true;
    });

    try {
      final client = Supabase.instance.client;
      // Call Supabase Edge Function to force mailbox check & ingestion
      final response = await client.functions.invoke('cams-kfintech-ingestion');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Ingestion success: ${response.status == 200 ? 'Job executed successfully' : 'Processed logs'}",
                  style: GoogleFonts.inter(),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF00C853),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      // Reload updated portfolio values
      await _refreshClients();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text("Ingestion trigger failed: $e", style: GoogleFonts.inter()),
              ),
            ],
          ),
          backgroundColor: Colors.redAccent.shade400,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() {
        _isIngesting = false;
      });
    }
  }

  Future<void> _triggerNAVUpdateSync() async {
    setState(() {
      _isSyncingNAV = true;
    });

    try {
      final client = Supabase.instance.client;
      final response = await client.functions.invoke('daily-nav-updater');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text("NAV sync complete! Response: ${response.data}", style: GoogleFonts.inter()),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF00C853),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Reload updated portfolio values
      await _refreshClients();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text("NAV sync trigger failed: $e", style: GoogleFonts.inter()),
              ),
            ],
          ),
          backgroundColor: Colors.redAccent.shade400,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() {
        _isSyncingNAV = false;
      });
    }
  }

  Future<void> _fetchFundsList() async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('mutual_funds')
          .select('id, scheme_name, scheme_code, category, fund_house')
          .order('scheme_name', ascending: true);
      
      setState(() {
        _fundsList = List<Map<String, dynamic>>.from(response ?? []);
        if (_fundsList.isNotEmpty && _selectedFundId == null) {
          _selectedFundId = _fundsList[0]['id'];
          _loadFactsheetForSelectedFund();
        }
      });
    } catch (e) {
      // Ignored
    }
  }

  Future<void> _loadFactsheetForSelectedFund() async {
    if (_selectedFundId == null) return;
    
    final data = await _supabaseService.getLatestFactsheet(_selectedFundId!);
    setState(() {
      if (data != null) {
        _factsheetPdfController.text = data['factsheet_url'] ?? '';
        _factsheetHoldingsUrlController.text = data['portfolio_holdings_url'] ?? '';
        _factsheetMonthController.text = data['month_year'] ?? '';
        
        final managersList = data['managers'] as List?;
        _factsheetManagersController.text = managersList?.join(', ') ?? '';
        
        final holdingsList = data['top_holdings'] as List?;
        if (holdingsList != null) {
          final lines = holdingsList.map((h) => "${h['company']}: ${h['weight']}");
          _factsheetTopHoldingsController.text = lines.join(', ');
        } else {
          _factsheetTopHoldingsController.text = '';
        }
      } else {
        _factsheetPdfController.text = '';
        _factsheetHoldingsUrlController.text = '';
        _factsheetManagersController.text = '';
        _factsheetTopHoldingsController.text = '';
      }
    });
  }

  Future<void> _saveFactsheet() async {
    if (_selectedFundId == null) return;
    
    setState(() {
      _savingFactsheet = true;
    });
    
    final managers = _factsheetManagersController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
        
    final topHoldings = <Map<String, dynamic>>[];
    final holdingsStr = _factsheetTopHoldingsController.text.trim();
    if (holdingsStr.isNotEmpty) {
      final parts = holdingsStr.split(',');
      for (var part in parts) {
        final pair = part.split(':');
        if (pair.length == 2) {
          final company = pair[0].trim();
          final weight = double.tryParse(pair[1].trim()) ?? 0.0;
          if (company.isNotEmpty && weight > 0) {
            topHoldings.add({
              'company': company,
              'weight': weight,
            });
          }
        }
      }
    }
    
    final payload = {
      'mutual_fund_id': _selectedFundId,
      'month_year': _factsheetMonthController.text.trim(),
      'factsheet_url': _factsheetPdfController.text.trim(),
      'portfolio_holdings_url': _factsheetHoldingsUrlController.text.trim(),
      'managers': managers,
      'top_holdings': topHoldings,
    };
    
    final success = await _supabaseService.upsertFactsheet(payload);
    
    setState(() {
      _savingFactsheet = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? "Factsheet updated successfully!" : "Failed to update factsheet."),
          backgroundColor: success ? Colors.green : Colors.redAccent,
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _factsheetPdfController.dispose();
    _factsheetHoldingsUrlController.dispose();
    _factsheetManagersController.dispose();
    _factsheetTopHoldingsController.dispose();
    _factsheetMonthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0C20),
      body: Row(
        children: [
          // Sidebar - Hidden on mobile viewports for responsiveness
          LayoutBuilder(builder: (context, constraints) {
            final showSidebar = MediaQuery.of(context).size.width > 900;
            if (!showSidebar) return const SizedBox.shrink();

            return Container(
              width: 260,
              decoration: const BoxDecoration(
                color: Color(0xFF151030),
                border: Border(right: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_outlined, color: Color(0xFFE94057), size: 28),
                        const SizedBox(width: 12),
                        Text(
                          "Admin Central",
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 16),
                  _buildSidebarItem(0, "Clients Management", Icons.people_outline),
                  _buildSidebarItem(1, "Data Ingestion", Icons.cloud_upload_outlined),
                  _buildSidebarItem(2, "Factsheets Manager", Icons.document_scanner_outlined),
                  _buildSidebarItem(3, "Invoice Signer", Icons.draw_outlined),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        authProvider.user?.email ?? "Admin User",
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text("System Administrator", style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 11)),
                      trailing: IconButton(
                        icon: const Icon(Icons.logout, color: Colors.grey),
                        onPressed: () => authProvider.signOut(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          // Main Pane
          Expanded(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: const Color(0xFF151030),
                elevation: 0,
                title: Text(
                  _selectedTab == 0
                      ? "Clients Directory"
                      : (_selectedTab == 1 
                          ? "Data Ingestion Engine" 
                          : (_selectedTab == 2 ? "Factsheets Manager" : "Invoice Signer")),
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.grey),
                    onPressed: _refreshClients,
                    tooltip: "Reload Profiles",
                  ),
                  if (MediaQuery.of(context).size.width <= 900)
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.grey),
                      onPressed: () => authProvider.signOut(),
                    ),
                ],
              ),
              bottomNavigationBar: MediaQuery.of(context).size.width <= 900
                  ? BottomNavigationBar(
                      currentIndex: _selectedTab,
                      backgroundColor: const Color(0xFF151030),
                      selectedItemColor: const Color(0xFFE94057),
                      unselectedItemColor: Colors.grey,
                      type: BottomNavigationBarType.fixed,
                      onTap: (index) {
                        setState(() {
                          _selectedTab = index;
                          if (index == 2) {
                            _fetchFundsList();
                          }
                        });
                      },
                      items: const [
                        BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: "Clients"),
                        BottomNavigationBarItem(icon: Icon(Icons.cloud_upload_outlined), label: "Ingest"),
                        BottomNavigationBarItem(icon: Icon(Icons.document_scanner_outlined), label: "Factsheets"),
                        BottomNavigationBarItem(icon: Icon(Icons.draw_outlined), label: "Signer"),
                      ],
                    )
                  : null,
              body: _buildSelectedTabContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTab = index;
            if (index == 2) {
              _fetchFundsList();
            }
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFE94057).withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? const Color(0xFFE94057) : Colors.grey, size: 22),
              const SizedBox(width: 16),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.white : Colors.grey.shade400,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedTabContent() {
    switch (_selectedTab) {
      case 0:
        return _buildClientsListContent();
      case 1:
        return _buildIngestionContent();
      case 2:
        return _buildFactsheetsContent();
      case 3:
        return _buildInvoiceSignerContent();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildClientsListContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE94057)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Client Search Bar
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: GoogleFonts.inter(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Search clients by full name or PAN code...",
              hintStyle: GoogleFonts.inter(color: Colors.grey.shade600),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged("");
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withOpacity(0.02),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.white10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE94057)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Directory count
          Text(
            "Showing ${_filteredClients.length} of ${_allClients.length} registered clients",
            style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Client List Table / ListView
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.015),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: _filteredClients.isEmpty
                  ? Center(
                      child: Text(
                        "No matching client profiles found.",
                        style: GoogleFonts.inter(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filteredClients.length,
                      separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
                      itemBuilder: (context, index) {
                        final client = _filteredClients[index];
                        final name = client['full_name'] ?? 'Unnamed Client';
                        final pan = client['pan'] ?? 'PAN Pending';
                        final id = client['id'].toString().substring(0, 8);

                        // Extract market value from portfolio lists
                        final portfolios = client['portfolios'] as List<dynamic>?;
                        double marketVal = 0.0;
                        if (portfolios != null && portfolios.isNotEmpty) {
                          marketVal = (portfolios.first['current_market_value'] as num).toDouble();
                        }

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => ClientDetailScreen(
                                  clientId: client['id'] as String,
                                  clientName: name,
                                  clientPan: pan,
                                ),
                              ),
                            );
                          },
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFE94057).withOpacity(0.1),
                            child: Text(
                              name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'C',
                              style: GoogleFonts.outfit(color: const Color(0xFFE94057), fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            name,
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              "PAN: ${pan.toUpperCase()}  •  ID: $id",
                              style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 12),
                            ),
                          ),
                          trailing: Text(
                            currencyFormat.format(marketVal),
                            style: GoogleFonts.outfit(
                              color: marketVal > 0 ? const Color(0xFF00C853) : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngestionContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Advisor Automation Tools",
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            "Manage connection states and execute manual file parsers.",
            style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13),
          ),
          const SizedBox(height: 32),

          // Ingestion Action Card
          Container(
            padding: const EdgeInsets.all(28.0),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sync_alt, color: Color(0xFFE94057), size: 24),
                    const SizedBox(width: 12),
                    Text(
                      "Force RTA Statement Sync",
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "Triggering this command immediately establishes secure IMAP tunnels, fetches new CAMS/KFintech mailbacks, runs decryptions, parses transactions, and logs outputs without waiting for midnight.",
                  style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _isIngesting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.cloud_download_outlined, color: Colors.white),
                    label: Text(
                      _isIngesting ? "Syncing Mailbox..." : "Execute Manual Ingestion Now",
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                    onPressed: _isIngesting ? null : _triggerManualIngestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94057),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // NAV Sync Action Card
          Container(
            padding: const EdgeInsets.all(28.0),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.currency_rupee, color: Color(0xFFF27121), size: 24),
                    const SizedBox(width: 12),
                    Text(
                      "Force Daily NAV Price Sync",
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "Queries the mfapi.in API database for all registered mutual funds to fetch today's latest Net Asset Values and updates client portfolio valuations.",
                  style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _isSyncingNAV
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.trending_up, color: Colors.white),
                    label: Text(
                      _isSyncingNAV ? "Syncing NAV Prices..." : "Sync Daily NAV Prices Now",
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                    onPressed: _isSyncingNAV ? null : _triggerNAVUpdateSync,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF27121),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _buildFactsheetsContent() {
    return _fundsList.isEmpty
        ? const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE94057)),
            ),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Factsheet & Holdings Editor",
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Select a mutual fund scheme to configure its monthly factsheet, managers, and top holdings.",
                  style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13),
                ),
                const SizedBox(height: 24),

                // Dropdown Selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedFundId,
                      dropdownColor: const Color(0xFF151030),
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                      isExpanded: true,
                      onChanged: (val) {
                        setState(() {
                          _selectedFundId = val;
                          _loadFactsheetForSelectedFund();
                        });
                      },
                      items: _fundsList.map((fund) {
                        return DropdownMenuItem<String>(
                          value: fund['id'],
                          child: Text(
                            "${fund['scheme_name']} (${fund['scheme_code']})",
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Edit Form Card
                Container(
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Month Year Text field
                      _buildLabel("Report Date (YYYY-MM-DD)"),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _factsheetMonthController,
                        style: GoogleFonts.inter(color: Colors.white),
                        decoration: _buildInputDecoration("e.g. 2026-07-01"),
                      ),
                      const SizedBox(height: 20),

                      // PDF Link Text field
                      _buildLabel("Factsheet PDF Download URL"),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _factsheetPdfController,
                        style: GoogleFonts.inter(color: Colors.white),
                        decoration: _buildInputDecoration("e.g. https://amc.com/factsheet.pdf"),
                      ),
                      const SizedBox(height: 20),

                      // Holdings URL Text field
                      _buildLabel("AMC Portfolio Disclosures Web URL"),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _factsheetHoldingsUrlController,
                        style: GoogleFonts.inter(color: Colors.white),
                        decoration: _buildInputDecoration("e.g. https://amc.com/disclosures"),
                      ),
                      const SizedBox(height: 20),

                      // Fund Managers (Comma separated)
                      _buildLabel("Fund Managers (Comma separated)"),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _factsheetManagersController,
                        style: GoogleFonts.inter(color: Colors.white),
                        decoration: _buildInputDecoration("e.g. John Doe, Jane Smith"),
                      ),
                      const SizedBox(height: 20),

                      // Top Holdings (Text Area format)
                      _buildLabel("Top Holdings (Format: CompanyName: Weight, Company2: Weight)"),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _factsheetTopHoldingsController,
                        maxLines: 3,
                        style: GoogleFonts.inter(color: Colors.white),
                        decoration: _buildInputDecoration("e.g. HDFC Bank: 9.5, Reliance: 8.2, TCS: 5.4"),
                      ),
                      const SizedBox(height: 32),

                      // Save Button
                      ElevatedButton(
                        onPressed: _savingFactsheet ? null : _saveFactsheet,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE94057),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _savingFactsheet
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                "Save Config",
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
  }

  Widget _buildLabel(String labelText) {
    return Text(
      labelText,
      style: GoogleFonts.inter(
        fontSize: 13,
        color: Colors.grey.shade400,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.grey.shade600),
      filled: true,
      fillColor: Colors.black.withOpacity(0.2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
  Widget _buildInvoiceSignerContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Invoice PDF Signer & Stamper",
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Upload a standard CAMS distributor invoice PDF, upload transparent signature and stamp assets, and overlay them on the final page of the PDF with adjustable placement offsets.",
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 800;
              return isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildUploadPanel()),
                        const SizedBox(width: 24),
                        Expanded(child: _buildControlPanel()),
                      ],
                    )
                  : Column(
                      children: [
                        _buildUploadPanel(),
                        const SizedBox(height: 24),
                        _buildControlPanel(),
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUploadPanel() {
    return Column(
      children: [
        _buildUploadCard(
          title: _selectedInvoicePdf != null && _selectedInvoicePdf!.filename.toLowerCase().endsWith(".zip") 
              ? "Distributor Invoice ZIP Archive" 
              : "Distributor Invoice PDF / ZIP",
          subtitle: _selectedInvoicePdf != null ? _selectedInvoicePdf!.filename : "Select PDF Invoice or ZIP Archive",
          icon: _selectedInvoicePdf != null && _selectedInvoicePdf!.filename.toLowerCase().endsWith(".zip") 
              ? Icons.archive_outlined 
              : Icons.picture_as_pdf_outlined,
          isSelected: _selectedInvoicePdf != null,
          onTap: () async {
            final file = await fph.pickFile('.pdf,.zip');
            if (file != null) {
              setState(() {
                _selectedInvoicePdf = file;
              });
            }
          },
        ),
        const SizedBox(height: 16),
        _buildUploadCard(
          title: "Transparent Signature PNG",
          subtitle: _selectedSignaturePng != null ? _selectedSignaturePng!.filename : "Select signature_transparent.png",
          icon: Icons.draw_outlined,
          isSelected: _selectedSignaturePng != null,
          onTap: () async {
            final file = await fph.pickFile('.png');
            if (file != null) {
              setState(() {
                _selectedSignaturePng = file;
              });
            }
          },
        ),
        const SizedBox(height: 16),
        _buildUploadCard(
          title: "Transparent Company Stamp PNG",
          subtitle: _selectedStampPng != null ? _selectedStampPng!.filename : "Select stamp_transparent.png",
          icon: Icons.qr_code_scanner_outlined,
          isSelected: _selectedStampPng != null,
          onTap: () async {
            final file = await fph.pickFile('.png');
            if (file != null) {
              setState(() {
                _selectedStampPng = file;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildUploadCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF151030),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFE94057) : Colors.white10,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE94057).withOpacity(0.1) : Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? const Color(0xFFE94057) : Colors.grey,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isSelected ? Colors.grey.shade300 : Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle : Icons.arrow_forward_ios,
              color: isSelected ? const Color(0xFFE94057) : Colors.grey.shade700,
              size: isSelected ? 22 : 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF151030),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Coordinate Offsets Customizer",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Fine-tune the overlays positioning relative to the bottom-left point boundary of the page space (A4 Point bounds).",
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 24),
          _buildCoordinateSlider(
            label: "Company Stamp X (Horizontal)",
            value: _stampX,
            min: 0,
            max: 600,
            onChanged: (val) {
              setState(() {
                _stampX = val;
              });
            },
          ),
          _buildCoordinateSlider(
            label: "Company Stamp Y (Vertical)",
            value: _stampY,
            min: 0,
            max: 800,
            onChanged: (val) {
              setState(() {
                _stampY = val;
              });
            },
          ),
          const Divider(color: Colors.white10, height: 32),
          _buildCoordinateSlider(
            label: "Distributor Signature X (Horizontal)",
            value: _sigX,
            min: 0,
            max: 600,
            onChanged: (val) {
              setState(() {
                _sigX = val;
              });
            },
          ),
          _buildCoordinateSlider(
            label: "Distributor Signature Y (Vertical)",
            value: _sigY,
            min: 0,
            max: 800,
            onChanged: (val) {
              setState(() {
                _sigY = val;
              });
            },
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _selectedInvoicePdf == null ||
                      _selectedSignaturePng == null ||
                      _selectedStampPng == null ||
                      _signingInvoice
                  ? null
                  : _signInvoiceProcess,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94057),
                disabledBackgroundColor: Colors.white10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _signingInvoice
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      "Sign & Stamp Invoice",
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinateSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey.shade400,
              ),
            ),
            Text(
              value.round().toString(),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFE94057),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          activeColor: const Color(0xFFE94057),
          inactiveColor: Colors.black26,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Future<void> _signInvoiceProcess() async {
    setState(() {
      _signingInvoice = true;
    });

    try {
      final originalName = _selectedInvoicePdf!.filename;
      final isZip = originalName.toLowerCase().endsWith(".zip");

      if (isZip) {
        final zipBytes = base64Decode(_selectedInvoicePdf!.base64String!);
        final decoder = archive.ZipDecoder();
        final archiveFiles = decoder.decodeBytes(zipBytes);
        
        final outArchive = archive.Archive();
        final encoder = archive.ZipEncoder();
        
        int signedCount = 0;
        int skippedCount = 0;

        for (final file in archiveFiles.files) {
          final lowerName = file.name.toLowerCase();
          final filenameOnly = file.name.split('/').last;

          if (file.isFile &&
              lowerName.endsWith('.pdf') &&
              !lowerName.contains('__macosx') &&
              !filenameOnly.startsWith('._')) {
            
            final rawBytes = file.content as List<int>;
            final base64Pdf = base64Encode(rawBytes);

            final payload = {
              "invoiceFile": base64Pdf,
              "signaturePng": _selectedSignaturePng!.base64String,
              "stampPng": _selectedStampPng!.base64String,
              "stampX": _stampX.round(),
              "stampY": _stampY.round(),
              "sigX": _sigX.round(),
              "sigY": _sigY.round(),
            };

            final response = await _supabaseService.client.functions.invoke(
              'sign-stamp-invoice',
              body: payload,
            );

            if (response.status == 200 && response.data != null) {
              final signedBytes = response.data as List<int>;
              outArchive.addFile(archive.ArchiveFile(
                file.name,
                signedBytes.length,
                signedBytes,
              ));
              signedCount++;
            } else {
              outArchive.addFile(file);
              skippedCount++;
            }
          } else {
            outArchive.addFile(file);
          }
        }

        final outputBytes = encoder.encode(outArchive);
        if (outputBytes == null) {
          throw Exception("Failed to encode output ZIP archive.");
        }

        final uint8Bytes = Uint8List.fromList(outputBytes);
        final outputName = originalName.toLowerCase().endsWith(".zip")
            ? "${originalName.substring(0, originalName.length - 4)}_SIGNED.zip"
            : "${originalName}_SIGNED.zip";

        await fph.saveFileBytes(uint8Bytes, outputName);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Batch signing complete! Signed $signedCount PDFs. Download started."),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final payload = {
          "invoiceFile": _selectedInvoicePdf!.base64String,
          "signaturePng": _selectedSignaturePng!.base64String,
          "stampPng": _selectedStampPng!.base64String,
          "stampX": _stampX.round(),
          "stampY": _stampY.round(),
          "sigX": _sigX.round(),
          "sigY": _sigY.round(),
        };

        final response = await _supabaseService.client.functions.invoke(
          'sign-stamp-invoice',
          body: payload,
        );

        if (response.status == 200 && response.data != null) {
          final bytes = response.data as List<int>;
          final uint8Bytes = Uint8List.fromList(bytes);

          final outputName = originalName.toLowerCase().endsWith(".pdf")
              ? "${originalName.substring(0, originalName.length - 4)}_SIGNED.pdf"
              : "${originalName}_SIGNED.pdf";

          await fph.saveFileBytes(uint8Bytes, outputName);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Invoice signed successfully! Download started."),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          throw Exception(response.data?["error"] ?? "Failed to sign invoice. Server returned status code ${response.status}");
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _signingInvoice = false;
        });
      }
    }
  }
}
