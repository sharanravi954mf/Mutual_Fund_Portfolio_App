import '../features/investor_identity/models/workspace.dart';
import 'supabase_service.dart';

class WorkspaceService {
  final _client = SupabaseService().client;

  Future<List<Workspace>> getWorkspaces() async {
    try {
      final response = await _client.from('workspaces').select();
      return (response as List)
          .map((json) => Workspace.fromJson(json))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<Workspace?> getWorkspace(String id) async {
    try {
      final response =
          await _client.from('workspaces').select().eq('id', id).maybeSingle();
      if (response == null) return null;
      return Workspace.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  Future<Workspace?> createWorkspace(String name, String ownerProfileId) async {
    try {
      final slugResponse = await _client
          .rpc('generate_unique_workspace_slug', params: {'p_name': name});
      final slug = slugResponse as String;

      final response = await _client
          .from('workspaces')
          .insert({
            'name': name,
            'slug': slug,
            'owner_profile_id': ownerProfileId,
            'workspace_status': 'active',
          })
          .select()
          .single();
      return Workspace.fromJson(response);
    } catch (e) {
      return null;
    }
  }
}
