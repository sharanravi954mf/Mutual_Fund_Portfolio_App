enum VerificationMethod {
  verifiedEmail,
  verifiedMobile,
  pan,
  folio,
  advisorAssisted,
  otp,
  documentUpload;

  String get databaseValue => switch (this) {
        VerificationMethod.verifiedEmail => 'verified_email',
        VerificationMethod.verifiedMobile => 'verified_mobile',
        VerificationMethod.pan => 'pan',
        VerificationMethod.folio => 'folio',
        VerificationMethod.advisorAssisted => 'advisor_assisted',
        VerificationMethod.otp => 'otp',
        VerificationMethod.documentUpload => 'document_upload',
      };

  static VerificationMethod fromDatabase(String value) =>
      VerificationMethod.values.firstWhere(
        (method) => method.databaseValue == value,
        orElse: () => throw ArgumentError.value(value, 'value'),
      );
}

enum VerificationStatus {
  draft,
  pendingAdvisorReview,
  approved,
  rejected,
  cancelled,
  expired;

  String get databaseValue => switch (this) {
        VerificationStatus.draft => 'draft',
        VerificationStatus.pendingAdvisorReview => 'pending_advisor_review',
        VerificationStatus.approved => 'approved',
        VerificationStatus.rejected => 'rejected',
        VerificationStatus.cancelled => 'cancelled',
        VerificationStatus.expired => 'expired',
      };

  static VerificationStatus fromDatabase(String value) =>
      VerificationStatus.values.firstWhere(
        (status) => status.databaseValue == value,
        orElse: () => throw ArgumentError.value(value, 'value'),
      );

  bool get canCancel => this == pendingAdvisorReview || this == draft;
  bool get canRetry => this == rejected || this == cancelled || this == expired;
}

class VerificationRequest {
  const VerificationRequest({
    required this.id,
    required this.method,
    required this.status,
    required this.createdAt,
    required this.version,
    this.submittedAt,
    this.resolvedAt,
  });

  final String id;
  final VerificationMethod method;
  final VerificationStatus status;
  final DateTime createdAt;
  final int version;
  final DateTime? submittedAt;
  final DateTime? resolvedAt;

  factory VerificationRequest.fromJson(Map<String, dynamic> json) =>
      VerificationRequest(
        id: json['id'] as String,
        method: VerificationMethod.fromDatabase(json['method_code'] as String),
        status: VerificationStatus.fromDatabase(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        version: json['version'] as int,
        submittedAt: json['submitted_at'] == null
            ? null
            : DateTime.parse(json['submitted_at'] as String),
        resolvedAt: json['resolved_at'] == null
            ? null
            : DateTime.parse(json['resolved_at'] as String),
      );
}

class VerificationEvent {
  const VerificationEvent({
    required this.id,
    required this.type,
    required this.createdAt,
    this.previousStatus,
    this.newStatus,
    this.reasonCode,
  });

  final String id;
  final String type;
  final VerificationStatus? previousStatus;
  final VerificationStatus? newStatus;
  final String? reasonCode;
  final DateTime createdAt;

  factory VerificationEvent.fromJson(Map<String, dynamic> json) =>
      VerificationEvent(
        id: json['id'] as String,
        type: json['event_type'] as String,
        previousStatus: json['previous_status'] == null
            ? null
            : VerificationStatus.fromDatabase(
                json['previous_status'] as String),
        newStatus: json['new_status'] == null
            ? null
            : VerificationStatus.fromDatabase(json['new_status'] as String),
        reasonCode: json['reason_code'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
