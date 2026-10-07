import 'package:supabase_flutter/supabase_flutter.dart';

class FundSearchService {
  FundSearchService(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> _searchEnvelope(
    String query, {
    int limit = 25,
  }) async {
    final raw = await _client.rpc(
      'search_nse_schemes',
      params: {'p_query': query.trim(), 'p_limit': limit},
    );

    final envelope = Map<String, dynamic>.from(raw as Map);
    if (envelope['available'] != true) {
      throw const FundSearchUnavailableException();
    }
    return envelope;
  }

  Future<List<dynamic>> search(String query) async {
    try {
      final envelope = await _searchEnvelope(query);
      final items = List<Map<String, dynamic>>.from(
        (envelope['items'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      return items
          .map(
            (row) => <String, dynamic>{
              'schemeCode': row['scheme_code']?.toString() ?? '',
              'schemeName': row['scheme_name']?.toString() ?? '',
              'nse': row,
            },
          )
          .toList(growable: false);
    } on FundSearchUnavailableException {
      rethrow;
    } catch (_) {
      throw const FundSearchException();
    }
  }

  Future<Map<String, dynamic>> loadDetails(String schemeCode) async {
    try {
      final envelope = await _searchEnvelope(schemeCode, limit: 50);
      final rows = List<Map<String, dynamic>>.from(
        (envelope['items'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      final normalized = schemeCode.trim().toUpperCase();
      final row = rows.cast<Map<String, dynamic>?>().firstWhere(
        (item) =>
            (item?['scheme_code']?.toString().toUpperCase() ?? '') ==
            normalized,
        orElse: () => null,
      );
      if (row == null) throw const FundSearchException();

      return {
        'meta': {
          'fund_house': row['amc_code'] ?? 'N/A',
          'scheme_name': row['scheme_name'] ?? 'N/A',
          'scheme_code': row['scheme_code'] ?? 'N/A',
          'scheme_type': row['scheme_type'] ?? 'N/A',
          'scheme_category': row['plan_type'] ?? 'N/A',
          'isin_div_payout': row['isin'] ?? 'N/A',
        },
        // NAV is intentionally not fabricated. NSE NAV publication remains a
        // separate, uncommissioned source/crosswalk decision.
        'data': <dynamic>[],
        'nse_source': row,
        'source': envelope['source'],
        'snapshot_version': envelope['snapshot_version'],
        'snapshot_created_at': envelope['snapshot_created_at'],
      };
    } on FundSearchUnavailableException {
      rethrow;
    } catch (_) {
      throw const FundSearchException();
    }
  }
}

class FundSearchException implements Exception {
  const FundSearchException();
}

class FundSearchUnavailableException implements Exception {
  const FundSearchUnavailableException();
}
