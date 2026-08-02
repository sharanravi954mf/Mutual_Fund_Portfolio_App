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

enum OrderPhase {
  initial,
  loadingReferenceData,
  ready,
  emptyInvestors,
  emptyFolios,
  emptyHoldings,
  accessDenied,
  offline,
  validationFailure,
  recoverableFailure,
  validating,
  submitting,
  submitted,
}

class OrderContext {
  final String workspaceId;
  final String investorProfileId;
  final String investorFullName;
  final String? investorEmail;
  final String? investorPhone;
  final String initiatorProfileId;
  final String initiationRole;
  final String initiationChannel;

  const OrderContext({
    required this.workspaceId,
    required this.investorProfileId,
    required this.investorFullName,
    this.investorEmail,
    this.investorPhone,
    required this.initiatorProfileId,
    required this.initiationRole,
    required this.initiationChannel,
  });

  OrderContext copyWith({
    String? workspaceId,
    String? investorProfileId,
    String? investorFullName,
    String? investorEmail,
    String? investorPhone,
    String? initiatorProfileId,
    String? initiationRole,
    String? initiationChannel,
  }) {
    return OrderContext(
      workspaceId: workspaceId ?? this.workspaceId,
      investorProfileId: investorProfileId ?? this.investorProfileId,
      investorFullName: investorFullName ?? this.investorFullName,
      investorEmail: investorEmail ?? this.investorEmail,
      investorPhone: investorPhone ?? this.investorPhone,
      initiatorProfileId: initiatorProfileId ?? this.initiatorProfileId,
      initiationRole: initiationRole ?? this.initiationRole,
      initiationChannel: initiationChannel ?? this.initiationChannel,
    );
  }
}

class OrderDraft {
  final OrderContext? context;
  final String schemeCode;
  final OrderType type;
  final double? amount;
  final double? units;
  final String? folioReferenceId;
  final String? destinationSchemeCode;

  const OrderDraft({
    this.context,
    required this.schemeCode,
    required this.type,
    this.amount,
    this.units,
    this.folioReferenceId,
    this.destinationSchemeCode,
  });

  OrderDraft copyWith({
    OrderContext? context,
    String? schemeCode,
    OrderType? type,
    double? amount,
    double? units,
    String? folioReferenceId,
    String? destinationSchemeCode,
    bool clearAmount = false,
    bool clearUnits = false,
    bool clearFolio = false,
    bool clearDestinationScheme = false,
    bool clearContext = false,
  }) {
    return OrderDraft(
      context: clearContext ? null : (context ?? this.context),
      schemeCode: schemeCode ?? this.schemeCode,
      type: type ?? this.type,
      amount: clearAmount ? null : (amount ?? this.amount),
      units: clearUnits ? null : (units ?? this.units),
      folioReferenceId:
          clearFolio ? null : (folioReferenceId ?? this.folioReferenceId),
      destinationSchemeCode: clearDestinationScheme
          ? null
          : (destinationSchemeCode ?? this.destinationSchemeCode),
    );
  }

  /// Run all validation checks. Returns null if valid, or a list of validation errors.
  List<String>? validate() {
    final errors = <String>[];

    final ctx = context;
    if (ctx == null) {
      errors.add(
          'Order context is required. Beneficiary or workspace could not be verified.');
      return errors;
    }

    if (ctx.workspaceId.trim().isEmpty) {
      errors.add('Workspace context is required.');
    }
    if (ctx.investorProfileId.trim().isEmpty) {
      errors.add('Beneficiary investor is required.');
    }
    if (schemeCode.trim().isEmpty) {
      errors.add('Scheme is required.');
    }

    if (type == OrderType.sell || type == OrderType.switchOrder) {
      if (folioReferenceId == null || folioReferenceId!.trim().isEmpty) {
        errors.add('Folio selection is required for Sell/Switch orders.');
      }
    }

    if (type == OrderType.switchOrder) {
      if (destinationSchemeCode == null ||
          destinationSchemeCode!.trim().isEmpty) {
        errors.add('Destination scheme is required for Switch orders.');
      } else if (destinationSchemeCode!.trim() == schemeCode.trim()) {
        errors.add(
            'Source and destination schemes cannot be identical for Switch orders.');
      }
    }

    final hasAmount = amount != null;
    final hasUnits = units != null;
    final amountIsValid = hasAmount && amount! > 0 && amount!.isFinite;
    final unitsAreValid = hasUnits && units! > 0 && units!.isFinite;

    if (hasAmount && hasUnits) {
      errors.add('Enter either amount or units, not both.');
    } else if (hasAmount && !amountIsValid) {
      errors.add('Amount must be positive and finite.');
    } else if (hasUnits && !unitsAreValid) {
      errors.add('Units must be positive and finite.');
    } else if (!hasAmount && !hasUnits) {
      errors.add('Enter a positive finite amount or units.');
    }

    return errors.isEmpty ? null : errors;
  }
}
