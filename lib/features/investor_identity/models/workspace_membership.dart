enum WorkspaceRole {
  investor,
  advisor,
  admin,
  operations,
  client;

  static WorkspaceRole fromDatabase(String value) {
    switch (value.toLowerCase()) {
      case 'investor':
        return WorkspaceRole.investor;
      case 'advisor':
        return WorkspaceRole.advisor;
      case 'admin':
        return WorkspaceRole.admin;
      case 'operations':
        return WorkspaceRole.operations;
      case 'client':
        return WorkspaceRole.client;
      default:
        return WorkspaceRole.investor;
    }
  }

  String get databaseValue => name;
}

enum MembershipStatus {
  active,
  inactive,
  suspended;

  static MembershipStatus fromDatabase(String value) {
    switch (value.toLowerCase()) {
      case 'active':
        return MembershipStatus.active;
      case 'inactive':
        return MembershipStatus.inactive;
      case 'suspended':
        return MembershipStatus.suspended;
      default:
        return MembershipStatus.active;
    }
  }

  String get databaseValue => name;
}

class WorkspaceMembership {
  const WorkspaceMembership({
    required this.id,
    required this.workspaceId,
    required this.profileId,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.endedAt,
    this.invitedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String workspaceId;
  final String profileId;
  final WorkspaceRole role;
  final MembershipStatus status;
  final DateTime joinedAt;
  final DateTime? endedAt;
  final String? invitedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == MembershipStatus.active;
  bool get isSuspended => status == MembershipStatus.suspended;
  bool get isInactive => status == MembershipStatus.inactive;

  factory WorkspaceMembership.fromJson(Map<String, dynamic> json) {
    return WorkspaceMembership(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      profileId: json['profile_id'] as String,
      role: WorkspaceRole.fromDatabase(json['role'] as String),
      status:
          MembershipStatus.fromDatabase(json['status'] as String? ?? 'active'),
      joinedAt: DateTime.parse(json['joined_at'] as String),
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      invitedBy: json['invited_by'] as String?,
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
      'profile_id': profileId,
      'role': role.databaseValue,
      'status': status.databaseValue,
      'joined_at': joinedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'invited_by': invitedBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
