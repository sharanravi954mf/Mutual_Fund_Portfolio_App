import '../models/verification_models.dart';

abstract class VerificationRepository {
  Future<List<VerificationRequest>> getStatus();
  Future<List<VerificationEvent>> getHistory(String requestId);
  Future<VerificationRequest> createRequest(VerificationMethod method);
  Future<void> cancelRequest(String requestId, int expectedVersion);
  Future<List<VerificationRequest>> reviewQueue();
  Future<void> approve(String requestId, String profileId, int expectedVersion,
      {String? reasonCode});
  Future<void> reject(String requestId, int expectedVersion,
      {String? reasonCode});
}

class VerificationPermissionDenied implements Exception {
  const VerificationPermissionDenied();
}
