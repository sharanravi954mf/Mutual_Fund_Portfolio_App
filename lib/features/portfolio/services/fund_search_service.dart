import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class FundSearchService {
  FundSearchService(this._client);

  final SupabaseClient _client;

  Future<List<dynamic>> search(String query) async {
    final response = await _client.functions.invoke(
      'sign-stamp-invoice',
      body: {
        'action': 'proxy-get',
        'url': 'https://api.mfapi.in/mf/search?q=${Uri.encodeComponent(query)}',
      },
    ).timeout(const Duration(seconds: 15));
    if (response.status != 200 || response.data == null) {
      throw const FundSearchException();
    }
    return response.data is String
        ? jsonDecode(response.data as String) as List<dynamic>
        : List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> loadDetails(String schemeCode) async {
    final response = await _client.functions.invoke(
      'sign-stamp-invoice',
      body: {
        'action': 'proxy-get',
        'url': 'https://api.mfapi.in/mf/$schemeCode',
      },
    ).timeout(const Duration(seconds: 20));
    if (response.status != 200 || response.data == null) {
      throw const FundSearchException();
    }
    return response.data is String
        ? Map<String, dynamic>.from(jsonDecode(response.data as String) as Map)
        : Map<String, dynamic>.from(response.data as Map);
  }
}

class FundSearchException implements Exception {
  const FundSearchException();
}
