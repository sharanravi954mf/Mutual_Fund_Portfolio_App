// ignore_for_file: uri_does_not_exist
// ignore_for_file: avoid_web_libraries_in_flutter
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import 'client_detail_screen.dart';
import '../services/supabase_service.dart';
import '../utils/file_picker_helper.dart' as fph;
import '../utils/excel_updater.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'dart:js' as js;
import 'package:archive/archive.dart' as archive;
import 'package:http/http.dart' as http;

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

  // Fund Search and Details variables
  final TextEditingController _fundSearchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _searchingFunds = false;
  bool _fetchingFundDetails = false;
  Map<String, dynamic>? _selectedFundDetails;
  String? _fundSearchError;
  Timer? _debounceTimer;

  // Invoice Signer variables
  fph.PickedFileData? _selectedInvoicePdf;
  fph.PickedFileData? _selectedSignaturePng;
  fph.PickedFileData? _selectedStampPng;
  double _stampX = 400;
  double _stampY = 102;
  double _sigX = 420;
  double _sigY = 72;
  double _stampW = 120;
  double _stampH = 60;
  double _sigW = 120;
  double _sigH = 50;
  bool _signingInvoice = false;
  String _selectedPreset = "CAMS Distributor (Default)";
  Uint8List? _pdfPreviewBytes;
  bool _loadingPreview = false;

  Future<void> _generatePdfPreview() async {
    if (_selectedInvoicePdf == null) {
      setState(() {
        _pdfPreviewBytes = null;
      });
      return;
    }

    setState(() {
      _loadingPreview = true;
      _pdfPreviewBytes = null;
    });

    try {
      Uint8List? rawBytes;
      if (_selectedInvoicePdf!.bytes != null) {
        rawBytes = _selectedInvoicePdf!.bytes;
      } else if (_selectedInvoicePdf!.base64String != null) {
        rawBytes = base64Decode(_selectedInvoicePdf!.base64String!);
      }

      if (rawBytes != null) {
        Uint8List? pdfBytes;
        final filename = _selectedInvoicePdf!.filename.toLowerCase();
        if (filename.endsWith('.pdf')) {
          pdfBytes = rawBytes;
        } else if (filename.endsWith('.zip')) {
          final dec = archive.ZipDecoder();
          final archiveFile = dec.decodeBytes(rawBytes);
          for (final entry in archiveFile.files) {
            if (entry.isFile && entry.name.toLowerCase().endsWith('.pdf')) {
              if (entry.name.contains('__MACOSX') || entry.name.split('/').last.startsWith('._')) {
                continue;
              }
              pdfBytes = Uint8List.fromList(entry.content as List<int>);
              break;
            }
          }
        }

        if (pdfBytes != null) {
          final preview = await _renderPdfPage(pdfBytes);
          setState(() {
            _pdfPreviewBytes = preview;
          });
        }
      }
    } catch (e) {
      print("Failed to generate PDF preview: $e");
    } finally {
      setState(() {
        _loadingPreview = false;
      });
    }
  }

  Future<Uint8List> _renderPdfPage(Uint8List pdfBytes) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    js.context.callMethod('renderPdfPageToImage', [pdfBytes, -1, id]);

    final key = 'pdf_render_result_$id';
    while (true) {
      final res = js.context[key];
      if (res != null) {
        final error = res['error'];
        final dataUrl = res['dataUrl'] as String?;

        js.context[key] = null; // Cleanup

        if (error != null) {
          throw Exception(error);
        }

        if (dataUrl != null && dataUrl.startsWith("data:image/png;base64,")) {
          final base64Str = dataUrl.substring("data:image/png;base64,".length);
          return base64Decode(base64Str);
        }
        throw Exception("Invalid render image format");
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  // Excel Metadata Ingestion & Updater variables
  fph.PickedFileData? _selectedExcelFile;
  bool _updatingExcel = false;
  bool _processingAll = false;

  void _applyCoordinatePreset(String preset) {
    setState(() {
      _selectedPreset = preset;
      if (preset == "CAMS Distributor (Default)") {
        _stampX = 400;
        _stampY = 102;
        _sigX = 420;
        _sigY = 72;
        _stampW = 120;
        _stampH = 60;
        _sigW = 120;
        _sigH = 50;
      } else if (preset == "KFintech / Karvy Distributor") {
        _stampX = 430;
        _stampY = 120;
        _sigX = 450;
        _sigY = 80;
        _stampW = 120;
        _stampH = 60;
        _sigW = 120;
        _sigH = 50;
      } else if (preset == "Bottom Right Corner") {
        _stampX = 400;
        _stampY = 150;
        _sigX = 400;
        _sigY = 80;
        _stampW = 120;
        _stampH = 60;
        _sigW = 120;
        _sigH = 50;
      } else if (preset == "Bottom Left Corner") {
        _stampX = 60;
        _stampY = 150;
        _sigX = 60;
        _sigY = 80;
        _stampW = 120;
        _stampH = 60;
        _sigW = 120;
        _sigH = 50;
      }
    });
  }

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

  void _onSearchQueryChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().length < 3) {
      setState(() {
        _searchResults = [];
        _fundSearchError = null;
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performFundSearch(query.trim());
    });
  }

  Future<void> _performFundSearch(String query) async {
    setState(() {
      _searchingFunds = true;
      _fundSearchError = null;
    });

    try {
      final response = await _supabaseService.client.functions.invoke(
        'sign-stamp-invoice',
        body: {
          "action": "proxy-get",
          "url": "https://api.mfapi.in/mf/search?q=${Uri.encodeComponent(query)}",
        },
      ).timeout(const Duration(seconds: 15));

      if (response.status == 200 && response.data != null) {
        final List<dynamic> results = response.data is String
            ? jsonDecode(response.data as String)
            : List<dynamic>.from(response.data as List);
        setState(() {
          _searchResults = results;
          _searchingFunds = false;
          if (results.isEmpty) {
            _fundSearchError = "No funds found matching '$query'.";
          }
        });
      } else {
        throw Exception("Failed to search funds through proxy.");
      }
    } catch (e) {
      setState(() {
        _searchResults = [];
        _searchingFunds = false;
        _fundSearchError = "Failed to search funds: Network error.";
      });
    }
  }

  Future<void> _fetchFundDetails(String schemeCode) async {
    setState(() {
      _fetchingFundDetails = true;
      _fundSearchError = null;
      _searchResults = []; // Close the dropdown
      _fundSearchController.clear(); // Clear search field
    });

    try {
      final response = await _supabaseService.client.functions.invoke(
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
    _fundSearchController.dispose();
    _debounceTimer?.cancel();
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Fund Facts Finder",
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Type a mutual fund name to lookup its real-time scheme classification, ISIN codes, and historical NAV data.",
            style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13),
          ),
          const SizedBox(height: 24),

          // Search Bar Container
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF151030),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextFormField(
                  controller: _fundSearchController,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  onChanged: _onSearchQueryChanged,
                  decoration: InputDecoration(
                    hintText: "Type 3+ characters to search funds (e.g. Axis Bluechip, SBI Liquid)...",
                    hintStyle: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    suffixIcon: _searchingFunds
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE94057)),
                              ),
                            ),
                          )
                        : (_fundSearchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white54),
                                onPressed: () {
                                  setState(() {
                                    _fundSearchController.clear();
                                    _searchResults = [];
                                    _fundSearchError = null;
                                  });
                                },
                              )
                            : null),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
              ),

              // Search Results Dropdown Overlay
              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151030),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
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
                    separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, index) {
                      final item = _searchResults[index];
                      final schemeName = item['schemeName'] as String? ?? '';
                      final schemeCode = (item['schemeCode'] ?? '').toString();

                      return ListTile(
                        title: Text(
                          schemeName,
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                        ),
                        subtitle: Text(
                          "Scheme Code: $schemeCode",
                          style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 11),
                        ),
                        hoverColor: Colors.white.withOpacity(0.04),
                        onTap: () => _fetchFundDetails(schemeCode),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),

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
          if (_fetchingFundDetails) ...[
            const SizedBox(height: 40),
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE94057)),
              ),
            ),
          ] else if (_selectedFundDetails != null) ...[
            _buildSelectedFundCard(),
          ] else ...[
            // Default placeholder card
            Container(
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.search_outlined, color: Colors.grey.shade700, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      "No Fund Selected",
                      style: GoogleFonts.outfit(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Search and select a mutual fund to view its meta information and historical NAV data.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedFundCard() {
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
        color: const Color(0xFF151030),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
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
                        color: const Color(0xFFF27121),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      schemeName,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Scheme Code: $schemeCode",
                      style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 12),
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
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      latestDate,
                      style: GoogleFonts.inter(
                        color: Colors.grey.shade400,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 40),
          
          Text(
            "Scheme Specifications",
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          
          // Specifications Grid
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
                  _buildSpecTile("Scheme Type", schemeType),
                  _buildSpecTile("Category", schemeCategory),
                  _buildSpecTile("ISIN", isin),
                ],
              );
            },
          ),
          
          const Divider(color: Colors.white10, height: 40),

          NavGrowthChart(navData: data),

          const Divider(color: Colors.white10, height: 40),

          Text(
            "Recent Historical NAVs",
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          
          // Historical NAV list
          if (data.isEmpty)
            Text(
              "No historical NAV details available.",
              style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 13),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: data.length > 5 ? 5 : data.length,
                separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, index) {
                  final navItem = data[index];
                  final date = navItem['date'] ?? 'N/A';
                  final navVal = navItem['nav'] ?? 'N/A';
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          date,
                          style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13),
                        ),
                        Text(
                          "₹$navVal",
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpecTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
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
            "Distributor Invoice Signer & Excel Auto-Updater",
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Upload your invoices ZIP/PDF, Excel tracker, transparent signature, and company stamp. The system will automatically overlay the signature/stamp on the final page of the PDFs, parse the invoice details to populate your Excel tracker columns (Invoice No, Date, and Filename), and start the download for both updated files in one go!",
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
            final file = await fph.pickFile('.pdf,.zip,application/pdf,application/zip,application/x-zip-compressed');
            if (file != null) {
              setState(() {
                _selectedInvoicePdf = file;
              });
              _generatePdfPreview();
            }
          },
        ),
        const SizedBox(height: 16),
        _buildUploadCard(
          title: "Excel Invoice Tracker (.xlsx)",
          subtitle: _selectedExcelFile != null ? _selectedExcelFile!.filename : "Select Excel Tracker File",
          icon: Icons.table_chart_outlined,
          isSelected: _selectedExcelFile != null,
          onTap: () async {
            final file = await fph.pickFile('.xlsx');
            if (file != null) {
              setState(() {
                _selectedExcelFile = file;
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

  Widget _buildPdfPreviewWidget() {
    final previewHeight = 400.0;
    final previewWidth = previewHeight * (595.0 / 842.0);

    if (_selectedInvoicePdf == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.picture_as_pdf_outlined, color: Colors.grey.shade600, size: 40),
              const SizedBox(height: 12),
              Text(
                "Upload a PDF or ZIP to see the placement preview",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_loadingPreview) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE94057)),
              ),
              const SizedBox(height: 16),
              Text(
                "Generating visual placement preview...",
                style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_pdfPreviewBytes == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Center(
          child: Text(
            "Could not load PDF page preview",
            style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 12),
          ),
        ),
      );
    }

    // Size of overlays scaled to the preview container:
    final stampW = (_stampW / 595.0) * previewWidth;
    final stampH = (_stampH / 842.0) * previewHeight;
    final stampL = (_stampX / 595.0) * previewWidth;
    final stampT = ((842.0 - (_stampY + _stampH)) / 842.0) * previewHeight;

    final sigW = (_sigW / 595.0) * previewWidth;
    final sigH = (_sigH / 842.0) * previewHeight;
    final sigL = (_sigX / 595.0) * previewWidth;
    final sigT = ((842.0 - (_sigY + _sigH)) / 842.0) * previewHeight;

    return Center(
      child: Column(
        children: [
          Text(
            "Visual Placement Preview (Last Page)",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Drag the Stamp or Signature directly to adjust coordinates",
            style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Container(
            width: previewWidth,
            height: previewHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Rendered PDF Page Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _pdfPreviewBytes!,
                    width: previewWidth,
                    height: previewHeight,
                    fit: BoxFit.cover,
                  ),
                ),

                // Stamp Overlay
                Positioned(
                  left: stampL,
                  top: stampT,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      final pdfDeltaX = (details.delta.dx / previewWidth) * 595.0;
                      final pdfDeltaY = -(details.delta.dy / previewHeight) * 842.0;
                      setState(() {
                        _stampX = (_stampX + pdfDeltaX).clamp(0.0, 595.0 - _stampW);
                        _stampY = (_stampY + pdfDeltaY).clamp(0.0, 842.0 - _stampH);
                        _selectedPreset = "Custom Placement";
                      });
                    },
                    child: Container(
                      width: stampW,
                      height: stampH,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFF27121), width: 2),
                        color: const Color(0xFFF27121).withOpacity(0.2),
                      ),
                      child: _selectedStampPng != null
                          ? Image.memory(
                              _selectedStampPng!.bytes ?? base64Decode(_selectedStampPng!.base64String!),
                              fit: BoxFit.fill,
                            )
                          : const Center(
                              child: Text(
                                "STAMP",
                                style: TextStyle(
                                  color: Color(0xFFF27121),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 8,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),

                // Signature Overlay
                Positioned(
                  left: sigL,
                  top: sigT,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      final pdfDeltaX = (details.delta.dx / previewWidth) * 595.0;
                      final pdfDeltaY = -(details.delta.dy / previewHeight) * 842.0;
                      setState(() {
                        _sigX = (_sigX + pdfDeltaX).clamp(0.0, 595.0 - _sigW);
                        _sigY = (_sigY + pdfDeltaY).clamp(0.0, 842.0 - _sigH);
                        _selectedPreset = "Custom Placement";
                      });
                    },
                    child: Container(
                      width: sigW,
                      height: sigH,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE94057), width: 2),
                        color: const Color(0xFFE94057).withOpacity(0.2),
                      ),
                      child: _selectedSignaturePng != null
                          ? Image.memory(
                              _selectedSignaturePng!.bytes ?? base64Decode(_selectedSignaturePng!.base64String!),
                              fit: BoxFit.fill,
                            )
                          : const Center(
                              child: Text(
                                "SIGNATURE",
                                style: TextStyle(
                                  color: Color(0xFFE94057),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 8,
                                ),
                              ),
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
          const SizedBox(height: 20),
          _buildPdfPreviewWidget(),
          const SizedBox(height: 24),
          Text(
            "Overlay Location Preset",
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedPreset,
                dropdownColor: const Color(0xFF151030),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                isExpanded: true,
                items: [
                  "CAMS Distributor (Default)",
                  "KFintech / Karvy Distributor",
                  "Bottom Right Corner",
                  "Bottom Left Corner",
                  "Custom Placement",
                ].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null && newValue != "Custom Placement") {
                    _applyCoordinatePreset(newValue);
                  } else if (newValue == "Custom Placement") {
                    setState(() {
                      _selectedPreset = newValue!;
                    });
                  }
                },
              ),
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
                _selectedPreset = "Custom Placement";
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
                _selectedPreset = "Custom Placement";
              });
            },
          ),
          _buildCoordinateSlider(
            label: "Company Stamp Width",
            value: _stampW,
            min: 30,
            max: 300,
            onChanged: (val) {
              setState(() {
                _stampW = val;
                _selectedPreset = "Custom Placement";
              });
            },
          ),
          _buildCoordinateSlider(
            label: "Company Stamp Height",
            value: _stampH,
            min: 30,
            max: 300,
            onChanged: (val) {
              setState(() {
                _stampH = val;
                _selectedPreset = "Custom Placement";
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
                _selectedPreset = "Custom Placement";
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
                _selectedPreset = "Custom Placement";
              });
            },
          ),
          _buildCoordinateSlider(
            label: "Distributor Signature Width",
            value: _sigW,
            min: 30,
            max: 300,
            onChanged: (val) {
              setState(() {
                _sigW = val;
                _selectedPreset = "Custom Placement";
              });
            },
          ),
          _buildCoordinateSlider(
            label: "Distributor Signature Height",
            value: _sigH,
            min: 15,
            max: 200,
            onChanged: (val) {
              setState(() {
                _sigH = val;
                _selectedPreset = "Custom Placement";
              });
            },
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _selectedInvoicePdf == null ||
                      _selectedExcelFile == null ||
                      _selectedSignaturePng == null ||
                      _selectedStampPng == null ||
                      _processingAll
                  ? null
                  : _processAllInvoices,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE94057),
                disabledBackgroundColor: Colors.white10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _processingAll
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      "Sign, Stamp & Update Tracker",
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
        final decryptPayload = {
          "invoiceFile": _selectedInvoicePdf!.base64String,
          "action": "decrypt",
        };

        final decryptResponse = await _supabaseService.client.functions.invoke(
          'sign-stamp-invoice',
          body: decryptPayload,
        );

        if (decryptResponse.status != 200 || decryptResponse.data == null) {
          throw Exception(decryptResponse.data?["error"] ?? "Failed to decrypt CAMS zip. Status: ${decryptResponse.status}");
        }

        final Map<String, dynamic> responseData = decryptResponse.data is String 
            ? jsonDecode(decryptResponse.data as String) 
            : Map<String, dynamic>.from(decryptResponse.data as Map);
        
        final List<dynamic> pdfFiles = responseData['files'] ?? [];
        if (pdfFiles.isEmpty) {
          throw Exception("No valid PDF invoices found inside the ZIP archive.");
        }

        final outArchive = archive.Archive();
        final encoder = archive.ZipEncoder();
        int signedCount = 0;

        for (final pdfFile in pdfFiles) {
          final filename = pdfFile['name'] as String;
          final base64Content = pdfFile['content'] as String;

          final signPayload = {
            "invoiceFile": base64Content,
            "signaturePng": _selectedSignaturePng!.base64String,
            "stampPng": _selectedStampPng!.base64String,
            "stampX": _stampX.round(),
            "stampY": _stampY.round(),
            "sigX": _sigX.round(),
            "sigY": _sigY.round(),
            "stampW": _stampW.round(),
            "stampH": _stampH.round(),
            "sigW": _sigW.round(),
            "sigH": _sigH.round(),
          };

          final signResponse = await _supabaseService.client.functions.invoke(
            'sign-stamp-invoice',
            body: signPayload,
          );

          if (signResponse.status == 200 && signResponse.data != null) {
            final Map<String, dynamic> signResponseData = signResponse.data is String 
                ? jsonDecode(signResponse.data as String) 
                : Map<String, dynamic>.from(signResponse.data as Map);
            final base64SignedPdf = signResponseData['signedPdf'] as String;
            final signedBytes = base64Decode(base64SignedPdf);
            
            outArchive.addFile(archive.ArchiveFile(
              filename,
              signedBytes.length,
              signedBytes,
            ));
            signedCount++;
          } else {
            final rawBytes = base64Decode(base64Content);
            outArchive.addFile(archive.ArchiveFile(
              filename,
              rawBytes.length,
              rawBytes,
            ));
          }
        }

        final outputBytes = encoder.encode(outArchive);
        if (outputBytes == null) {
          throw Exception("Failed to package signed files into output ZIP.");
        }

        final uint8Bytes = Uint8List.fromList(outputBytes);
        final outputName = "${originalName.substring(0, originalName.length - 4)}_SIGNED.zip";

        await fph.saveFileBytes(uint8Bytes, outputName);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Batch signing complete! Signed $signedCount of ${pdfFiles.length} PDFs. Download started."),
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
          "stampW": _stampW.round(),
          "stampH": _stampH.round(),
          "sigW": _sigW.round(),
          "sigH": _sigH.round(),
        };

        final response = await _supabaseService.client.functions.invoke(
          'sign-stamp-invoice',
          body: payload,
        );

        if (response.status == 200 && response.data != null) {
          final Map<String, dynamic> responseData = response.data is String 
              ? jsonDecode(response.data as String) 
              : Map<String, dynamic>.from(response.data as Map);
          final base64SignedPdf = responseData['signedPdf'] as String;
          final uint8Bytes = base64Decode(base64SignedPdf);

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

  Future<void> _processAllInvoices() async {
    setState(() {
      _processingAll = true;
    });

    try {
      await _signInvoiceProcess();
      await _updateExcelProcess();
    } catch (e) {
      // Individual sub-methods catch errors and show snackbars
    } finally {
      if (mounted) {
        setState(() {
          _processingAll = false;
        });
      }
    }
  }

  Future<void> _updateExcelProcess() async {
    setState(() {
      _updatingExcel = true;
    });

    try {
      final originalExcelName = _selectedExcelFile!.filename;
      final excelBytes = base64Decode(_selectedExcelFile!.base64String!);
      final zipBytes = base64Decode(_selectedInvoicePdf!.base64String!);

      final result = await ExcelMetadataUpdater.updateExcelMetadata(
        excelBytes: excelBytes,
        zipBytes: zipBytes,
      );

      final uint8Bytes = result['updatedExcel'] as Uint8List;
      final updatedCount = result['updatedCount'] as int;

      final outputName = originalExcelName.toLowerCase().endsWith(".xlsx")
          ? "${originalExcelName.substring(0, originalExcelName.length - 5)}_UPDATED.xlsx"
          : "${originalExcelName}_UPDATED.xlsx";

      await fph.saveFileBytes(uint8Bytes, outputName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Excel updated successfully! Populated $updatedCount invoice records. Download started."),
            backgroundColor: Colors.green,
          ),
        );
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
          _updatingExcel = false;
        });
      }
    }
  }

}

