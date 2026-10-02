enum NseReadKind {
  orderStatus,
  provOrders,
  clientAuthorization,
  clientDetail,
  twoFa,
  clientKycReport,
  fatcaReport,
  elogReport,
  orderLifecycle,
  transactionDetail,
  fundOrder,
  fundAge,
  allotmentStatement,
  redemptionStatement,
  redemptionPayout,
  redemptionPayoutNonDemat,
  sipRegReport,
  sipCanReport,
  sipInstDueReport,
  sipTopupReport,
  stepupRegReport,
  xsipRegReport,
  xsipCanReport,
  xsipInstDueReport,
  xsipTopupReport,
  stpRegReport,
  stpCanReport,
  stpInstDueReport,
  swpRegReport,
  swpCanReport,
  swpInstDueReport,
  sipAmcPauseReport;

  static const _apis = [
    'ORDER_STATUS',
    'PROV_ORDERS',
    'CLIENT_AUTHORIZATION',
    'CLIENT_DETAIL',
    'TWO_FA',
    'CLIENT_KYC_REPORT',
    'FATCA_REPORT',
    'ELOG_REPORT',
    'ORDER_LIFECYCLE',
    'TRANSACTION_DETAIL',
    'FUND_ORDER',
    'FUND_AGE',
    'ALLOTMENT_STATEMENT',
    'REDEMPTION_STATEMENT',
    'REDEMPTION_PAYOUT',
    'REDEMPTION_PAYOUT_NON_DEMAT',
    'SIP_REG_REPORT',
    'SIP_CAN_REPORT',
    'SIP_INST_DUE_REPORT',
    'SIP_TOPUP_REPORT',
    'STEPUP_REG_REPORT',
    'XSIP_REG_REPORT',
    'XSIP_CAN_REPORT',
    'XSIP_INST_DUE_REPORT',
    'XSIP_TOPUP_REPORT',
    'STP_REG_REPORT',
    'STP_CAN_REPORT',
    'STP_INST_DUE_REPORT',
    'SWP_REG_REPORT',
    'SWP_CAN_REPORT',
    'SWP_INST_DUE_REPORT',
    'SIP_AMC_PAUSE_REPORT'
  ];
  String get api => _apis[index];
  String get wire => 'read_${api.toLowerCase()}';
  bool get isSettlement => index >= 12 && index <= 15;
  bool get optionalDates => index >= 16;
  bool get noDates => index >= 5 && index <= 7;
  bool get singleDate => this == fundAge;
  bool get isDue =>
      this == sipInstDueReport ||
      this == xsipInstDueReport ||
      this == stpInstDueReport ||
      this == swpInstDueReport;
  static NseReadKind parse(Object? value) =>
      values.firstWhere((kind) => kind.wire == value,
          orElse: () => throw const FormatException('Unknown read kind'));
}

enum NseDisplayStatus {
  queued('QUEUED'),
  running('RUNNING'),
  retryPending('RETRY_PENDING'),
  success('SUCCESS'),
  businessFailed('BUSINESS_FAILED'),
  failedClosed('FAILED_CLOSED'),
  failed('FAILED'),
  reconciliationRequired('RECONCILIATION_REQUIRED'),
  resultUnavailable('RESULT_UNAVAILABLE');

  const NseDisplayStatus(this.wire);
  final String wire;
  String get label => switch (this) {
        queued => 'Queued',
        running => 'Running',
        retryPending => 'Waiting for backend retry',
        success => 'Success',
        businessFailed => 'Business failed',
        failedClosed => 'Failed closed',
        failed => 'Failed',
        reconciliationRequired => 'Reconciliation required',
        resultUnavailable => 'Result unavailable — review required',
      };
  static NseDisplayStatus parse(Object? value) => values.firstWhere(
      (status) => status.wire == value,
      orElse: () => throw const FormatException('Unknown operation status'));
}

class NseFailure implements Exception {
  const NseFailure(this.code);
  final String code;
  bool get accessDenied =>
      code == 'NOT_AUTHORIZED' || code == 'TARGET_UNAVAILABLE';
  bool get uncertain =>
      code == 'NETWORK' ||
      code == 'INVALID_RESPONSE' ||
      code == 'TEMPORARILY_UNAVAILABLE';
  String get message => switch (code) {
        'NOT_AUTHORIZED' =>
          'You do not have access to this client’s NSE reads.',
        'TARGET_UNAVAILABLE' => 'This operation or client is unavailable.',
        'OWNED_STP_REGISTRATION_SELECTION_REQUIRED' =>
          'Owned STP registration evidence must be selected by the service. This console command is unavailable.',
        'INVALID_COMMAND' => 'Check the dates and selected report rows.',
        'BLOCKED_PREREQUISITE' =>
          'The investor integration or owned evidence is not ready.',
        'FEATURE_DISABLED' =>
          'NSE reads have not been enabled for this workspace.',
        'REQUEST_CONFLICT' =>
          'This request was already used with different options. Reload its status.',
        'OPERATION_IN_PROGRESS' =>
          'This report is already running. Refresh the history.',
        'RATE_LIMITED' => 'Please wait before starting another read.',
        _ => 'Status could not be confirmed. Check the connection and refresh.',
      };
}

