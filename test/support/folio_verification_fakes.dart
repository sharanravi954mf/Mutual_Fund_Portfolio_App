import 'dart:async';

import 'package:mutual_fund_portfolio_app/features/investor_verification/data/folio_verification_repository.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/folio_verification_models.dart';

class FolioTestRepository
    implements
        InvestorFolioVerificationRepository,
        AdvisorFolioVerificationRepository {
  Object? error;
  int submitCalls = 0, refreshCalls = 0, cancelCalls = 0, resubmitCalls = 0;
  String? correlation;
  Completer<FolioVerificationRequest>? pendingSubmit;
  List<InvestorFolioRequestListRecord> safeRows = const [
    InvestorFolioRequestListRecord(
      requestId: 'request',
      version: 1,
      registrarDisplay: 'CAMS',
      maskedFolio: '••••1234',
      status: FolioVerificationStatus.pendingAdvisorReview,
    ),
  ];
  final request = const FolioVerificationRequest(
      id: 'request',
      status: FolioVerificationStatus.pendingAdvisorReview,
      version: 1);
  Future<T> run<T>(T value, [String? id]) async {
    correlation = id ?? correlation;
    if (error != null) throw error!;
    return value;
  }

  @override
  Future<FolioSubmissionToken> acquireSubmissionToken(
          String registrar, String folioNumber) =>
      run(const FolioSubmissionToken('opaque'));
  @override
  Future<FolioVerificationPage<InvestorFolioRequestListRecord>>
      getMyFolioRequestList({int page = 0, int pageSize = 25}) {
    refreshCalls++;
    return run(FolioVerificationPage(
      items: safeRows,
      page: page,
      pageSize: pageSize,
    ));
  }

  @override
  Future<FolioVerificationRequest> submit(
      FolioSubmissionToken t, FolioHolderRelationship r, String id) {
    submitCalls++;
    final pending = pendingSubmit;
    if (pending != null) return pending.future;
    return run(request, id);
  }

  @override
  Future<FolioVerificationRequest> cancel(String id, int v, String c) {
    cancelCalls++;
    return run(request, c);
  }

  @override
  Future<FolioVerificationRequest> resubmit(String id, int v, String c) {
    resubmitCalls++;
    return run(request, c);
  }

  @override
  Future<FolioVerificationPage<FolioVerificationRequest>> getMyRequests(
      {int page = 0, int pageSize = 25}) {
    refreshCalls++;
    return run(FolioVerificationPage(
        items: [request], page: page, pageSize: pageSize));
  }

  @override
  Future<FolioVerificationRequest> getRequestDetail(String id) => run(request);
  @override
  Future<FolioVerificationPage<FolioVerificationEvent>> getHistory(String id,
          {int page = 0, int pageSize = 25}) =>
      run(FolioVerificationPage(
          items: const [], page: page, pageSize: pageSize));
  @override
  Future<FolioVerificationRequest> beginReview(String id, int v, String c) =>
      run(request, c);
  @override
  Future<FolioVerificationRequest> requestMoreInformation(
          String id, int v, String r, String c) =>
      run(request, c);
  @override
  Future<FolioVerificationRequest> approve(
          String id, int v, String r, String c) =>
      run(request, c);
  @override
  Future<FolioVerificationRequest> reject(
          String id, int v, String r, String c) =>
      run(request, c);
  @override
  Future<void> revokeGrant(String id, int v, String r, String c) =>
      run(null, c);
  @override
  Future<FolioVerificationPage<FolioVerificationRequest>> getAdvisorQueue(
          FolioQueueFilter f) =>
      run(FolioVerificationPage(
          items: const [], page: f.page, pageSize: f.pageSize));
  @override
  Future<FolioVerificationPage<AdvisorFolioVerificationQueueItem>>
      getAssignedFolioQueue(FolioQueueFilter filter) => run(
            FolioVerificationPage(
              items: const [],
              page: filter.page,
              pageSize: filter.pageSize,
            ),
          );
  @override
  Future<AdvisorFolioVerificationDetail> getAssignedFolioRequestDetail(
          String requestId) =>
      run(const AdvisorFolioVerificationDetail(
        requestId: 'request',
        version: 1,
        investorDisplayLabel: 'Investor request',
        registrarDisplay: 'CAMS',
        maskedFolio: '••••1234',
        holderRelationship: FolioHolderRelationship.soleHolder,
        status: FolioVerificationStatus.pendingAdvisorReview,
        history: [],
      ));
  @override
  Future<FolioGrantSummary?> getGrantSummary(String id) => run(null);
}
