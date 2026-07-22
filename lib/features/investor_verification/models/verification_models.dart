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
  expired,
  moreInformationRequired;

  String get databaseValue => switch (this) {
        VerificationStatus.draft => 'draft',
        VerificationStatus.pendingAdvisorReview => 'pending_advisor_review',
        VerificationStatus.approved => 'approved',
        VerificationStatus.rejected => 'rejected',
        VerificationStatus.cancelled => 'cancelled',
        VerificationStatus.expired => 'expired',
        VerificationStatus.moreInformationRequired =>
          'more_information_required',
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
    this.expiresAt,
    this.retryOfRequestId,
  });

  final String id;
  final VerificationMethod method;
  final VerificationStatus status;
  final DateTime createdAt;
  final int version;
  final DateTime? submittedAt;
  final DateTime? resolvedAt;
  final DateTime? expiresAt;
  final String? retryOfRequestId;

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
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String),
        retryOfRequestId: json['retry_of_request_id'] as String?,
      );
}

class VerificationQueueFilter {
  const VerificationQueueFilter({
    this.requestIdQuery = '',
    this.status,
    this.method,
  });

  final String requestIdQuery;
  final VerificationStatus? status;
  final VerificationMethod? method;

  VerificationQueueFilter copyWith({
    String? requestIdQuery,
    VerificationStatus? status,
    VerificationMethod? method,
    bool clearStatus = false,
    bool clearMethod = false,
  }) {
    return VerificationQueueFilter(
      requestIdQuery: requestIdQuery ?? this.requestIdQuery,
      status: clearStatus ? null : status ?? this.status,
      method: clearMethod ? null : method ?? this.method,
    );
  }
}

class AdvisorVerificationCandidate {
  const AdvisorVerificationCandidate({
    required this.token,
    required this.name,
    required this.profileSummary,
    this.maskedEmail,
    this.maskedMobile,
  });

  final String token;
  final String name;
  final String? maskedEmail;
  final String? maskedMobile;
  final String profileSummary;

  factory AdvisorVerificationCandidate.fromJson(Map<String, dynamic> json) {
    return AdvisorVerificationCandidate(
      token: json['candidate_token'] as String,
      name: json['candidate_name'] as String,
      maskedEmail: json['masked_email'] as String?,
      maskedMobile: json['masked_mobile'] as String?,
      profileSummary: json['profile_summary'] as String,
    );
  }
}

class AdvisorVerificationReview {
  const AdvisorVerificationReview({
    required this.request,
    required this.timeline,
    this.maskedEmail,
    this.maskedMobile,
  });

  final VerificationRequest request;
  final List<VerificationEvent> timeline;
  final String? maskedEmail;
  final String? maskedMobile;

  factory AdvisorVerificationReview.fromJson(
    Map<String, dynamic> json,
    List<VerificationEvent> timeline,
  ) {
    return AdvisorVerificationReview(
      request: VerificationRequest.fromJson(json),
      timeline: timeline,
      maskedEmail: json['requester_masked_email'] as String?,
      maskedMobile: json['requester_masked_mobile'] as String?,
    );
  }
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