String nseReasonLabel(String? reason) => switch (reason) {
      'REGISTERED_ACCOUNT_REQUIRED' =>
        'Registered NSE investor / UCC data is required.',
      'ACCOUNT_IDENTITY_UNAVAILABLE' => 'The account identity needs review.',
      'VERIFIED_IDENTITY_REQUIRED' => 'Verified investor identity is required.',
      'FEATURE_DISABLED' =>
        'Reads are disabled until this DEV deployment is verified.',
      'POSITIVE_OWNED_ORDER_EVIDENCE_REQUIRED' =>
        'Positive owned ORDER_STATUS evidence is required.',
      'OWNED_ORDER_SELECTION_REQUIRED' =>
        'Select eligible rows from an owned ORDER_STATUS result.',
      'ORDER_EVIDENCE_NOT_ELIGIBLE' =>
        'This row does not meet this report’s ownership and order requirements.',
      'OWNED_STP_REGISTRATION_SELECTION_REQUIRED' =>
        'Owned STP registration evidence must be selected by the service. This console command is unavailable.',
      'INVALID_COMMAND' => 'Check the dates and selected rows.',
      null => 'Available',
      _ => 'Prerequisites need review.',
    };

Map<String, dynamic> nseObject(Object? value) {
  if (value is! Map) throw const FormatException('Expected object');
  return Map<String, dynamic>.from(value);
}

String nseString(Object? value) {
  if (value is! String) throw const FormatException('Expected string');
  return value;
}

bool nseBool(Object? value) {
  if (value is! bool) throw const FormatException('Expected boolean');
  return value;
}

int nseCount(Object? value) {
  if (value is! int || value < 0) throw const FormatException('Expected count');
  return value;
}

final nseUuidPattern =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
String nseUuid(Object? value) {
  final s = nseString(value);
  if (!nseUuidPattern.hasMatch(s)) {
    throw const FormatException('Expected local reference');
  }
  return s;
}

class NseTarget {
  const NseTarget(this.id, this.clientLabel, this.workspaceLabel);
  final String id, clientLabel, workspaceLabel;
  factory NseTarget.fromJson(Map<String, dynamic> row) => NseTarget(
      nseUuid(row['target_ref']),
      row['client_label'] is String
          ? row['client_label'] as String
          : 'Unnamed client',
      nseString(row['workspace_label']));
}

class NseCapability {
  const NseCapability(this.kind, this.available, this.reason);
  final NseReadKind kind;
  final bool available;
  final String? reason;
  bool get canSelectEvidence =>
      kind.isSettlement && reason == 'OWNED_ORDER_SELECTION_REQUIRED';
  factory NseCapability.fromJson(Map<String, dynamic> row) {
    if (!['AVAILABLE', 'BLOCKED_PREREQUISITE'].contains(row['availability'])) {
      throw const FormatException('Unknown availability');
    }
    return NseCapability(NseReadKind.parse(row['kind']),
        row['availability'] == 'AVAILABLE', row['reason'] as String?);
  }
}

class NseReadContext {
  const NseReadContext(this.target, this.accountState, this.verificationStatus,
      this.deploymentVerified, this.capabilities,
      {this.verificationOperationState});
  final String target, accountState, verificationStatus;
  final String? verificationOperationState;
  final bool deploymentVerified;
  final List<NseCapability> capabilities;
  factory NseReadContext.fromJson(Map<String, dynamic> row) {
    if (row['environment'] != 'UAT') {
      throw const FormatException('Unexpected environment');
    }
    final state = nseString(row['account_state']);
    if (![
      'NOT_REGISTERED',
      'REGISTRATION_PENDING',
      'REGISTERED',
      'VALIDATION_FAILED',
      'REGISTRATION_FAILED',
      'RECONCILIATION_REQUIRED'
    ].contains(state)) {
      throw const FormatException('Unknown account state');
    }
    final verification = nseString(row['verification_status']);
    if (!['CONFIRMED', 'NOT_CONFIRMED', 'HTTP_FAILED', 'UNKNOWN']
        .contains(verification)) {
      throw const FormatException('Unknown verification state');
    }
    final verificationOperation = row['verification_operation_state'];
    if (verificationOperation != null &&
        ![
          'PREPARED',
          'QUEUED',
          'SUBMITTING',
          'SUCCESS',
          'VALIDATION_FAILED',
          'BUSINESS_FAILED',
          'HTTP_FAILED',
          'SUBMISSION_FAILED',
          'RECONCILIATION_REQUIRED'
        ].contains(verificationOperation)) {
      throw const FormatException('Unknown verification operation');
    }
    return NseReadContext(
        nseUuid(row['target_ref']),
        state,
        verification,
        nseBool(row['deployment_verified']),
        (row['capabilities'] as List)
            .map((x) => NseCapability.fromJson(nseObject(x)))
            .toList(growable: false),
        verificationOperationState: verificationOperation as String?);
  }
}

