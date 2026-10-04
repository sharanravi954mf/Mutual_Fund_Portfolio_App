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
      await _client.rpc('set_workspace_membership_status', params: {
        'p_membership_id': membershipId,
        'p_status': status.databaseValue,
      });
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
    // Admission requires a verified recipient accepting a stored invitation.
    // A known profile UUID alone cannot establish a customer relationship.
    throw UnsupportedError('Use a workspace invitation to add a member.');
  }
}
