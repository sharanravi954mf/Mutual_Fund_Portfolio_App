import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedTab = 0;
  String _searchQuery = "";
  bool _isIngesting = false;
  bool _isLoading = true;
  
  final TextEditingController _searchController = TextEditingController();
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

  List<Map<String, dynamic>> _allClients = [];
  List<Map<String, dynamic>> _filteredClients = [];

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

  @override
  void dispose() {
    _searchController.dispose();
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
                  _selectedTab == 0 ? "Clients Directory" : "Data Ingestion Engine",
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
                      onTap: (index) {
                        setState(() {
                          _selectedTab = index;
                        });
                      },
                      items: const [
                        BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: "Clients"),
                        BottomNavigationBarItem(icon: Icon(Icons.cloud_upload_outlined), label: "Ingest"),
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
        ],
      ),
    );
  }
}
