import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/onboarding_case.dart';
import 'investor_onboarding_repository.dart';

class KycCase {
  KycCase(Map<String, dynamic> json)
      : onboarding = OnboardingCase.fromJson(json),
        amcs = (json['amcs'] as List? ?? [])
            .map((e) => Map<String, String>.from(e as Map))
            .toList(),
        canOpen = json['can_open_ekyc'] == true;
  final OnboardingCase onboarding;
  final List<Map<String, String>> amcs;
  final bool canOpen;
  String get id => onboarding.id;
  String get state => onboarding.status;
}

abstract class OnboardingKycRepository {
  InvestorOnboardingRepository get legacy;
  Future<KycCase> start(String workspace, String id, String pan);
  Future<KycCase> get(String id);
  Future<KycCase> request(String id, String requestId, String action,
      {String? email, String? mobile, String? amc});
  Future<String?> link(String id);
}

class SupabaseOnboardingKycRepository implements OnboardingKycRepository {
  SupabaseOnboardingKycRepository(this.client);
  final SupabaseClient client;
  @override
  InvestorOnboardingRepository get legacy =>
      SupabaseInvestorOnboardingRepository(client);
  Future<KycCase> _call(String rpc, Map<String, dynamic> params) async =>
      KycCase(Map<String, dynamic>.from(
          await client.rpc(rpc, params: params) as Map));
  @override
  Future<KycCase> start(String workspace, String id, String pan) => _call(
      'start_onboarding_kyc',
      {'p_workspace_id': workspace, 'p_case_id': id, 'p_pan': pan});
  @override
  Future<KycCase> get(String id) =>
      _call('get_onboarding_kyc', {'p_case_id': id});
  @override
  Future<KycCase> request(String id, String requestId, String action,
          {String? email, String? mobile, String? amc}) =>
      _call('request_onboarding_kyc', {
        'p_case_id': id,
        'p_request_id': requestId,
        'p_action': action,
        'p_email': email,
        'p_mobile': mobile,
        'p_amc_code': amc
      });
  @override
  Future<String?> link(String id) async =>
      await client.rpc('get_onboarding_ekyc_link', params: {'p_case_id': id})
          as String?;
}
