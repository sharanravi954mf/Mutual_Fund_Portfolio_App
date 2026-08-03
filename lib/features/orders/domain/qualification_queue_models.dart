import 'order_models.dart';
import 'masking.dart';

enum QualificationQueuePhase {
  initial,
  loading,
  ready,
  empty,
  refreshing,
  accessDenied,
  offline,
  failure,
}

enum QualificationDecision {
  approved,
  rejected;

  String get databaseValue => name;
}

enum QualificationFailureKind {
  stale,
  accessDenied,
  network,
  unknown,
}

class QualificationQueueFailure implements Exception {
  const QualificationQueueFailure(this.kind, this.message);

  final QualificationFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

class QualificationQueueSnapshot {
  const QualificationQueueSnapshot({
    required this.items,
    required this.fetchedAt,
  });

  final List<QualificationQueueItem> items;
  final DateTime fetchedAt;
}

class QualificationQueueItem {
  const QualificationQueueItem({
    required this.id,
    required this.workspaceId,
    required this.investorProfileId,
    required this.investorName,
    required this.initiatedByProfileId,
    required this.initiatorName,
    required this.initiatedByRole,
    required this.initiationChannel,
    required this.status,
    required this.type,
    required this.schemeCode,
    required this.createdAt,
    this.investorEmail,
    this.investorPhone,
    this.schemeName,
    this.destinationSchemeCode,
    this.destinationSchemeName,
    this.amount,
    this.units,
  });

  final String id;
  final String workspaceId;
  final String investorProfileId;
  final String investorName;
  final String? investorEmail;
  final String? investorPhone;
  final String initiatedByProfileId;
  final String initiatorName;
  final String initiatedByRole;
  final String initiationChannel;
  final OrderStatus status;
  final OrderType type;
  final String schemeCode;
  final String? schemeName;
  final String? destinationSchemeCode;
  final String? destinationSchemeName;
  final double? amount;
  final double? units;
  final DateTime createdAt;

  bool isSameInitiator(String? currentProfileId) =>
      currentProfileId != null && currentProfileId == initiatedByProfileId;

  String get maskedEmail => investorEmail == null
      ? 'No email on file'
      : MaskingUtil.maskEmail(investorEmail!);

  String get maskedPhone => investorPhone == null
      ? 'No phone on file'
      : MaskingUtil.maskPhone(investorPhone!);

  String get schemeDisplay => schemeName == null || schemeName!.trim().isEmpty
      ? schemeCode
      : '${schemeName!.trim()} ($schemeCode)';

  String get destinationSchemeDisplay {
    if (destinationSchemeCode == null || destinationSchemeCode!.isEmpty) {
      return '';
    }
    if (destinationSchemeName == null ||
        destinationSchemeName!.trim().isEmpty) {
      return destinationSchemeCode!;
    }
    return '${destinationSchemeName!.trim()} ($destinationSchemeCode)';
  }

  String get orderTypeLabel => switch (type) {
        OrderType.buy => 'Buy',
        OrderType.sell => 'Sell',
        OrderType.switchOrder => 'Switch',
      };

  String get statusLabel => status.databaseValue.replaceAll('_', ' ');
}
