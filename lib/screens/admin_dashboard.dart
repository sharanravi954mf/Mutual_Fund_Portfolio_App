// ignore_for_file: uri_does_not_exist
// ignore_for_file: avoid_web_libraries_in_flutter
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/language_provider.dart';
import 'client_detail_screen.dart';
import 'rupee_rain_background.dart';
import '../services/supabase_service.dart';
import '../utils/file_picker_helper.dart' as fph;
import '../features/invoice_signer/invoice_signer_job_controller.dart';
import '../features/invoice_signer/models/invoice_document.dart';
import '../features/invoice_signer/models/invoice_job.dart';
import '../features/invoice_signer/models/processing_report.dart';
import '../features/invoice_signer/models/registrar_detection_result.dart';
import '../features/invoice_signer/processors/registrar_processor.dart';
import '../features/invoice_signer/services/registrar_detection_service.dart';
import '../features/invoice_signer/services/invoice_pdf_discovery_service.dart';
import '../features/investor_verification/presentation/advisor_verification_queue_screen.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:js' as js;
import 'package:http/http.dart' as http;

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedTab = 0;
  bool _isSidebarExpanded = true;
  String _searchQuery = "";
  bool _isIngesting = false;
  bool _isSyncingNAV = false;
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  final currencyFormat =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  List<Map<String, dynamic>> _allClients = [];
  List<Map<String, dynamic>> _filteredClients = [];

  // Factsheet Management variables
  final SupabaseService _supabaseService = SupabaseService();
  final InvoiceSignerJobController _invoiceSignerJobController =
      InvoiceSignerJobController(SupabaseService());
  List<Map<String, dynamic>> _fundsList = [];
  String? _selectedFundId;
  bool _savingFactsheet = false;
  final TextEditingController _factsheetPdfController = TextEditingController();
  final TextEditingController _factsheetHoldingsUrlController =
      TextEditingController();
  final TextEditingController _factsheetManagersController =
      TextEditingController();
  final TextEditingController _factsheetTopHoldingsController =
      TextEditingController();
  final TextEditingController _factsheetMonthController = TextEditingController(
    text:
        "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-01",
  );

  // Fund Search and Details variables
  final TextEditingController _fundSearchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _searchingFunds = false;
  bool _fetchingFundDetails = false;
  Map<String, dynamic>? _selectedFundDetails;
  String? _fundSearchError;
  Timer? _debounceTimer;
  String _selectedChartRange = "1Y";

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
  String? _previewError;
  final InvoicePdfDiscoveryService _pdfDiscoveryService =
      const InvoicePdfDiscoveryService();

  Future<void> _generatePdfPreview() async {
    if (_selectedInvoicePdf == null) {
      setState(() {
        _pdfPreviewBytes = null;
        _previewError = null;
      });
      return;
    }

    setState(() {
      _loadingPreview = true;
      _pdfPreviewBytes = null;
      _previewError = null;
    });

    try {
      Uint8List? rawBytes;
      if (_selectedInvoicePdf!.bytes != null) {
        rawBytes = _selectedInvoicePdf!.bytes;
      } else if (_selectedInvoicePdf!.base64String != null) {
        rawBytes = base64Decode(_selectedInvoicePdf!.base64String!);
      }

      if (rawBytes == null) {
        throw const FormatException('The uploaded invoice could not be read.');
      }
      final document = _pdfDiscoveryService.discoverFirst(
        sourceFileName: _selectedInvoicePdf!.filename,
        sourceBytes: rawBytes,
      );
      final preview = await _renderPdfPage(document.pdfBytes);
      if (mounted) {
        setState(() {
          _pdfPreviewBytes = preview;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewError = 'Preview unavailable for this invoice file.';
        });
      }
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
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

      final List<Map<String, dynamic>> loaded =
          List<Map<String, dynamic>>.from(response ?? []);

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
          final email = (client['email'] ?? '')
              .toString()
              .toLowerCase(); // fallback email
          final pan = (client['pan'] ?? '').toString().toLowerCase();
          final id = (client['id'] ?? '').toString().toLowerCase();

          return name.contains(q) ||
              email.contains(q) ||
              pan.contains(q) ||
              id.contains(q);
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
                child: Text("Ingestion trigger failed: $e",
                    style: GoogleFonts.inter()),
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
                child: Text("NAV sync complete! Response: ${response.data}",
                    style: GoogleFonts.inter()),
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
                child: Text("NAV sync trigger failed: $e",
                    style: GoogleFonts.inter()),
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
    final cleanQuery = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanQuery.isEmpty) return;

    final keywords =
        cleanQuery.toLowerCase().split(' ').where((k) => k.isNotEmpty).toList();

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
        final response = await _supabaseService.client.functions.invoke(
          'sign-stamp-invoice',
          body: {
            "action": "proxy-get",
            "url":
                "https://api.mfapi.in/mf/search?q=${Uri.encodeComponent(cleanQuery)}",
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

  List<dynamic> filterNavDataByRange(
      List<dynamic> allData, String rangeOption) {
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
        _factsheetHoldingsUrlController.text =
            data['portfolio_holdings_url'] ?? '';
        _factsheetMonthController.text = data['month_year'] ?? '';

        final managersList = data['managers'] as List?;
        _factsheetManagersController.text = managersList?.join(', ') ?? '';

        final holdingsList = data['top_holdings'] as List?;
        if (holdingsList != null) {
          final lines =
              holdingsList.map((h) => "${h['company']}: ${h['weight']}");
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
          content: Text(success
              ? "Factsheet updated successfully!"
              : "Failed to update factsheet."),
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
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final colors = AppThemeColors(isDark);
    final t = languageProvider.translate;
    final showSidebar = MediaQuery.of(context).size.width > 900;

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
                                child: const Icon(Icons.shield_outlined,
                                    color: Colors.white, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "Admin Central",
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
                    const SizedBox(height: 12),

                    // 2. Navigation items
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          _buildDrawerItem(0, t('clients_management'),
                              Icons.people_outline, colors, context),
                          _buildDrawerItem(1, t('verification_queue'),
                              Icons.verified_user_outlined, colors, context),
                          _buildDrawerItem(2, t('data_ingestion'),
                              Icons.cloud_upload_outlined, colors, context),
                          _buildDrawerItem(3, t('factsheets_manager'),
                              Icons.document_scanner_outlined, colors, context),
                          _buildDrawerItem(4, t('invoice_signer'),
                              Icons.draw_outlined, colors, context),
                          _buildDrawerItem(5, t('settings'),
                              Icons.settings_outlined, colors, context),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: colors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.logout,
                                  color: colors.primary, size: 20),
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
                    )
                        .animate(delay: const Duration(milliseconds: 6 * 80))
                        .fadeIn(duration: 800.ms, curve: Curves.easeOutCubic)
                        .blur(
                            begin: const Offset(8, 8),
                            end: Offset.zero,
                            duration: 800.ms,
                            curve: Curves.easeOutCubic)
                        .slide(
                            begin: const Offset(-0.15, 0),
                            end: Offset.zero,
                            duration: 800.ms,
                            curve: Curves.easeOutCubic),
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
                child: const Icon(Icons.shield_outlined,
                    color: Colors.white, size: 20),
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
              _selectedTab == 0
                  ? t('clients_directory')
                  : (_selectedTab == 1
                      ? t('verification_queue')
                      : (_selectedTab == 2
                          ? t('data_ingestion_engine')
                          : (_selectedTab == 3
                              ? t('factsheets_manager')
                              : (_selectedTab == 4
                                  ? t('invoice_signer')
                                  : t('settings_console'))))),
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
            onPressed: _refreshClients,
            tooltip: t('refresh_data'),
          ),
          IconButton(
            icon: Icon(Icons.logout, color: colors.textSecondary),
            onPressed: () => authProvider.signOut(),
          ),
        ],
      ),
      body: RupeeRainBackground(
        child: _buildSelectedTabContent()
            .animate()
            .fadeIn(duration: 1000.ms, curve: Curves.easeInOutCubic),
      ),
    );

    if (!showSidebar) {
      return mainScaffold;
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: RupeeRainBackground(
        child: Column(
          children: [
            // Full-Width Top Header Bar on Top of Everything
            _buildTopHeaderBar(colors, t, authProvider),
            Expanded(
              child: Row(
                children: [
                  _buildDesktopSidebar(colors, t, authProvider),
                  Expanded(
                    child: SafeArea(
                      child: _buildSelectedTabContent(),
                    ).animate().fadeIn(
                        duration: 1000.ms, curve: Curves.easeInOutCubic),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeaderBar(AppThemeColors colors, String Function(String) t,
      AuthProvider authProvider) {
    final sectionTitle = _selectedTab == 0
        ? t('clients_directory')
        : (_selectedTab == 1
            ? t('verification_queue')
            : (_selectedTab == 2
                ? t('data_ingestion_engine')
                : (_selectedTab == 3
                    ? t('factsheets_manager')
                    : (_selectedTab == 4
                        ? t('invoice_signer')
                        : t('settings_console')))));

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: App Logo + Sharan Fincorp Title + Section Breadcrumb
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shield_outlined,
                    color: Colors.white, size: 20),
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
              Text(
                sectionTitle,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),

          // Right: Refresh Action, Admin Greeting, and Profile Avatar with Logout Menu
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.refresh, color: colors.textSecondary),
                tooltip: t('refresh_data'),
                onPressed: _refreshClients,
              ),
              const SizedBox(width: 12),
              Text(
                "Welcome back, Admin!",
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 14),
              PopupMenuButton<int>(
                tooltip: "Admin Account Settings",
                icon: CircleAvatar(
                  radius: 18,
                  backgroundColor: colors.primary.withValues(alpha: 0.15),
                  child: Text(
                    "A",
                    style: GoogleFonts.outfit(
                      color: colors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
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
                  PopupMenuItem<int>(
                    enabled: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authProvider.user?.email ?? "Admin User",
                          style: GoogleFonts.outfit(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "System Administrator",
                          style: GoogleFonts.inter(
                            color: colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<int>(
                    value: 1,
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: colors.error, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          t('logout'),
                          style: GoogleFonts.inter(
                            color: colors.error,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebar(AppThemeColors colors, String Function(String) t,
      AuthProvider authProvider) {
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
          // 1. Top of Left Panel: Icons.menu (Three Horizontal Lines Menu Icon)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: Row(
              mainAxisAlignment: _isSidebarExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(Icons.menu, color: colors.sidebarTextPrimary, size: 22),
                if (_isSidebarExpanded) ...[
                  const SizedBox(width: 12),
                  Text(
                    "Admin Central",
                    style: GoogleFonts.outfit(
                      color: colors.sidebarTextPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(color: colors.sidebarBorder, height: 1),
          const SizedBox(height: 12),

          // 3. Navigation items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildSidebarItem(
                    0, t('clients_management'), Icons.people_outline, colors),
                _buildSidebarItem(1, t('verification_queue'),
                    Icons.verified_user_outlined, colors),
                _buildSidebarItem(2, t('data_ingestion'),
                    Icons.cloud_upload_outlined, colors),
                _buildSidebarItem(3, t('factsheets_manager'),
                    Icons.document_scanner_outlined, colors),
                _buildSidebarItem(
                    4, t('invoice_signer'), Icons.draw_outlined, colors),
                _buildSidebarItem(
                    5, t('settings'), Icons.settings_outlined, colors),
              ],
            ),
          ),

          Divider(color: colors.sidebarBorder, height: 1),

          // 4. Bottom Right of Left Panel: arrow_back Icon Button to Shrink/Expand Left Panel
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: _isSidebarExpanded
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.center,
              children: [
                Tooltip(
                  message: _isSidebarExpanded ? 'Shrink Menu' : 'Expand Menu',
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _isSidebarExpanded = !_isSidebarExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.sidebarSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.sidebarBorder),
                      ),
                      child: Icon(
                        _isSidebarExpanded ? Icons.arrow_back : Icons.menu,
                        color: colors.sidebarTextSecondary,
                        size: 20,
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

  Widget _buildSidebarItem(
      int index, String title, IconData icon, AppThemeColors colors) {
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
                if (index == 3) {
                  _fetchFundsList();
                }
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
                  color: isSelected
                      ? colors.sidebarTextPrimary
                      : colors.sidebarTextSecondary,
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
            if (index == 3) {
              _fetchFundsList();
            }
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
                color: isSelected
                    ? colors.sidebarTextPrimary
                    : colors.sidebarTextSecondary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: isSelected
                        ? colors.sidebarTextPrimary
                        : colors.sidebarTextSecondary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
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

  Widget _buildDrawerItem(int index, String label, IconData icon,
      AppThemeColors colors, BuildContext context) {
    final isSelected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: InkWell(
        onTap: () {
          Navigator.pop(context); // Close the drawer natively
          setState(() {
            _selectedTab = index;
            if (index == 3) {
              _fetchFundsList();
            }
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: isSelected ? colors.sidebarActive : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: isSelected
                      ? colors.sidebarTextPrimary
                      : colors.sidebarTextSecondary,
                  size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: isSelected
                        ? colors.sidebarTextPrimary
                        : colors.sidebarTextSecondary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
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

  Widget _buildSelectedTabContent() {
    switch (_selectedTab) {
      case 0:
        return _buildClientsListContent();
      case 1:
        return const AdvisorVerificationQueueScreen();
      case 2:
        return _buildIngestionContent();
      case 3:
        return _buildFactsheetsContent();
      case 4:
        return _buildInvoiceSignerContent();
      case 5:
        return _buildSettingsContent();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildClientsListContent() {
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode(context);
    final colors = AppThemeColors(isDark);

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
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
            style: GoogleFonts.inter(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: "Search clients by full name or PAN code...",
              hintStyle: GoogleFonts.inter(color: colors.placeholder),
              prefixIcon: Icon(Icons.search, color: colors.textSecondary),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: colors.textSecondary),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged("");
                      },
                    )
                  : null,
              filled: true,
              fillColor: colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.primary, width: 1.5),
              ),
            ),
          ).premiumReveal(index: 0),
          const SizedBox(height: 20),

          // Directory count
          Text(
            "Showing ${_filteredClients.length} of ${_allClients.length} registered clients",
            style: GoogleFonts.inter(color: colors.textSecondary, fontSize: 13),
          ).premiumReveal(index: 1),
          const SizedBox(height: 16),

          // Client List Table / ListView
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border, width: 1),
              ),
              child: _filteredClients.isEmpty
                  ? Center(
                      child: Text(
                        "No matching client profiles found.",
                        style: GoogleFonts.inter(color: colors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filteredClients.length,
                      separatorBuilder: (context, index) =>
                          Divider(color: colors.border, height: 1),
                      itemBuilder: (context, index) {
                        final client = _filteredClients[index];
                        final name = client['full_name'] ?? 'Unnamed Client';
                        final pan = client['pan'] ?? 'PAN Pending';
                        final id = client['id'].toString().substring(0, 8);

                        // Extract market value from portfolio lists
                        final portfolios =
                            client['portfolios'] as List<dynamic>?;
                        double marketVal = 0.0;
                        if (portfolios != null && portfolios.isNotEmpty) {
                          marketVal =
                              (portfolios.first['current_market_value'] as num)
                                  .toDouble();
                        }

                        return Material(
                          color: index % 2 == 1
                              ? colors.tableRowAlt
                              : colors.surface,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
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
                              backgroundColor: colors.activeBackground,
                              child: Text(
                                name.isNotEmpty
                                    ? name.substring(0, 1).toUpperCase()
                                    : 'C',
                                style: GoogleFonts.outfit(
                                    color: colors.primary,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(
                              name,
                              style: GoogleFonts.outfit(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                "PAN: ${pan.toUpperCase()}  •  ID: $id",
                                style: GoogleFonts.inter(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                            trailing: Text(
                              currencyFormat.format(marketVal),
                              style: GoogleFonts.outfit(
                                color: marketVal > 0
                                    ? colors.profit
                                    : colors.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ).premiumReveal(index: 2),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Advisor Automation Tools",
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                "Manage connection states and execute manual file parsers.",
                style: GoogleFonts.inter(
                    color: Colors.grey.shade400, fontSize: 13),
              ),
            ],
          ).premiumReveal(index: 0),
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
                    const Icon(Icons.sync_alt,
                        color: Color(0xFFE94057), size: 24),
                    const SizedBox(width: 12),
                    Text(
                      "Force RTA Statement Sync",
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "Triggering this command immediately establishes secure IMAP tunnels, fetches new CAMS/KFintech mailbacks, runs decryptions, parses transactions, and logs outputs without waiting for midnight.",
                  style: GoogleFonts.inter(
                      color: Colors.grey.shade400, fontSize: 13, height: 1.4),
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
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.cloud_download_outlined,
                            color: Colors.white),
                    label: Text(
                      _isIngesting
                          ? "Syncing Mailbox..."
                          : "Execute Manual Ingestion Now",
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.white),
                    ),
                    onPressed: _isIngesting ? null : _triggerManualIngestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94057),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ).premiumReveal(index: 1),
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
                    const Icon(Icons.currency_rupee,
                        color: Color(0xFFF27121), size: 24),
                    const SizedBox(width: 12),
                    Text(
                      "Force Daily NAV Price Sync",
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "Queries the mfapi.in API database for all registered mutual funds to fetch today's latest Net Asset Values and updates client portfolio valuations.",
                  style: GoogleFonts.inter(
                      color: Colors.grey.shade400, fontSize: 13, height: 1.4),
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
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.trending_up, color: Colors.white),
                    label: Text(
                      _isSyncingNAV
                          ? "Syncing NAV Prices..."
                          : "Sync Daily NAV Prices Now",
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.white),
                    ),
                    onPressed: _isSyncingNAV ? null : _triggerNAVUpdateSync,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF27121),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ).premiumReveal(index: 2),
        ],
      ),
    );
  }

  Widget _buildFactsheetsContent() {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode(context);
    final colors = AppThemeColors(isDark);
    final t = languageProvider.translate;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('fund_facts_finder'),
                style: GoogleFonts.outfit(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t('fund_facts_finder_sub'),
                style: GoogleFonts.inter(
                    color: colors.textSecondary, fontSize: 13),
              ),
            ],
          ).premiumReveal(index: 0),
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
                  style: GoogleFonts.inter(
                      color: colors.textPrimary, fontSize: 14),
                  onChanged: _onSearchQueryChanged,
                  decoration: InputDecoration(
                    hintText: t('search_funds_placeholder'),
                    hintStyle: GoogleFonts.inter(
                        color: colors.textMuted, fontSize: 13),
                    prefixIcon: Icon(Icons.search, color: colors.textSecondary),
                    suffixIcon: _searchingFunds
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFFE94057)),
                              ),
                            ),
                          )
                        : (_fundSearchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    color: Colors.white54),
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                  ),
                ),
              ),

              // Search Results Dropdown Overlay
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
                          style: GoogleFonts.inter(
                              color: colors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          "Scheme Code: $schemeCode",
                          style: GoogleFonts.inter(
                              color: colors.textSecondary, fontSize: 11),
                        ),
                        hoverColor: colors.surfaceAccent,
                        onTap: () => _fetchFundDetails(schemeCode),
                      );
                    },
                    separatorBuilder: (context, index) =>
                        Divider(color: colors.border, height: 1),
                  ),
                ),
              ],
            ],
          ).premiumReveal(index: 1),

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
                  const Icon(Icons.error_outline,
                      color: Colors.redAccent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _fundSearchError!,
                      style: GoogleFonts.inter(
                          color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          (_fetchingFundDetails
                  ? const Padding(
                      padding: EdgeInsets.only(top: 40.0),
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFFE94057)),
                        ),
                      ),
                    )
                  : (_selectedFundDetails != null
                      ? _buildSelectedFundCard()
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 60, horizontal: 24),
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
                                Icon(Icons.search_outlined,
                                    color: colors.textMuted, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  t('no_fund_selected'),
                                  style: GoogleFonts.outfit(
                                      color: colors.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  t('no_fund_selected_sub'),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                      color: colors.textSecondary,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        )))
              .premiumReveal(index: 2),
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
    final isin =
        meta['isin_div_payout'] ?? meta['isin_div_reinvestment'] ?? 'N/A';

    String latestDate = 'N/A';
    String latestNav = 'N/A';
    if (data.isNotEmpty) {
      latestDate = data[0]['date'] ?? 'N/A';
      latestNav = data[0]['nav'] ?? 'N/A';
    }

    final isDark = Provider.of<ThemeProvider>(context).isDarkMode(context);
    final colors = AppThemeColors(isDark);
    final t = Provider.of<LanguageProvider>(context).translate;

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
                      style: GoogleFonts.inter(
                          color: colors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // NAV Tag
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE94057).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFFE94057).withOpacity(0.3)),
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
                      _buildSpecTile("Scheme Type", schemeType),
                      _buildSpecTile("Category", schemeCategory),
                      _buildSpecTile("ISIN", isin),
                    ],
                  );
                },
              ),
            ],
          ).premiumReveal(index: 1),
          const Divider(color: Colors.white10, height: 40),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;

              // Filter the data based on selection
              final filteredData =
                  filterNavDataByRange(data, _selectedChartRange);

              // Calculate growth percent
              double growthPercent = 0.0;
              if (filteredData.isNotEmpty) {
                final double latest =
                    double.tryParse(filteredData.first['nav'].toString()) ??
                        0.0;
                final double oldest =
                    double.tryParse(filteredData.last['nav'].toString()) ?? 0.0;
                growthPercent =
                    oldest == 0.0 ? 0.0 : ((latest - oldest) / oldest) * 100;
              }

              final chartCol = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "NAV Growth Trend (${_getRangeLabel(_selectedChartRange)})",
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      // Growth Percent Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: growthPercent >= 0
                              ? Colors.green.withOpacity(0.15)
                              : Colors.redAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: growthPercent >= 0
                                  ? Colors.green.withOpacity(0.3)
                                  : Colors.redAccent.withOpacity(0.3)),
                        ),
                        child: Text(
                          "${growthPercent >= 0 ? '+' : ''}${growthPercent.toStringAsFixed(2)}%",
                          style: GoogleFonts.inter(
                            color: growthPercent >= 0
                                ? Colors.green
                                : Colors.redAccent,
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
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.04)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Time Range",
                      style: GoogleFonts.outfit(
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...["YTD", "1Y", "2Y", "3Y", "5Y", "Since Launch"]
                        .map((range) {
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
                                    color: isSelected
                                        ? const Color(0xFFE94057)
                                        : Colors.grey.shade600,
                                    width: isSelected ? 5 : 2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _getRangeLabel(range),
                                style: GoogleFonts.inter(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.grey.shade400,
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
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
          const Divider(color: Colors.white10, height: 40),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Recent Historical NAVs",
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              if (data.isEmpty)
                Text(
                  "No historical NAV details available.",
                  style: GoogleFonts.inter(
                      color: Colors.grey.shade500, fontSize: 13),
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
                    separatorBuilder: (context, index) =>
                        const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (context, index) {
                      final navItem = data[index];
                      final date = navItem['date'] ?? 'N/A';
                      final navVal = navItem['nav'] ?? 'N/A';

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              date,
                              style: GoogleFonts.inter(
                                  color: Colors.grey.shade400, fontSize: 13),
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
          ).premiumReveal(index: 3),
        ],
      ),
    );
  }

  Widget _buildSpecTile(String label, String value) {
    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode(context);
    final colors = AppThemeColors(isDark);
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
            style: GoogleFonts.inter(
                color: colors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold),
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
          Column(
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
            ],
          ).premiumReveal(index: 0),
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
          ).premiumReveal(index: 1),
        ],
      ),
    );
  }

  Widget _buildUploadPanel() {
    return Column(
      children: [
        _buildUploadCard(
          title: _selectedInvoicePdf != null &&
                  _selectedInvoicePdf!.filename.toLowerCase().endsWith(".zip")
              ? "Distributor Invoice ZIP Archive"
              : "Distributor Invoice PDF / ZIP",
          subtitle: _selectedInvoicePdf != null
              ? _selectedInvoicePdf!.filename
              : "Select PDF Invoice or ZIP Archive",
          icon: _selectedInvoicePdf != null &&
                  _selectedInvoicePdf!.filename.toLowerCase().endsWith(".zip")
              ? Icons.archive_outlined
              : Icons.picture_as_pdf_outlined,
          isSelected: _selectedInvoicePdf != null,
          onTap: () async {
            final file = await fph.pickFile(
                '.pdf,.zip,application/pdf,application/zip,application/x-zip-compressed');
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
          title: "Excel Invoice Tracker (.xlsx, .xls, .csv)",
          subtitle: _selectedExcelFile != null
              ? _selectedExcelFile!.filename
              : "Select Excel Tracker File (Optional)",
          icon: Icons.table_chart_outlined,
          isSelected: _selectedExcelFile != null,
          onTap: () async {
            final file = await fph.pickFile(
                '.xlsx,.xls,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel,text/csv');
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
          subtitle: _selectedSignaturePng != null
              ? _selectedSignaturePng!.filename
              : "Select signature_transparent.png",
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
          subtitle: _selectedStampPng != null
              ? _selectedStampPng!.filename
              : "Select stamp_transparent.png",
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
                color: isSelected
                    ? const Color(0xFFE94057).withOpacity(0.1)
                    : Colors.black26,
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
                      color: isSelected
                          ? Colors.grey.shade300
                          : Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle : Icons.arrow_forward_ios,
              color:
                  isSelected ? const Color(0xFFE94057) : Colors.grey.shade700,
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
              Icon(Icons.picture_as_pdf_outlined,
                  color: Colors.grey.shade600, size: 40),
              const SizedBox(height: 12),
              Text(
                "Upload a PDF or ZIP to see the placement preview",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: Colors.grey.shade500, fontSize: 12),
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
                style: GoogleFonts.inter(
                    color: Colors.grey.shade400, fontSize: 12),
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
            _previewError ?? 'Could not load PDF page preview',
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
                      final pdfDeltaX =
                          (details.delta.dx / previewWidth) * 595.0;
                      final pdfDeltaY =
                          -(details.delta.dy / previewHeight) * 842.0;
                      setState(() {
                        _stampX =
                            (_stampX + pdfDeltaX).clamp(0.0, 595.0 - _stampW);
                        _stampY =
                            (_stampY + pdfDeltaY).clamp(0.0, 842.0 - _stampH);
                        _selectedPreset = "Custom Placement";
                      });
                    },
                    child: Container(
                      width: stampW,
                      height: stampH,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: const Color(0xFFF27121), width: 2),
                        color: const Color(0xFFF27121).withOpacity(0.2),
                      ),
                      child: _selectedStampPng != null
                          ? Image.memory(
                              _selectedStampPng!.bytes ??
                                  base64Decode(
                                      _selectedStampPng!.base64String!),
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
                      final pdfDeltaX =
                          (details.delta.dx / previewWidth) * 595.0;
                      final pdfDeltaY =
                          -(details.delta.dy / previewHeight) * 842.0;
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
                        border: Border.all(
                            color: const Color(0xFFE94057), width: 2),
                        color: const Color(0xFFE94057).withOpacity(0.2),
                      ),
                      child: _selectedSignaturePng != null
                          ? Image.memory(
                              _selectedSignaturePng!.bytes ??
                                  base64Decode(
                                      _selectedSignaturePng!.base64String!),
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
          if (_lastProcessingReport != null) ...[
            const SizedBox(height: 12),
            Text(
              _lastProcessingReport!.errors.isNotEmpty
                  ? 'Invoice source could not be confirmed.'
                  : 'Invoice source: ${_lastProcessingReport!.invoiceSourceLabel} • ${_lastProcessingReport!.detection.invoicesFound} invoices found',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: _lastProcessingReport!.errors.isNotEmpty
                    ? Colors.redAccent
                    : Colors.greenAccent,
              ),
            ),
          ],
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _selectedInvoicePdf == null ||
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
                      _selectedExcelFile != null
                          ? "Sign, Stamp & Update Tracker"
                          : "Sign & Stamp Invoices",
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

  List<InvoiceDocument> _lastInvoiceDocuments = [];
  bool _lastSigningSourceWasZip = false;
  final RegistrarDetectionService _registrarDetectionService =
      RegistrarDetectionService();
  ProcessingReport? _lastProcessingReport;

  Future<SigningJobResult?> _signInvoiceProcess(
      {RegistrarType? registrar}) async {
    setState(() {
      _signingInvoice = true;
    });

    try {
      final result = await _invoiceSignerJobController.sign(
        sourceFileName: _selectedInvoicePdf!.filename,
        sourceBase64: _selectedInvoicePdf!.base64String!,
        signatureBase64: _selectedSignaturePng!.base64String!,
        stampBase64: _selectedStampPng!.base64String!,
        registrar: registrar,
        placement: SignaturePlacement(
          stampX: _stampX,
          stampY: _stampY,
          signatureX: _sigX,
          signatureY: _sigY,
          stampWidth: _stampW,
          stampHeight: _stampH,
          signatureWidth: _sigW,
          signatureHeight: _sigH,
        ),
      );
      _lastInvoiceDocuments = result.documents;
      _lastSigningSourceWasZip = result.isZip;
      await fph.saveFileBytes(result.outputBytes, result.outputFileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          result.isZip
              ? SnackBar(
                  content: Text(
                      'Batch signing complete! Signed ${result.signedCount} of ${result.documents.length} PDFs. Download started.'),
                  backgroundColor: Colors.green,
                )
              : const SnackBar(
                  content:
                      Text('Invoice signed successfully! Download started.'),
                  backgroundColor: Colors.green,
                ),
        );
      }
      return result;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return null;
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

    RegistrarDetectionResult? detection;
    try {
      if (_selectedExcelFile != null) {
        detection = await _detectRegistrar();
        if (!detection.isConfirmed || detection.registrar == null) {
          _publishProcessingReport(
            ProcessingReport(
              detection: detection,
              invoicesSigned: 0,
              trackerRowsUpdated: 0,
              unmatchedInvoices: 0,
              errors: const ['Invoice source could not be confirmed.'],
            ),
          );
          return;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Invoice source: ${_invoiceSourceLabel(detection.registrar!)}. ${detection.invoicesFound} invoices found. Processing invoices…',
              ),
            ),
          );
        }
      }

      final signing =
          await _signInvoiceProcess(registrar: detection?.registrar);
      if (signing == null) {
        if (detection != null) {
          _publishProcessingReport(
            ProcessingReport(
              detection: detection,
              invoicesSigned: 0,
              trackerRowsUpdated: 0,
              unmatchedInvoices: 0,
              errors: const ['Invoice signing did not complete.'],
            ),
          );
        }
        return;
      }

      if (detection != null) {
        final trackerUpdate = await _updateExcelProcess(detection.registrar!);
        if (trackerUpdate == null) {
          _publishProcessingReport(
            ProcessingReport(
              detection: detection,
              invoicesSigned: signing.signedCount,
              trackerRowsUpdated: 0,
              unmatchedInvoices: detection.invoicesFound,
              errors: const ['Tracker update did not complete.'],
            ),
          );
          return;
        }
        _publishProcessingReport(
          ProcessingReport(
            detection: detection,
            invoicesSigned: signing.signedCount,
            trackerRowsUpdated: trackerUpdate.updatedCount,
            unmatchedInvoices: math.max(
              0,
              detection.invoicesFound - trackerUpdate.updatedCount,
            ),
            warnings: signing.signedCount < signing.documents.length
                ? const ['Some invoices could not be signed.']
                : const [],
          ),
        );
      }
    } catch (error) {
      _publishProcessingReport(
        ProcessingReport(
          detection: detection ??
              RegistrarDetectionResult.unknown(
                reason: 'Unexpected Invoice Signer error: $error',
              ),
          invoicesSigned: 0,
          trackerRowsUpdated: 0,
          unmatchedInvoices: 0,
          errors: const ['Invoice processing did not complete.'],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingAll = false;
        });
      }
    }
  }

  Future<RegistrarDetectionResult> _detectRegistrar() async {
    return _registrarDetectionService.detect(
      trackerBytes: base64Decode(_selectedExcelFile!.base64String!),
      archiveBytes: base64Decode(_selectedInvoicePdf!.base64String!),
    );
  }

  String _invoiceSourceLabel(RegistrarType registrar) => switch (registrar) {
        RegistrarType.cams => 'CAMS',
        RegistrarType.kfintech => 'KFintech',
      };

  void _publishProcessingReport(ProcessingReport report) {
    if (!mounted) return;
    setState(() => _lastProcessingReport = report);
    final hasErrors = report.errors.isNotEmpty;
    final summary = hasErrors
        ? 'We could not confirm the invoice source. Please upload matching invoice and tracker files.'
        : report.trackerRowsUpdated == 0 && report.detection.invoicesFound > 0
            ? 'Invoice source: ${report.invoiceSourceLabel}. No matching invoices found.'
            : 'Invoice source: ${report.invoiceSourceLabel}. Signed ${report.invoicesSigned} invoices and updated ${report.trackerRowsUpdated} tracker rows.'
                '${report.unmatchedInvoices > 0 ? ' ${report.unmatchedInvoices} invoices had no tracker match.' : ''}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(summary),
        backgroundColor: hasErrors ? Colors.redAccent : Colors.green,
      ),
    );
  }

  Future<ExcelUpdateResult?> _updateExcelProcess(
      RegistrarType registrar) async {
    if (_selectedExcelFile == null) return null;

    setState(() {
      _updatingExcel = true;
    });

    try {
      final originalExcelName = _selectedExcelFile!.filename;
      final excelBytes = base64Decode(_selectedExcelFile!.base64String!);

      final extIndex = originalExcelName.lastIndexOf('.');
      final baseName = extIndex != -1
          ? originalExcelName.substring(0, extIndex)
          : originalExcelName;
      final ext = extIndex != -1
          ? originalExcelName.substring(extIndex).toLowerCase()
          : '.xlsx';

      final result = await _invoiceSignerJobController.updateTracker(
        registrar: registrar,
        trackerBytes: excelBytes,
        fileExtension: ext,
        documents: _lastInvoiceDocuments,
        sourceWasZip: _lastSigningSourceWasZip,
      );

      final uint8Bytes = result.updatedBytes;
      final updatedCount = result.updatedCount;
      final outputName = "${baseName}_UPDATED$ext";

      if (updatedCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No matching invoices found.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return result;
      }

      await fph.saveFileBytes(uint8Bytes, outputName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "Excel updated successfully! Populated $updatedCount invoice records. Download started."),
            backgroundColor: Colors.green,
          ),
        );
      }
      return result;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _updatingExcel = false;
        });
      }
    }
  }

  Widget _buildSettingsContent() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isDark = themeProvider.isDarkMode(context);
    final colors = AppThemeColors(isDark);
    final t = languageProvider.translate;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Submenu 1: Theme Settings
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('display_settings'),
                style: GoogleFonts.outfit(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t('display_settings_sub'),
                style: GoogleFonts.inter(
                  color: colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ).premiumReveal(index: 0),
          const SizedBox(height: 16),
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
                ]),
            child: Column(
              children: [
                _buildThemeOptionTile(
                  title: t('light_mode'),
                  subtitle: t('light_mode_sub'),
                  icon: Icons.light_mode_outlined,
                  option: ThemeModeOption.light,
                  themeProvider: themeProvider,
                  colors: colors,
                ),
                Divider(color: colors.border, height: 1),
                _buildThemeOptionTile(
                  title: t('dark_mode'),
                  subtitle: t('dark_mode_sub'),
                  icon: Icons.dark_mode_outlined,
                  option: ThemeModeOption.dark,
                  themeProvider: themeProvider,
                  colors: colors,
                ),
                Divider(color: colors.border, height: 1),
                _buildThemeOptionTile(
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

          // Live Money Wallpaper Settings
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Live Money Wallpaper",
                style: GoogleFonts.outfit(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Customize live animated financial backgrounds across the application.",
                style: GoogleFonts.inter(
                  color: colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ).premiumReveal(index: 2),
          const SizedBox(height: 16),
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
                ]),
            child: Column(
              children: [
                _buildWallpaperOptionTile(
                  title: "Currency Rain (Rupees & Gains)",
                  subtitle: "Floating animated ₹, \$, €, %, 📈 money particles",
                  icon: Icons.attach_money_outlined,
                  option: MoneyWallpaperOption.rupeeRain,
                  themeProvider: themeProvider,
                  colors: colors,
                ),
                Divider(color: colors.border, height: 1),
                _buildWallpaperOptionTile(
                  title: "Golden Wealth Orbs",
                  subtitle:
                      "Ambient glowing wealth circles and growth trend curves",
                  icon: Icons.auto_awesome_outlined,
                  option: MoneyWallpaperOption.goldenWealth,
                  themeProvider: themeProvider,
                  colors: colors,
                ),
                Divider(color: colors.border, height: 1),
                _buildWallpaperOptionTile(
                  title: "Disabled",
                  subtitle: "Plain solid canvas background",
                  icon: Icons.hide_image_outlined,
                  option: MoneyWallpaperOption.disabled,
                  themeProvider: themeProvider,
                  colors: colors,
                ),
              ],
            ),
          ).premiumReveal(index: 3),

          const SizedBox(height: 36),

          // Submenu 2: Language Settings
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('language_settings'),
                style: GoogleFonts.outfit(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t('language_settings_sub'),
                style: GoogleFonts.inter(
                  color: colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ).premiumReveal(index: 2),
          const SizedBox(height: 16),
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
                ]),
            child: Column(
              children: [
                _buildLanguageOptionTile(
                  title: "English",
                  subtitle: "Default interface language",
                  langCode: "en",
                  languageProvider: languageProvider,
                  colors: colors,
                ),
                Divider(color: colors.border, height: 1),
                _buildLanguageOptionTile(
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

  Widget _buildThemeOptionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required ThemeModeOption option,
    required ThemeProvider themeProvider,
    required AppThemeColors colors,
  }) {
    final isSelected = themeProvider.themeModeOption == option;
    return InkWell(
      onTap: () {
        themeProvider.setThemeMode(option);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon,
                color: isSelected ? colors.primary : colors.textSecondary,
                size: 24),
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
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
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

  Widget _buildWallpaperOptionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required MoneyWallpaperOption option,
    required ThemeProvider themeProvider,
    required AppThemeColors colors,
  }) {
    final isSelected = themeProvider.wallpaperOption == option;
    return InkWell(
      onTap: () {
        themeProvider.setWallpaperOption(option);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon,
                color: isSelected ? colors.primary : colors.textSecondary,
                size: 24),
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
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
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

  Widget _buildLanguageOptionTile({
    required String title,
    required String subtitle,
    required String langCode,
    required LanguageProvider languageProvider,
    required AppThemeColors colors,
  }) {
    final isSelected = languageProvider.currentLanguage == langCode;
    return InkWell(
      onTap: () {
        languageProvider.setLanguage(langCode);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.language,
                color: isSelected ? colors.primary : colors.textSecondary,
                size: 24),
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
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 180,
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
              style:
                  GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 10),
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
              style:
                  GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 10),
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
    final Path areaPath = Path()..moveTo(0, height);
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
    final Path linePath = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final controlPoint1 = Offset(p1.dx + stepX / 2.0, p1.dy);
      final controlPoint2 = Offset(p2.dx - stepX / 2.0, p2.dy);
      linePath.cubicTo(
        controlPoint1.dx,
        controlPoint1.dy,
        controlPoint2.dx,
        controlPoint2.dy,
        p2.dx,
        p2.dy,
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
    return this
        .animate(delay: Duration(milliseconds: index * staggerMs))
        .fadeIn(duration: 1000.ms, curve: Curves.easeInOutCubic)
        .blur(
            begin: const Offset(10, 10),
            end: Offset.zero,
            duration: 1000.ms,
            curve: Curves.easeInOutCubic)
        .slide(
            begin: const Offset(0, 0.2),
            end: Offset.zero,
            duration: 1000.ms,
            curve: Curves.easeInOutCubic);
  }
}
