import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../features/investor_identity/models/workspace_invitation.dart';
import '../features/investor_identity/models/workspace_membership.dart';
import 'supabase_service.dart';

class InvitationService {
  final _client = SupabaseService().client;

  Future<List<WorkspaceInvitation>> getInvitations(String workspaceId) async {
    try {
      final response = await _client
          .from('workspace_invitations')
          .select()
          .eq('workspace_id', workspaceId);
      return (response as List)
          .map((json) => WorkspaceInvitation.fromJson(json))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<WorkspaceInvitation?> createInvitation({
    required String workspaceId,
    required String email,
    required WorkspaceRole role,
    required String invitedBy,
    required String plaintextToken,
    required DateTime expiresAt,
  }) async {
    try {
      final bytes = utf8.encode(plaintextToken);
      final hash = sha256.convert(bytes).toString();

      final response = await _client
          .from('workspace_invitations')
          .insert({
            'workspace_id': workspaceId,
            'email': email,
            'role': role.databaseValue,
            'invited_by': invitedBy,
            'token_hash': hash,
            'status': 'pending',
            'expires_at': expiresAt.toIso8601String(),
          })
          .select()
          .single();
      return WorkspaceInvitation.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  Future<bool> acceptInvitation(String plaintextToken) async {
    try {
      final response = await _client.rpc(
        'accept_workspace_invitation',
        params: {'p_plaintext_token': plaintextToken},
      );
      return response as bool;
    } catch (e) {
      return false;
    }
  }
}
