import '../models/folio_verification_models.dart';

abstract class InvestorFolioVerificationRepository {
  Future<FolioSubmissionToken> acquireSubmissionToken(
      String registrar, String folioNumber);
  Future<FolioVerificationRequest> submit(FolioSubmissionToken token,
      FolioHolderRelationship relationship, String correlationId);
  Future<FolioVerificationRequest> resubmit(
      String requestId, int expectedVersion, String correlationId);
  Future<FolioVerificationRequest> cancel(
      String requestId, int expectedVersion, String correlationId);
  Future<FolioVerificationPage<FolioVerificationRequest>> getMyRequests(
      {int page = 0, int pageSize = 25});
  Future<FolioVerificationPage<InvestorFolioRequestListRecord>>
      getMyFolioRequestList({int page = 0, int pageSize = 25});
  Future<FolioVerificationRequest> getRequestDetail(String requestId);
  Future<FolioVerificationPage<FolioVerificationEvent>> getHistory(
      String requestId,
      {int page = 0,
      int pageSize = 25});
}

abstract class AdvisorFolioVerificationRepository {
  Future<FolioVerificationPage<AdvisorFolioVerificationQueueItem>>
      getAssignedFolioQueue(FolioQueueFilter filter);
  Future<AdvisorFolioVerificationDetail> getAssignedFolioRequestDetail(
      String requestId);
  Future<FolioVerificationRequest> beginReview(
      String requestId, int expectedVersion, String correlationId);
  Future<FolioVerificationRequest> requestMoreInformation(String requestId,
      int expectedVersion, String reasonCode, String correlationId);
  Future<FolioVerificationRequest> approve(String requestId,
      int expectedVersion, String reasonCode, String correlationId);
  Future<FolioVerificationRequest> reject(String requestId, int expectedVersion,
      String reasonCode, String correlationId);
  Future<void> revokeGrant(String grantId, int expectedVersion,
      String reasonCode, String correlationId);
  Future<FolioVerificationPage<FolioVerificationRequest>> getAdvisorQueue(
      FolioQueueFilter filter);
  Future<FolioGrantSummary?> getGrantSummary(String requestId);
}
