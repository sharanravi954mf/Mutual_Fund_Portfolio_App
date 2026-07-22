import '../models/verification_models.dart';

abstract class VerificationRepository {
  Future<List<VerificationRequest>> getStatus();
  Future<List<VerificationEvent>> getHistory(String requestId);
  Future<VerificationRequest> createRequest(VerificationMethod method);
  Future<void> cancelRequest(String requestId, int expectedVersion);
  Future<List<VerificationRequest>> reviewQueue(
      [VerificationQueueFilter filter = const VerificationQueueFilter()]);
  Future<AdvisorVerificationReview> getReview(String requestId);
  Future<List<AdvisorVerificationCandidate>> searchCandidates(
      String requestId, String query);
  Future<void> approveCandidate(
    String requestId,
    String candidateToken,
    int expectedVersion, {
    String? reasonCode,
  });
  Future<void> requestMoreInformation(
    String requestId,
    int expectedVersion, {
    required String reasonCode,
  });

  /// Deprecated for Flutter callers. Sprint 5 uses [approveCandidate] so a
  /// business profile UUID is never exposed to the Advisor interface.
  Future<void> approve(String requestId, String profileId, int expectedVersion,
      {String? reasonCode});
  Future<void> reject(String requestId, int expectedVersion,
      {String? reasonCode});
}

class VerificationPermissionDenied implements Exception {
  const VerificationPermissionDenied();
}
