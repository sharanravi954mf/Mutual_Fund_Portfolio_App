import '../models/folio_verification_models.dart';

class FolioVerificationListItem {
  const FolioVerificationListItem({
    required this.registrarDisplay,
    required this.maskedFolio,
    required this.status,
    required this.submittedAt,
  });

  final String registrarDisplay;
  final String maskedFolio;
  final FolioVerificationStatus status;
  final DateTime? submittedAt;

  @override
  bool operator ==(Object other) =>
      other is FolioVerificationListItem &&
      registrarDisplay == other.registrarDisplay &&
      maskedFolio == other.maskedFolio &&
      status == other.status &&
      submittedAt == other.submittedAt;

  @override
  int get hashCode => Object.hash(
        registrarDisplay,
        maskedFolio,
        status,
        submittedAt,
      );
}

class FolioVerificationRow {
  const FolioVerificationRow({
    required this.display,
    required this.requestId,
    required this.version,
  });

  final FolioVerificationListItem display;
  final String requestId;
  final int version;

  @override
  bool operator ==(Object other) =>
      other is FolioVerificationRow &&
      display == other.display &&
      requestId == other.requestId &&
      version == other.version;

  @override
  int get hashCode => Object.hash(display, requestId, version);
}
