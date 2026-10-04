class VerificationWorkspace {
  const VerificationWorkspace(this.id, this.name);
  final String id;
  final String name;

  factory VerificationWorkspace.fromJson(Map<String, dynamic> row) =>
      VerificationWorkspace(
          row['workspace_id'] as String, row['workspace_name'] as String);
}
