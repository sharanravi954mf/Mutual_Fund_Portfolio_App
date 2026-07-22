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

  String get databaseValue => switch (this) {
        pendingAdvisorReview => 'pending_advisor_review',
        underReview => 'under_review',
        moreInformationRequired => 'more_information_required',
        approved => 'approved',
        rejected => 'rejected',
        cancelled => 'cancelled',
        expired => 'expired',
        superseded => 'superseded',
        revoked => 'revoked',
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

/// Server-approved reason codes for Advisor folio decisions. The UI and
/// application service must use these values rather than forwarding arbitrary
/// strings into the dedicated folio lifecycle.
enum FolioReviewReasonCode {
  verifiedSoleHolder,
  verifiedJointHolder,
  verifiedGuardian,
  verifiedAuthorizedRelationship,
  invalidFolio,
  nameMismatch,
  panMismatch,
  insufficientDocuments,
  holderRelationshipNotProven,
  duplicateRequest,
  otherRejection,
  folioDocumentRequired,
  jointHolderProofRequired,
  guardianProofRequired,
  identityClarificationRequired,
  additionalInformationRequired;

  String get databaseValue => switch (this) {
        verifiedSoleHolder => 'VERIFIED_SOLE_HOLDER',
        verifiedJointHolder => 'VERIFIED_JOINT_HOLDER',
        verifiedGuardian => 'VERIFIED_GUARDIAN',
        verifiedAuthorizedRelationship => 'VERIFIED_AUTHORIZED_RELATIONSHIP',
        invalidFolio => 'INVALID_FOLIO',
        nameMismatch => 'NAME_MISMATCH',
        panMismatch => 'PAN_MISMATCH',
        insufficientDocuments => 'INSUFFICIENT_DOCUMENTS',
        holderRelationshipNotProven => 'HOLDER_RELATIONSHIP_NOT_PROVEN',
        duplicateRequest => 'DUPLICATE_REQUEST',
        otherRejection => 'OTHER_REJECTION',
        folioDocumentRequired => 'FOLIO_DOCUMENT_REQUIRED',
        jointHolderProofRequired => 'JOINT_HOLDER_PROOF_REQUIRED',
        guardianProofRequired => 'GUARDIAN_PROOF_REQUIRED',
        identityClarificationRequired => 'IDENTITY_CLARIFICATION_REQUIRED',
        additionalInformationRequired => 'ADDITIONAL_INFORMATION_REQUIRED',
      };

  static FolioReviewReasonCode fromDatabase(String value) =>
      FolioReviewReasonCode.values.firstWhere(
        (reason) => reason.databaseValue == value,
        orElse: () => throw ArgumentError.value(value, 'value'),
      );
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

/// Safe Advisor queue projection. [requestId] and [version] exist solely for
/// secured controller commands and must never be rendered as identifiers.
class AdvisorFolioVerificationQueueItem {
  const AdvisorFolioVerificationQueueItem({
    required this.requestId,
    required this.version,
    required this.investorDisplayLabel,
    required this.registrarDisplay,
    required this.maskedFolio,
    required this.holderRelationship,
    required this.status,
    this.submittedAt,
    this.updatedAt,
  });

  final String requestId;
  final int version;
  final String investorDisplayLabel;
  final String registrarDisplay;
  final String maskedFolio;
  final FolioHolderRelationship holderRelationship;
  final FolioVerificationStatus status;
  final DateTime? submittedAt;
  final DateTime? updatedAt;
}

class AdvisorFolioVerificationHistoryEvent {
  const AdvisorFolioVerificationHistoryEvent({
    required this.type,
    required this.createdAt,
    this.previousStatus,
    this.newStatus,
    this.reasonCode,
  });

  final String type;
  final DateTime createdAt;
  final FolioVerificationStatus? previousStatus;
  final FolioVerificationStatus? newStatus;
  final String? reasonCode;
}

class AdvisorFolioVerificationDetail {
  const AdvisorFolioVerificationDetail({
    required this.requestId,
    required this.version,
    required this.investorDisplayLabel,
    required this.registrarDisplay,
    required this.maskedFolio,
    required this.holderRelationship,
    required this.status,
    required this.history,
    this.submittedAt,
    this.updatedAt,
    this.expiresAt,
  });

  final String requestId;
  final int version;
  final String investorDisplayLabel;
  final String registrarDisplay;
  final String maskedFolio;
  final FolioHolderRelationship holderRelationship;
  final FolioVerificationStatus status;
  final List<AdvisorFolioVerificationHistoryEvent> history;
  final DateTime? submittedAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;
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
