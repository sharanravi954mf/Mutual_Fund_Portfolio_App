import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/onboarding_case.dart';

abstract class InvestorOnboardingRepository {
  Future<List<Map<String, String>>> workspaces();
  Future<List<OnboardingCase>> list(String workspace);
  Future<OnboardingCase> get(String id);
  Future<OnboardingCase> save(
      String workspace, String id, int version, Map<String, String> fields);
  Future<OnboardingCase> resolve(String id, int version);
}

class SupabaseInvestorOnboardingRepository
    implements InvestorOnboardingRepository {
  SupabaseInvestorOnboardingRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<Map<String, String>>> workspaces() async =>
      (await client.rpc('list_investor_onboarding_workspaces') as List)
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
  @override
  Future<List<OnboardingCase>> list(String workspace) async => (await client
          .rpc('list_investor_onboarding',
              params: {'p_workspace_id': workspace}) as List)
      .map((e) => OnboardingCase.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
  @override
  Future<OnboardingCase> get(String id) async =>
      OnboardingCase.fromJson(Map<String, dynamic>.from(await client
          .rpc('get_investor_onboarding', params: {'p_case_id': id}) as Map));
  @override
  Future<OnboardingCase> save(String workspace, String id, int version,
          Map<String, String> fields) async =>
      OnboardingCase.fromJson(Map<String, dynamic>.from(
          await client.rpc('save_investor_onboarding', params: {
        'p_workspace_id': workspace,
        'p_case_id': id,
        'p_version': version,
        'p_fields': fields,
      }) as Map));
  @override
  Future<OnboardingCase> resolve(String id, int version) async =>
      OnboardingCase.fromJson(Map<String, dynamic>.from(await client.rpc(
          'resolve_investor_onboarding',
          params: {'p_case_id': id, 'p_version': version}) as Map));
}
