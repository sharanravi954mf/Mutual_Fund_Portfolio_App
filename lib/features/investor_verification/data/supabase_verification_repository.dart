import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/verification_models.dart';
import 'verification_repository.dart';

class SupabaseVerificationRepository implements VerificationRepository {
  SupabaseVerificationRepository(this._client);

  factory SupabaseVerificationRepository.fromDefaultClient() =>
      SupabaseVerificationRepository(Supabase.instance.client);

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
  Future<List<VerificationRequest>> reviewQueue(
      [VerificationQueueFilter filter =
          const VerificationQueueFilter()]) async {
    return _requests(
      await _client.rpc('list_verification_review_queue_filtered', params: {
        'p_request_id_query': filter.requestIdQuery,
        'p_status': filter.status?.databaseValue,
        'p_method_code': filter.method?.databaseValue,
      }),
    );
  }

  @override
  Future<AdvisorVerificationReview> getReview(String requestId) async {
    final results = await Future.wait([
      _client.rpc('get_verification_review', params: {
        'p_request_id': requestId,
      }),
      _client.rpc('get_verification_events', params: {
        'p_request_id': requestId,
      }),
    ]);
    return AdvisorVerificationReview.fromJson(
      _singleRow(results[0]),
      _rows(results[1]).map(VerificationEvent.fromJson).toList(),
    );
  }

  @override
  Future<List<AdvisorVerificationCandidate>> searchCandidates(
      String requestId, String query) async {
    final rows = await _client.rpc('search_verification_candidates', params: {
      'p_request_id': requestId,
      'p_query': query,
    });
    return _rows(rows).map(AdvisorVerificationCandidate.fromJson).toList();
  }

  @override
  Future<void> approveCandidate(
    String requestId,
    String candidateToken,
    int expectedVersion, {
    String? reasonCode,
  }) =>
      _client.rpc('approve_verification_candidate', params: {
        'p_request_id': requestId,
        'p_candidate_token': candidateToken,
        'p_expected_version': expectedVersion,
        'p_reason_code': reasonCode,
      });

  @override
  Future<void> requestMoreInformation(
    String requestId,
    int expectedVersion, {
    required String reasonCode,
  }) =>
      _client.rpc('request_more_verification_information', params: {
        'p_request_id': requestId,
        'p_expected_version': expectedVersion,
        'p_reason_code': reasonCode,
      });

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

  Map<String, dynamic> _singleRow(dynamic value) {
    final rows = _rows(value);
    if (rows.length != 1) {
      throw StateError('Verification service returned an invalid review.');
    }
    return rows.single;
  }
}
