import '../models/folio_verification_models.dart';

class FolioVerificationRequestDto {
  const FolioVerificationRequestDto(this.json);
  final Map<String, dynamic> json;
  FolioVerificationRequest toDomain() => FolioVerificationRequest(
      id: json['request_id']?.toString() ?? json['id'] as String,
      status: FolioVerificationStatus.fromDatabase(json['status'] as String),
      version: json['version'] as int,
      submittedAt: _date('submitted_at'),
      resolvedAt: _date('resolved_at'),
      expiresAt: _date('expires_at'),
      retryOfRequestId: json['retry_of_request_id'] as String?);
  DateTime? _date(String key) =>
      json[key] == null ? null : DateTime.parse(json[key] as String);
}

class FolioVerificationEventDto {
  const FolioVerificationEventDto(this.json);
  final Map<String, dynamic> json;
  FolioVerificationEvent toDomain() => FolioVerificationEvent(
      id: json['id'] as String,
      type: json['event_type'] as String,
      occurredAt: DateTime.parse(json['created_at'] as String),
      reasonCode: json['reason_code'] as String?);
}

class FolioGrantSummaryDto {
  const FolioGrantSummaryDto(this.json);
  final Map<String, dynamic> json;
  FolioGrantSummary toDomain() => FolioGrantSummary(
      id: json['id'] as String,
      status: json['status'] as String,
      holderRelationship: FolioHolderRelationship.values.firstWhere(
          (value) => value.databaseValue == json['holder_relationship']),
      approvedAt: _date('approved_at'),
      revokedAt: _date('revoked_at'));
  DateTime? _date(String key) =>
      json[key] == null ? null : DateTime.parse(json[key] as String);
}

class InvestorFolioRequestListRecordDto {
  const InvestorFolioRequestListRecordDto(this.json);
  final Map<String, dynamic> json;
  InvestorFolioRequestListRecord toDomain() => InvestorFolioRequestListRecord(
      requestId: json['request_id'] as String,
      version: json['version'] as int,
      registrarDisplay: json['registrar_display'] as String,
      maskedFolio: json['masked_folio'] as String,
      status: FolioVerificationStatus.fromDatabase(json['status'] as String),
      submittedAt: json['submitted_at'] == null
          ? null
          : DateTime.parse(json['submitted_at'] as String));
}
