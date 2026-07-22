import 'dart:async';
import 'folio_verification_datasource.dart';
import 'advisor_folio_verification_dtos.dart';
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
  Future<FolioVerificationPage<AdvisorFolioVerificationQueueItem>>
      getAssignedFolioQueue(FolioQueueFilter filter) async {
    final items = (await _rows('get_my_advisor_folio_requests', {
      'p_page': filter.page,
      'p_page_size': filter.pageSize,
      'p_status': filter.status?.databaseValue,
    }))
        .map((row) => AdvisorFolioVerificationQueueItemDto(row).toDomain())
        .toList();
    return FolioVerificationPage(
      items: items,
      page: filter.page,
      pageSize: filter.pageSize,
    );
  }

  @override
  Future<AdvisorFolioVerificationDetail> getAssignedFolioRequestDetail(
      String requestId) async {
    final rows = await _rows('get_my_advisor_folio_request_detail', {
      'p_request_id': requestId,
    });
    if (rows.length != 1) {
      throw const FolioVerificationFailure(
          FolioVerificationFailureCode.requestUnavailable);
    }
    return AdvisorFolioVerificationDetailDto(rows.single).toDomain();
  }

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
    final safePage =
        await getMyFolioRequestList(page: page, pageSize: pageSize);
    return FolioVerificationPage(
      items: safePage.items
          .map((item) => FolioVerificationRequest(
                id: item.requestId,
                status: item.status,
                version: item.version,
                submittedAt: item.submittedAt,
              ))
          .toList(),
      page: safePage.page,
      pageSize: safePage.pageSize,
    );
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
    final rows = await _rows('get_folio_request_detail', {'p_request_id': id});
    if (rows.length != 1) {
      throw const FolioVerificationFailure(
          FolioVerificationFailureCode.requestUnavailable);
    }
    final row = rows.single;
    return FolioVerificationRequest(
      id: id,
      status: FolioVerificationStatus.fromDatabase(row['status'] as String),
      version: row['version'] as int,
      submittedAt: _date(row['submitted_at']),
      resolvedAt: _date(row['resolved_at']),
      expiresAt: _date(row['expires_at']),
    );
  }

  @override
  Future<FolioVerificationPage<FolioVerificationEvent>> getHistory(String id,
          {int page = 0, int pageSize = 25}) async =>
      _page(
          (await _rows('get_folio_verification_events', {'p_request_id': id}))
              .map((row) => FolioVerificationEventDto(row).toDomain())
              .toList(),
          page,
          pageSize);
  @override
  Future<FolioVerificationPage<FolioVerificationRequest>> getAdvisorQueue(
      FolioQueueFilter filter) async {
    final safePage = await getAssignedFolioQueue(filter);
    return FolioVerificationPage(
      items: safePage.items
          .map((item) => FolioVerificationRequest(
                id: item.requestId,
                status: item.status,
                version: item.version,
                submittedAt: item.submittedAt,
              ))
          .toList(),
      page: safePage.page,
      pageSize: safePage.pageSize,
    );
  }

  @override
  Future<FolioGrantSummary?> getGrantSummary(String requestId) async {
    final rows =
        await _rows('get_folio_grant_summary', {'p_request_id': requestId});
    if (rows.isEmpty) return null;
    if (rows.length != 1) {
      throw const FolioVerificationFailure(
          FolioVerificationFailureCode.unexpected);
    }
    final row = rows.single;
    return FolioGrantSummary(
      id: requestId,
      status: row['grant_status'] as String,
      holderRelationship: FolioHolderRelationship.values.firstWhere(
          (relationship) =>
              relationship.databaseValue == row['holder_relationship']),
      approvedAt: _date(row['approved_at']),
      revokedAt: _date(row['revoked_at']),
    );
  }

  DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value as String);
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
