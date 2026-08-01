import '../models/folio_verification_models.dart';

class AdvisorFolioVerificationQueueItemDto {
  const AdvisorFolioVerificationQueueItemDto(this.json);

  final Map<String, dynamic> json;

  AdvisorFolioVerificationQueueItem toDomain() =>
      AdvisorFolioVerificationQueueItem(
        requestId: json['request_id'] as String,
        version: json['version'] as int,
        investorDisplayLabel: json['investor_display_label'] as String,
        registrarDisplay: json['registrar_display'] as String,
        maskedFolio: json['masked_folio'] as String,
        holderRelationship: _relationship(json['holder_relationship'] as String),
        status: FolioVerificationStatus.fromDatabase(json['status'] as String),
        submittedAt: _date(json['submitted_at']),
        updatedAt: _date(json['updated_at']),
      );
}

class AdvisorFolioVerificationDetailDto {
  const AdvisorFolioVerificationDetailDto(this.json);

  final Map<String, dynamic> json;

  AdvisorFolioVerificationDetail toDomain() => AdvisorFolioVerificationDetail(
        requestId: json['request_id'] as String,
        version: json['version'] as int,
        investorDisplayLabel: json['investor_display_label'] as String,
        registrarDisplay: json['registrar_display'] as String,
        maskedFolio: json['masked_folio'] as String,
        holderRelationship: _relationship(json['holder_relationship'] as String),
        status: FolioVerificationStatus.fromDatabase(json['status'] as String),
        submittedAt: _date(json['submitted_at']),
        updatedAt: _date(json['updated_at']),
        expiresAt: _date(json['expires_at']),
        history: List.unmodifiable(
          ((json['event_summary'] as List<dynamic>? ?? const [])
              .map((event) => AdvisorFolioVerificationHistoryEventDto(
                    Map<String, dynamic>.from(event as Map),
                  ).toDomain())),
        ),
      );
}

class AdvisorFolioVerificationHistoryEventDto {
  const AdvisorFolioVerificationHistoryEventDto(this.json);

  final Map<String, dynamic> json;

  AdvisorFolioVerificationHistoryEvent toDomain() =>
      AdvisorFolioVerificationHistoryEvent(
        type: json['event_type'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        previousStatus: json['previous_status'] == null
            ? null
            : FolioVerificationStatus.fromDatabase(
                json['previous_status'] as String),
        newStatus: json['new_status'] == null
            ? null
            : FolioVerificationStatus.fromDatabase(json['new_status'] as String),
        reasonCode: json['reason_code'] as String?,
      );
}

FolioHolderRelationship _relationship(String value) =>
    FolioHolderRelationship.values.firstWhere(
      (relationship) => relationship.databaseValue == value,
      orElse: () => throw ArgumentError.value(value, 'holder_relationship'),
    );

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.parse(value as String);
