enum AssignmentStatus {
  active,
  ended;

  static AssignmentStatus fromDatabase(String value) {
    switch (value.toLowerCase()) {
      case 'active':
        return AssignmentStatus.active;
      case 'ended':
        return AssignmentStatus.ended;
      default:
        return AssignmentStatus.ended;
    }
  }

  String get databaseValue => name;
}

class AdvisorInvestorAssignment {
  const AdvisorInvestorAssignment({
    required this.id,
    this.workspaceId,
    required this.advisorId,
    required this.investorId,
    this.assignedBy,
    required this.assignedAt,
    this.endedBy,
    this.endedAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? workspaceId;
  final String advisorId;
  final String investorId;
  final String? assignedBy;
  final DateTime assignedAt;
  final String? endedBy;
  final DateTime? endedAt;
  final AssignmentStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive =>
      workspaceId != null &&
      status == AssignmentStatus.active &&
      endedAt == null;
  bool get isEnded => status == AssignmentStatus.ended;

  factory AdvisorInvestorAssignment.fromJson(Map<String, dynamic> json) {
    return AdvisorInvestorAssignment(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String?,
      advisorId: json['advisor_id'] as String,
      investorId: json['investor_id'] as String,
      assignedBy: json['assigned_by'] as String?,
      assignedAt: DateTime.parse(json['assigned_at'] as String),
      endedBy: json['ended_by'] as String?,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      status:
          AssignmentStatus.fromDatabase(json['status'] as String? ?? 'ended'),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(
        json['updated_at'] as String? ?? json['created_at'] as String,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workspace_id': workspaceId,
      'advisor_id': advisorId,
      'investor_id': investorId,
      'assigned_by': assignedBy,
      'assigned_at': assignedAt.toIso8601String(),
      'ended_by': endedBy,
      'ended_at': endedAt?.toIso8601String(),
      'status': status.databaseValue,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
