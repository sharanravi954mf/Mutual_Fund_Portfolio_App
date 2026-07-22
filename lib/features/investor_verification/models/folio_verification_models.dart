enum FolioVerificationStatus {
  pendingAdvisorReview,
  underReview,
  moreInformationRequired,
  approved,
  rejected,
  cancelled,
  expired,
  superseded,
  revoked;

  static FolioVerificationStatus fromDatabase(String value) => switch (value) {
        'pending_advisor_review' => pendingAdvisorReview,
        'under_review' => underReview,
        'more_information_required' => moreInformationRequired,
        'approved' => approved,
        'rejected' => rejected,
        'cancelled' => cancelled,
        'expired' => expired,
        'superseded' => superseded,
        'revoked' => revoked,
        _ => throw ArgumentError.value(value, 'value'),
      };
}

enum FolioHolderRelationship {
  soleHolder,
  jointHolder,
  guardianForMinor;

  String get databaseValue => switch (this) {
        soleHolder => 'SOLE_HOLDER',
        jointHolder => 'JOINT_HOLDER',
        guardianForMinor => 'GUARDIAN_FOR_MINOR'
      };
}

class FolioSubmissionToken {
  const FolioSubmissionToken(this.value);
  final String value;
}

class FolioVerificationRequest {
  const FolioVerificationRequest(
      {required this.id,
      required this.status,
      required this.version,
      this.submittedAt,
      this.resolvedAt,
      this.expiresAt,
      this.retryOfRequestId});
  final String id;
  final FolioVerificationStatus status;
  final int version;
  final DateTime? submittedAt, resolvedAt, expiresAt;
  final String? retryOfRequestId;
}

class FolioVerificationEvent {
  const FolioVerificationEvent(
      {required this.id,
      required this.type,
      required this.occurredAt,
      this.reasonCode});
  final String id, type;
  final DateTime occurredAt;
  final String? reasonCode;
}

class FolioGrantSummary {
  const FolioGrantSummary(
      {required this.id,
      required this.status,
      required this.holderRelationship,
      this.approvedAt,
      this.revokedAt});
  final String id, status;
  final FolioHolderRelationship holderRelationship;
  final DateTime? approvedAt, revokedAt;
}

class FolioQueueFilter {
  const FolioQueueFilter({this.page = 0, this.pageSize = 25, this.status});
  final int page, pageSize;
  final FolioVerificationStatus? status;
}

class FolioVerificationPage<T> {
  const FolioVerificationPage(
      {required this.items, required this.page, required this.pageSize});
  final List<T> items;
  final int page, pageSize;
}

class InvestorFolioRequestListRecord {
  const InvestorFolioRequestListRecord(
      {required this.requestId,
      required this.version,
      required this.registrarDisplay,
      required this.maskedFolio,
      required this.status,
      this.submittedAt});
  final String requestId, registrarDisplay, maskedFolio;
  final int version;
  final FolioVerificationStatus status;
  final DateTime? submittedAt;
}

enum FolioVerificationFailureCode {
  unauthenticated,
  permissionDenied,
  requestUnavailable,
  invalidTransition,
  staleVersion,
  duplicateRequest,
  duplicateGrant,
  tokenInvalidOrExpired,
  evidenceChanged,
  unsupportedRelationship,
  validationFailed,
  timeout,
  temporaryFailure,
  unexpected
}

class FolioVerificationFailure implements Exception {
  const FolioVerificationFailure(this.code);
  final FolioVerificationFailureCode code;
}
