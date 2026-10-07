import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fund_search_service.dart';

class NseFundSearchScreen extends StatefulWidget {
  const NseFundSearchScreen({super.key});

  @override
  State<NseFundSearchScreen> createState() => _NseFundSearchScreenState();
}

class _NseFundSearchScreenState extends State<NseFundSearchScreen> {
  final TextEditingController _query = TextEditingController();
  late final FundSearchService _service = FundSearchService(
    Supabase.instance.client,
  );

  bool _busy = false;
  String? _message;
  List<Map<String, dynamic>> _rows = const [];
  Map<String, dynamic>? _selected;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2 || _busy) return;

    setState(() {
      _busy = true;
      _message = null;
      _selected = null;
    });

    try {
      final results = await _service.search(query);
      final rows = results
          .map(
            (item) => Map<String, dynamic>.from(
              (item as Map<String, dynamic>)['nse'] as Map,
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _message = rows.isEmpty ? 'No NSE schemes matched this search.' : null;
      });
    } on FundSearchUnavailableException {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _message =
            'The NSE scheme catalogue is not available yet. Try again after the next master refresh.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _message = 'Unable to search the NSE scheme catalogue.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _sourceRow(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(text.isEmpty ? '—' : text)),
        ],
      ),
    );
  }

  Widget _details(Map<String, dynamic> row) {
    return Card(
      margin: const EdgeInsets.only(top: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row['scheme_name']?.toString() ?? 'NSE scheme',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Source: NSE Invest SCH master',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 28),
            _sourceRow('Scheme Code', row['scheme_code']),
            _sourceRow('AMC Code', row['amc_code']),
            _sourceRow('RTA Agent Code', row['rta_agent_code']),
            _sourceRow('RTA Scheme Code', row['rta_scheme_code']),
            _sourceRow('AMC Scheme Code', row['amc_scheme_code']),
            _sourceRow('ISIN', row['isin']),
            _sourceRow('Scheme Type', row['scheme_type']),
            _sourceRow('Plan Type', row['plan_type']),
            _sourceRow('AMC Active Flag', row['amc_active_flag']),
            const SizedBox(height: 12),
            const Text(
              'These are NSE source fields. They are not treated as eKYC RTA-AMC codes unless NSE evidence establishes that mapping.',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fund Search')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'NSE scheme catalogue',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Search the validated NSE Invest SCH master by scheme name, code, AMC, RTA or ISIN.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _query,
                enabled: !_busy,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  labelText: 'Search funds',
                  hintText: 'For example: Bandhan',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    onPressed: _busy ? null : _search,
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!),
              ],
              if (_rows.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  '${_rows.length} matching schemes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final row in _rows)
                  Card(
                    child: ListTile(
                      title: Text(row['scheme_name']?.toString() ?? ''),
                      subtitle: Text(
                        'Scheme Code: ${row['scheme_code'] ?? '—'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() => _selected = row),
                    ),
                  ),
              ],
              if (_selected != null) _details(_selected!),
            ],
          ),
        ),
      ),
    );
  }
}
