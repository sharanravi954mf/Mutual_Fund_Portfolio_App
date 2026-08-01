import 'workspace_membership.dart';

enum InvitationStatus {
  pending,
  accepted,
  expired,
  revoked;

  static InvitationStatus fromDatabase(String value) {
    switch (value.toLowerCase()) {
      case 'pending':
        return InvitationStatus.pending;
      case 'accepted':
        return InvitationStatus.accepted;
      case 'expired':
        return InvitationStatus.expired;
      case 'revoked':
        return InvitationStatus.revoked;
      default:
        return InvitationStatus.pending;
    }
  }

  String get databaseValue => name;
}

class WorkspaceInvitation {
  const WorkspaceInvitation({
    required this.id,
    required this.workspaceId,
    required this.email,
    required this.role,
    required this.invitedBy,
    required this.tokenHash,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String workspaceId;
  final String email;
  final WorkspaceRole role;
  final String invitedBy;
  final String tokenHash;
  final InvitationStatus status;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPending => status == InvitationStatus.pending;
  bool get isAccepted => status == InvitationStatus.accepted;
  bool get isExpired => status == InvitationStatus.expired || DateTime.now().isAfter(expiresAt);
  bool get isRevoked => status == InvitationStatus.revoked;

  factory WorkspaceInvitation.fromJson(Map<String, dynamic> json) {
    return WorkspaceInvitation(
      id: json['id'] as String,
      workspaceId: json['workspace_id'] as String,
      email: json['email'] as String,
      role: WorkspaceRole.fromDatabase(json['role'] as String),
      invitedBy: json['invited_by'] as String,
      tokenHash: json['token_hash'] as String,
      status: InvitationStatus.fromDatabase(json['status'] as String? ?? 'pending'),
      expiresAt: DateTime.parse(json['expires_at'] as String),
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
      'email': email,
      'role': role.databaseValue,
      'invited_by': invitedBy,
      'token_hash': tokenHash,
      'status': status.databaseValue,
      'expires_at': expiresAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
