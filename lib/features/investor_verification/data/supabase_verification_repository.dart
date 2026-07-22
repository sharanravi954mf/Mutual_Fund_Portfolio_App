import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/verification_models.dart';
import 'verification_repository.dart';

class SupabaseVerificationRepository implements VerificationRepository {
  SupabaseVerificationRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<VerificationRequest>> getStatus() async => _requests(
        await _client.rpc('get_verification_status'),
      );

  @override
  Future<List<VerificationEvent>> getHistory(String requestId) async {
    final rows = await _client.rpc('get_verification_events', params: {
      'p_request_id': requestId,
    });
    return _rows(rows).map(VerificationEvent.fromJson).toList();
  }

  @override
  Future<VerificationRequest> createRequest(VerificationMethod method) async {
    await _client.rpc('create_verification_request', params: {
      'p_method_code': method.databaseValue,
    });
    return (await getStatus()).first;
  }

  @override
  Future<void> cancelRequest(String requestId, int expectedVersion) =>
      _client.rpc(
        'cancel_verification_request',
        params: {
          'p_request_id': requestId,
          'p_expected_version': expectedVersion
        },
      );

  @override
  Future<List<VerificationRequest>> reviewQueue() async => _requests(
        await _client.rpc('list_verification_review_queue'),
      );

  @override
  Future<void> approve(String requestId, String profileId, int expectedVersion,
          {String? reasonCode}) =>
      _client.rpc('approve_verification_request', params: {
        'p_request_id': requestId,
        'p_profile_id': profileId,
        'p_expected_version': expectedVersion,
        'p_reason_code': reasonCode,
      });

  @override
  Future<void> reject(String requestId, int expectedVersion,
          {String? reasonCode}) =>
      _client.rpc(
        'reject_verification_request',
        params: {
          'p_request_id': requestId,
          'p_expected_version': expectedVersion,
          'p_reason_code': reasonCode
        },
      );

  List<VerificationRequest> _requests(dynamic value) =>
      _rows(value).map(VerificationRequest.fromJson).toList();

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) {
      throw StateError('Verification service returned invalid data.');
    }
    return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }
}
