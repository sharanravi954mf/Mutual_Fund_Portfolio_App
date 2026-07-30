import '../features/investor_identity/models/workspace_membership.dart';
import 'supabase_service.dart';

class MembershipService {
  final _client = SupabaseService().client;

  Future<List<WorkspaceMembership>> getMemberships(String workspaceId) async {
    try {
      final response = await _client
          .from('workspace_memberships')
          .select()
          .eq('workspace_id', workspaceId);
      return (response as List)
          .map((json) => WorkspaceMembership.fromJson(json))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<bool> updateMembershipStatus(
    String membershipId,
    MembershipStatus status,
  ) async {
    try {
      await _client.from('workspace_memberships').update({
        'status': status.databaseValue,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', membershipId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<WorkspaceMembership?> addMember(
    String workspaceId,
    String profileId,
    WorkspaceRole role,
  ) async {
    try {
      final response = await _client
          .from('workspace_memberships')
          .insert({
            'workspace_id': workspaceId,
            'profile_id': profileId,
            'role': role.databaseValue,
            'status': 'active',
          })
          .select()
          .single();
      return WorkspaceMembership.fromJson(response);
    } catch (e) {
      return null;
    }
  }
}
