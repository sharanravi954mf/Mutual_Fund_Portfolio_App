enum WorkspaceStatus {
  active,
  suspended,
  archived;

  static WorkspaceStatus fromDatabase(String value) {
    switch (value.toLowerCase()) {
      case 'active':
        return WorkspaceStatus.active;
      case 'suspended':
        return WorkspaceStatus.suspended;
      case 'archived':
        return WorkspaceStatus.archived;
      default:
        return WorkspaceStatus.active;
    }
  }

  String get databaseValue => name;
}

class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    required this.slug,
    required this.ownerProfileId,
    required this.workspaceStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String slug;
  final String? ownerProfileId;
  final WorkspaceStatus workspaceStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => workspaceStatus == WorkspaceStatus.active;
  bool get isSuspended => workspaceStatus == WorkspaceStatus.suspended;
  bool get isArchived => workspaceStatus == WorkspaceStatus.archived;

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      ownerProfileId: json['owner_profile_id'] as String?,
      workspaceStatus: WorkspaceStatus.fromDatabase(
        json['workspace_status'] as String? ?? 'active',
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(
        json['updated_at'] as String? ?? json['created_at'] as String,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'owner_profile_id': ownerProfileId,
      'workspace_status': workspaceStatus.databaseValue,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
