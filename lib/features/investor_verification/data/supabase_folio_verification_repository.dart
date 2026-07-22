import 'dart:async';
import 'folio_verification_datasource.dart';
import 'folio_verification_dtos.dart';
import 'folio_verification_repository.dart';
import '../models/folio_verification_models.dart';

class SupabaseFolioVerificationRepository
    implements
        InvestorFolioVerificationRepository,
        AdvisorFolioVerificationRepository {
  SupabaseFolioVerificationRepository(this._datasource,
      {Duration timeout = const Duration(seconds: 15)})
      : _timeout = timeout;
  final FolioVerificationDatasource _datasource;
  final Duration _timeout;
  @override
  Future<FolioSubmissionToken> acquireSubmissionToken(
      String registrar, String folioNumber) async {
    final rows = await _rows('issue_folio_submission_token',
        {'p_registrar': registrar, 'p_folio_number': folioNumber});
    if (rows.length != 1) {
      throw const FolioVerificationFailure(
          FolioVerificationFailureCode.unexpected);
    }
    return FolioSubmissionToken(rows.single['submission_token'] as String);
  }

  @override
  Future<FolioVerificationRequest> submit(FolioSubmissionToken token,
          FolioHolderRelationship relationship, String correlationId) =>
      _request('submit_folio_verification', {
        'p_folio_token': token.value,
        'p_relationship': relationship.databaseValue,
        'p_idempotency_key': correlationId
      });
  @override
  Future<FolioVerificationRequest> resubmit(
          String id, int version, String correlationId) =>
      _request('resubmit_folio_verification',
          {'p_request_id': id, 'p_expected_version': version});
  @override
  Future<FolioVerificationRequest> cancel(
          String id, int version, String correlationId) =>
      _request('cancel_folio_verification',
          {'p_request_id': id, 'p_expected_version': version});
  @override
  Future<FolioVerificationRequest> beginReview(
          String id, int version, String correlationId) =>
      _request('begin_folio_review',
          {'p_request_id': id, 'p_expected_version': version});
  @override
  Future<FolioVerificationRequest> requestMoreInformation(
          String id, int version, String reason, String correlationId) =>
      _request('request_folio_more_information', {
        'p_request_id': id,
        'p_expected_version': version,
        'p_reason': reason
      });
  @override
  Future<FolioVerificationRequest> approve(
          String id, int version, String reason, String correlationId) =>
      _request('approve_folio_verification', {
        'p_request_id': id,
        'p_expected_version': version,
        'p_reason': reason
      });
  @override
  Future<FolioVerificationRequest> reject(
          String id, int version, String reason, String correlationId) =>
      _request('reject_folio_verification', {
        'p_request_id': id,
        'p_expected_version': version,
        'p_reason': reason
      });
  @override
  Future<void> revokeGrant(
          String id, int version, String reason, String correlationId) =>
      _call('revoke_folio_grant', {
        'p_grant_id': id,
        'p_expected_version': version,
        'p_reason': reason
      });
  @override
  Future<FolioVerificationPage<FolioVerificationRequest>> getMyRequests(
      {int page = 0, int pageSize = 25}) async {
    final rows = await _rows('get_verification_status');
    return _page(
        rows
            .where((row) => row['method_code'] == 'folio')
            .map((row) => FolioVerificationRequestDto(row).toDomain())
            .toList(),
        page,
        pageSize);
  }

  @override
  Future<FolioVerificationPage<InvestorFolioRequestListRecord>>
      getMyFolioRequestList({int page = 0, int pageSize = 25}) async {
    // The safe RPC owns pagination. Applying _page here would discard every
    // non-zero page a second time.
    final items = (await _rows('get_my_folio_requests', {
      'p_page': page,
      'p_page_size': pageSize,
    }))
        .map((row) => InvestorFolioRequestListRecordDto(row).toDomain())
        .toList();

    return FolioVerificationPage(
      items: items,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<FolioVerificationRequest> getRequestDetail(String id) async {
    final page = await getMyRequests(pageSize: 1000);
    return page.items.firstWhere((request) => request.id == id,
        orElse: () => throw const FolioVerificationFailure(
            FolioVerificationFailureCode.requestUnavailable));
  }

  @override
  Future<FolioVerificationPage<FolioVerificationEvent>> getHistory(String id,
          {int page = 0, int pageSize = 25}) async =>
      _page(
          (await _rows('get_verification_events', {'p_request_id': id}))
              .map((row) => FolioVerificationEventDto(row).toDomain())
              .toList(),
          page,
          pageSize);
  @override
  Future<FolioVerificationPage<FolioVerificationRequest>> getAdvisorQueue(
      FolioQueueFilter filter) async {
    final rows = await _rows('list_verification_review_queue_filtered',
        {'p_status': filter.status?.name});
    return _page(
        rows
            .where((row) => row['method_code'] == 'folio')
            .map((row) => FolioVerificationRequestDto(row).toDomain())
            .toList(),
        filter.page,
        filter.pageSize);
  }

  @override
  Future<FolioGrantSummary?> getGrantSummary(String requestId) =>
      throw UnsupportedError('Phase 1 has no safe grant-summary RPC.');
  Future<FolioVerificationRequest> _request(
      String rpc, Map<String, dynamic> params) async {
    final rows = await _rows(rpc, params);
    if (rows.length != 1) {
      throw const FolioVerificationFailure(
          FolioVerificationFailureCode.unexpected);
    }
    return FolioVerificationRequestDto(rows.single).toDomain();
  }

  Future<void> _call(String rpc, Map<String, dynamic> params) async {
    await _guard(_datasource.rpc(rpc, params: params));
  }

  Future<List<Map<String, dynamic>>> _rows(String rpc,
      [Map<String, dynamic>? params]) async {
    final value = await _guard(_datasource.rpc(rpc, params: params));
    if (value is! List) {
      throw const FolioVerificationFailure(
          FolioVerificationFailureCode.unexpected);
    }
    return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<T> _guard<T>(Future<T> call) async {
    try {
      return await call.timeout(_timeout);
    } on TimeoutException {
      throw const FolioVerificationFailure(
          FolioVerificationFailureCode.timeout);
    } catch (error) {
      if (error is FolioVerificationFailure) {
        rethrow;
      }
      throw FolioVerificationFailure(_errorCode(error.toString()));
    }
  }

  FolioVerificationFailureCode _errorCode(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('authorization') || lower.contains('permission')) {
      return FolioVerificationFailureCode.permissionDenied;
    }
    if (lower.contains('changed') || lower.contains('stale')) {
      return FolioVerificationFailureCode.staleVersion;
    }
    if (lower.contains('token') || lower.contains('unavailable')) {
      return FolioVerificationFailureCode.tokenInvalidOrExpired;
    }
    if (lower.contains('duplicate')) {
      return FolioVerificationFailureCode.duplicateRequest;
    }
    if (lower.contains('transition')) {
      return FolioVerificationFailureCode.invalidTransition;
    }
    return FolioVerificationFailureCode.temporaryFailure;
  }

  FolioVerificationPage<T> _page<T>(List<T> values, int page, int size) {
    final start = page * size;
    return FolioVerificationPage(
        items: start >= values.length
            ? const []
            : values.skip(start).take(size).toList(),
        page: page,
        pageSize: size);
  }
}