class NavGrowthChart extends StatelessWidget {
  final List<dynamic> navData;

  const NavGrowthChart({super.key, required this.navData});

  @override
  Widget build(BuildContext context) {
    if (navData.isEmpty) return const SizedBox.shrink();

    // Take the last 30 data points (or fewer if not available)
    final int count = navData.length > 30 ? 30 : navData.length;
    final pointsList = navData.take(count).toList().reversed.toList();

    final List<double> navs = pointsList.map((item) {
      return double.tryParse((item['nav'] ?? '0').toString()) ?? 0.0;
    }).toList();

    if (navs.isEmpty) return const SizedBox.shrink();

    final double maxVal = navs.reduce((a, b) => a > b ? a : b);
    final double minVal = navs.reduce((a, b) => a < b ? a : b);
    final double range = maxVal - minVal == 0 ? 1.0 : maxVal - minVal;

    final firstDate = pointsList.first['date'] ?? '';
    final lastDate = pointsList.last['date'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "NAV Growth Trend (Last 30 Days)",
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              "Range: ₹${minVal.toStringAsFixed(2)} - ₹${maxVal.toStringAsFixed(2)}",
              style: GoogleFonts.inter(
                color: const Color(0xFFF27121),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          height: 180,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.01),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.03)),
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
              style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 10),
            ),
            Text(
              lastDate,
              style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 10),
            ),
          ],
        ),
      ],
    );
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
      ..color = Colors.white.withOpacity(0.04)
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
          const Color(0xFFE94057).withOpacity(0.3),
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