class NseReadCommand {
  NseReadCommand(
      {required this.kind,
      this.from,
      this.to,
      this.date,
      this.sourceOperationId,
      List<int> rowIndices = const []})
      : rowIndices = List.unmodifiable(rowIndices);
  final NseReadKind kind;
  final String? from, to, date, sourceOperationId;
  final List<int> rowIndices;
  Map<String, dynamic> toJson() => {
        'kind': kind.wire,
        'options': {
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          if (date != null) 'date': date,
          if (sourceOperationId != null)
            'source_operation_id': sourceOperationId,
          if (kind.isSettlement) 'row_indices': rowIndices,
        }
      };
  factory NseReadCommand.fromJson(Map<String, dynamic> row) {
    final kind = NseReadKind.parse(row['kind']);
    final options = nseObject(row['options']);
    return NseReadCommand(
        kind: kind,
        from: options['from'] as String?,
        to: options['to'] as String?,
        date: options['date'] as String?,
        sourceOperationId: options['source_operation_id'] == null
            ? null
            : nseUuid(options['source_operation_id']),
        rowIndices: options['row_indices'] == null
            ? const []
            : (options['row_indices'] as List).map(nseCount).toList());
  }
}

class NseAcceptance {
  const NseAcceptance(this.requestId, this.operationId);
  final String requestId, operationId;
  factory NseAcceptance.fromJson(Map<String, dynamic> row) {
    if (!['ACCEPTED', 'REPLAYED'].contains(row['acceptance'])) {
      throw const FormatException('Unknown acceptance');
    }
    return NseAcceptance(
        nseUuid(row['request_id']), nseUuid(row['operation_id']));
  }
}

class NseSummary {
  const NseSummary(this.nativeStatus, this.category, this.recordCount,
      this.validCount, this.invalidCount, this.otherCount);
  final String? nativeStatus;
  final String category;
  final int? recordCount, validCount, invalidCount, otherCount;
  factory NseSummary.fromJson(Map<String, dynamic> row) {
    final native = row['native_status'];
    if (native != null && native != 'S' && native != 'F') {
      throw const FormatException('Unknown native status');
    }
    final category = nseString(row['category'] ?? 'pending');
    // Server categories are allowlisted; a second structural bound prevents
    // rendering provider diagnostics if an incompatible response reaches Flutter.
    if (!RegExp(r'^[a-z][a-z_]{0,79}$').hasMatch(category)) {
      throw const FormatException('Invalid category');
    }
    int? count(String key) => row[key] == null ? null : nseCount(row[key]);
    return NseSummary(native as String?, category, count('record_count'),
        count('valid_count'), count('invalid_count'), count('other_count'));
  }
}

class NseOperation {
  const NseOperation(
      {required this.id,
      required this.targetRef,
      required this.kind,
      required this.status,
      required this.terminal,
      required this.attempts,
      required this.createdAt,
      required this.updatedAt,
      required this.fetchedAt,
      this.submittedAt,
      this.completedAt,
      this.summary});
  final String id, targetRef;
  final NseReadKind kind;
  final NseDisplayStatus status;
  final bool terminal;
  final int attempts;
  final DateTime createdAt, updatedAt, fetchedAt;
  final DateTime? submittedAt, completedAt;
  final NseSummary? summary;
  factory NseOperation.fromJson(Map<String, dynamic> row) {
    final status = NseDisplayStatus.parse(row['display_status']);
    final terminal = nseBool(row['terminal']);
    if (terminal ==
        [
          NseDisplayStatus.queued,
          NseDisplayStatus.running,
          NseDisplayStatus.retryPending
        ].contains(status)) {
      throw const FormatException('Inconsistent lifecycle');
    }
    return NseOperation(
        id: nseUuid(row['operation_id']),
        targetRef: nseUuid(row['target_ref']),
        kind: NseReadKind.parse(row['kind']),
        status: status,
        terminal: terminal,
        attempts: nseCount(row['attempt_count']),
        createdAt: DateTime.parse(nseString(row['created_at'])),
        updatedAt: DateTime.parse(nseString(row['updated_at'])),
        fetchedAt: DateTime.parse(nseString(row['fetched_at'])),
        submittedAt: row['submitted_at'] == null
            ? null
            : DateTime.parse(nseString(row['submitted_at'])),
        completedAt: row['completed_at'] == null
            ? null
            : DateTime.parse(nseString(row['completed_at'])),
        summary: row['summary'] == null
            ? null
            : NseSummary.fromJson(nseObject(row['summary'])));
  }
}

class NseCandidate {
  const NseCandidate(this.index, this.eligible);
  final int index;
  final bool eligible;
  factory NseCandidate.fromJson(Map<String, dynamic> row) =>
      NseCandidate(nseCount(row['row_index']), nseBool(row['eligible']));
}

class NsePage<T> {
  const NsePage(this.items, this.cursor);
  final List<T> items;
  final Object? cursor;
}
