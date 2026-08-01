import '../features/investor_identity/models/advisor_investor_assignment.dart';
import 'supabase_service.dart';

class AssignmentService {
  final _client = SupabaseService().client;

  Future<List<AdvisorInvestorAssignment>> getAssignmentsForAdvisor(
    String advisorId,
  ) async {
    try {
      final response = await _client
          .from('advisor_investor_assignments')
          .select()
          .eq('advisor_id', advisorId);
      return (response as List)
          .map((json) => AdvisorInvestorAssignment.fromJson(json))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<AdvisorInvestorAssignment?> createAssignment({
    required String advisorId,
    required String investorId,
    required String assignedBy,
  }) async {
    try {
      final response = await _client.from('advisor_investor_assignments').insert({
        'advisor_id': advisorId,
        'investor_id': investorId,
        'assigned_by': assignedBy,
        'status': 'active',
      }).select().single();
      return AdvisorInvestorAssignment.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  Future<bool> endAssignment(String assignmentId, String endedBy) async {
    try {
      await _client.from('advisor_investor_assignments').update({
        'status': 'ended',
        'ended_by': endedBy,
        'ended_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', assignmentId);
      return true;
    } catch (e) {
      return false;
    }
  }
}
