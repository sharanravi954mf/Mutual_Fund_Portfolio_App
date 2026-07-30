enum OrderType {
  buy,
  sell,
  switchOrder;

  static OrderType fromDatabase(String value) {
    switch (value.toLowerCase()) {
      case 'buy':
        return OrderType.buy;
      case 'sell':
        return OrderType.sell;
      case 'switch':
        return OrderType.switchOrder;
      default:
        return OrderType.buy;
    }
  }

  String get databaseValue {
    switch (this) {
      case OrderType.buy:
        return 'buy';
      case OrderType.sell:
        return 'sell';
      case OrderType.switchOrder:
        return 'switch';
    }
  }
}

enum OrderStatus {
  pendingQualification,
  pendingReview,
  autoApproved,
  approved,
  rejected,
  cancelled;

  static OrderStatus fromDatabase(String value) {
    switch (value.toLowerCase()) {
      case 'pending_qualification':
        return OrderStatus.pendingQualification;
      case 'pending_review':
        return OrderStatus.pendingReview;
      case 'auto_approved':
        return OrderStatus.autoApproved;
      case 'approved':
        return OrderStatus.approved;
      case 'rejected':
        return OrderStatus.rejected;
      case 'cancelled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.pendingQualification;
    }
  }

  String get databaseValue {
    switch (this) {
      case OrderStatus.pendingQualification:
        return 'pending_qualification';
      case OrderStatus.pendingReview:
        return 'pending_review';
      case OrderStatus.autoApproved:
        return 'auto_approved';
      case OrderStatus.approved:
        return 'approved';
      case OrderStatus.rejected:
        return 'rejected';
      case OrderStatus.cancelled:
        return 'cancelled';
    }
  }
}

class OrderDraft {
  final String workspaceId;
  final String investorProfileId;
  final String schemeCode;
  final OrderType type;
  final double? amount;
  final double? units;
  final String? folioNumber; // Local-only
  final String? destSchemeCode; // Local-only (destination scheme for Switch)

  const OrderDraft({
    required this.workspaceId,
    required this.investorProfileId,
    required this.schemeCode,
    required this.type,
    this.amount,
    this.units,
    this.folioNumber,
    this.destSchemeCode,
  });

  OrderDraft copyWith({
    String? workspaceId,
    String? investorProfileId,
    String? schemeCode,
    OrderType? type,
    double? amount,
    double? units,
    String? folioNumber,
    String? destSchemeCode,
    bool clearAmount = false,
    bool clearUnits = false,
    bool clearFolio = false,
    bool clearDestScheme = false,
  }) {
    return OrderDraft(
      workspaceId: workspaceId ?? this.workspaceId,
      investorProfileId: investorProfileId ?? this.investorProfileId,
      schemeCode: schemeCode ?? this.schemeCode,
      type: type ?? this.type,
      amount: clearAmount ? null : (amount ?? this.amount),
      units: clearUnits ? null : (units ?? this.units),
      folioNumber: clearFolio ? null : (folioNumber ?? this.folioNumber),
      destSchemeCode:
          clearDestScheme ? null : (destSchemeCode ?? this.destSchemeCode),
    );
  }

  /// Run all validation checks. Returns null if valid, or a list of validation errors.
  List<String>? validate() {
    final errors = <String>[];

    if (workspaceId.trim().isEmpty) {
      errors.add('Workspace context is required.');
    }
    if (investorProfileId.trim().isEmpty) {
      errors.add('Beneficiary investor is required.');
    }
    if (schemeCode.trim().isEmpty) {
      errors.add('Scheme is required.');
    }

    if (type == OrderType.sell || type == OrderType.switchOrder) {
      if (folioNumber == null || folioNumber!.trim().isEmpty) {
        errors.add('Folio selection is required for Sell/Switch orders.');
      }
    }

    if (type == OrderType.switchOrder) {
      if (destSchemeCode == null || destSchemeCode!.trim().isEmpty) {
        errors.add('Destination scheme is required for Switch orders.');
      } else if (destSchemeCode!.trim() == schemeCode.trim()) {
        errors.add(
            'Source and destination schemes cannot be identical for Switch orders.');
      }
    }

    // At least one of amount or units must be specified and positive
    final hasAmount = amount != null && amount! > 0 && amount!.isFinite;
    final hasUnits = units != null && units! > 0 && units!.isFinite;

    if (!hasAmount && !hasUnits) {
      errors.add('A positive finite amount or units is required.');
    }

    return errors.isEmpty ? null : errors;
  }
}
