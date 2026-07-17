import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';

class FactsheetDialog extends StatefulWidget {
  final String fundId;
  final String schemeName;
  final String category;
  final String fundHouse;

  const FactsheetDialog({
    Key? key,
    required this.fundId,
    required this.schemeName,
    required this.category,
    required this.fundHouse,
  }) : super(key: key);

  @override
  State<FactsheetDialog> createState() => _FactsheetDialogState();
}

class _FactsheetDialogState extends State<FactsheetDialog> {
  final SupabaseService _supabaseService = SupabaseService();
  bool _isLoading = true;
  Map<String, dynamic>? _factsheet;

  @override
  void initState() {
    super.initState();
    _loadFactsheet();
  }

  Future<void> _loadFactsheet() async {
    final data = await _supabaseService.getLatestFactsheet(widget.fundId);
    if (mounted) {
      setState(() {
        _factsheet = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _openUrl(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $urlString')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Dialog(
      backgroundColor: const Color(0xFF151030),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: isMobile ? double.infinity : 600,
        padding: const EdgeInsets.all(24.0),
        child: _isLoading
            ? const SizedBox(
                height: 200,
                child: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFE94057),
                  ),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                                widget.schemeName,
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${widget.category} • ${widget.fundHouse}",
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 24),

                    if (_factsheet == null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.description_outlined,
                                  size: 48, color: Colors.grey.shade600),
                              const SizedBox(height: 12),
                              Text(
                                "No Factsheet Data Available Yet",
                                style: GoogleFonts.inter(
                                  color: Colors.grey.shade400,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Factsheets are updated monthly by the administrator.",
                                style: GoogleFonts.inter(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // Disclosure Date
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Report Month",
                            style: GoogleFonts.inter(
                              color: Colors.grey.shade400,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            _factsheet!['month_year'] ?? "N/A",
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Fund Managers
                      Text(
                        "Fund Managers",
                        style: GoogleFonts.inter(
                          color: Colors.grey.shade300,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ((_factsheet!['managers'] as List?) ?? [])
                            .map((m) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.1),
                                    ),
                                  ),
                                  child: Text(
                                    m.toString(),
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 24),

                      // Top Holdings
                      Text(
                        "Top Portfolio Holdings",
                        style: GoogleFonts.inter(
                          color: Colors.grey.shade300,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._buildHoldingsList(_factsheet!['top_holdings']),
                      const SizedBox(height: 24),

                      // Document Links
                      Row(
                        children: [
                          if (_factsheet!['factsheet_url'] != null &&
                              _factsheet!['factsheet_url'].toString().isNotEmpty)
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _openUrl(_factsheet!['factsheet_url']),
                                icon: const Icon(Icons.download_rounded, size: 18),
                                label: const Text("Factsheet PDF"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE94057),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 12),
                          if (_factsheet!['portfolio_holdings_url'] != null &&
                              _factsheet!['portfolio_holdings_url']
                                  .toString()
                                  .isNotEmpty)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _openUrl(_factsheet!['portfolio_holdings_url']),
                                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                label: const Text("All Holdings"),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white30),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _buildHoldingsList(dynamic holdingsData) {
    if (holdingsData == null || holdingsData is! List) {
      return [
        Text(
          "No top holdings detailed.",
          style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 12),
        )
      ];
    }

    return holdingsData.map<Widget>((h) {
      final company = h['company']?.toString() ?? 'Unknown';
      final weightVal = double.tryParse(h['weight']?.toString() ?? '0') ?? 0.0;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  company,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                ),
                Text(
                  "${weightVal.toStringAsFixed(2)}%",
                  style: GoogleFonts.inter(
                    color: const Color(0xFFF27121),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: weightVal / 100.0,
                backgroundColor: Colors.white.withOpacity(0.05),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF8A2387),
                ),
                minHeight: 6,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
