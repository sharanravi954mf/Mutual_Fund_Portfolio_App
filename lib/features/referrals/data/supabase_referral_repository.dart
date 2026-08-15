import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/investor_referral.dart';
import 'referral_repository.dart';

abstract class ReferralRpcClient {
  Future<dynamic> call(
    String functionName, {
    Map<String, dynamic> parameters = const <String, dynamic>{},
  });
}

class SupabaseReferralRpcClient implements ReferralRpcClient {
  const SupabaseReferralRpcClient(this.client);

  final SupabaseClient client;

  @override
  Future<dynamic> call(
    String functionName, {
    Map<String, dynamic> parameters = const <String, dynamic>{},
  }) =>
      client.rpc(functionName, params: parameters);
}

class SupabaseReferralRepository implements ReferralRepository {
  const SupabaseReferralRepository(this._client);

  factory SupabaseReferralRepository.fromClient(SupabaseClient client) =>
      SupabaseReferralRepository(SupabaseReferralRpcClient(client));

  final ReferralRpcClient _client;

  @override
  Future<InvestorReferral> getOrCreateCurrentInvestorReferral() async {
    try {
      final response = await _client.call('get_or_create_investor_referral');
      final rows = response is List ? response : <dynamic>[response];
      if (rows.length != 1 || rows.single is! Map) {
        throw const ReferralRepositoryException();
      }

      final row = Map<String, dynamic>.from(rows.single as Map);
      final code = row['referral_code'];
      final createdAt = row['created_at'];
      if (code is! String || code.isEmpty || createdAt is! String) {
        throw const ReferralRepositoryException();
      }

      return InvestorReferral(
        code: code,
        createdAt: DateTime.parse(createdAt),
      );
    } on ReferralRepositoryException {
      rethrow;
    } catch (_) {
      throw const ReferralRepositoryException();
    }
  }

  @override
  Future<String> createReferralOnboardingClaim(String referralCode) async {
    try {
      final response = await _client.call(
        'create_referral_onboarding_claim',
        parameters: <String, dynamic>{'p_referral_code': referralCode},
      );
      final rows = response is List ? response : <dynamic>[response];
      if (rows.length != 1 || rows.single is! Map) {
        throw const ReferralRepositoryException();
      }

      final token = Map<String, dynamic>.from(rows.single as Map)['claim_token'];
      if (token is! String || token.isEmpty) {
        throw const ReferralRepositoryException();
      }
      return token;
    } on ReferralRepositoryException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ReferralRepositoryException(
        'Referral onboarding could not be started.',
        _failureForMessage(error.message),
      );
    } catch (_) {
      throw const ReferralRepositoryException();
    }
  }

  @override
  Future<void> bindCurrentUserReferralOnboardingClaim(
    String claimToken,
  ) async {
    try {
      final response = await _client.call(
        'bind_referral_onboarding_claim',
        parameters: <String, dynamic>{'p_claim_token': claimToken},
      );
      final rows = response is List ? response : <dynamic>[response];
      if (rows.length != 1 || rows.single is! Map) {
        throw const ReferralRepositoryException();
      }

      final bound = Map<String, dynamic>.from(rows.single as Map)['bound'];
      if (bound is! bool || !bound) {
        throw const ReferralRepositoryException();
      }
    } on ReferralRepositoryException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ReferralRepositoryException(
        'Referral onboarding could not be secured.',
        _failureForMessage(error.message),
      );
    } catch (_) {
      throw const ReferralRepositoryException();
    }
  }

  @override
  Future<ReferralConversionResult> processCurrentInvestorReferralConversion(
    String claimToken,
  ) async {
    try {
      final response = await _client.call(
        'process_investor_referral_conversion',
        parameters: <String, dynamic>{'p_claim_token': claimToken},
      );
      final rows = response is List ? response : <dynamic>[response];
      if (rows.length != 1 || rows.single is! Map) {
        throw const ReferralRepositoryException();
      }

      final row = Map<String, dynamic>.from(rows.single as Map);
      final replayed = row['replayed'];
      final rewardEntitlementCount = row['reward_entitlement_count'];
      if (replayed is! bool || rewardEntitlementCount is! int) {
        throw const ReferralRepositoryException();
      }

      return ReferralConversionResult(
        replayed: replayed,
        rewardEntitlementCount: rewardEntitlementCount,
      );
    } on ReferralRepositoryException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ReferralRepositoryException(
        'Referral attribution could not be applied.',
        _failureForMessage(error.message),
      );
    } catch (_) {
      throw const ReferralRepositoryException();
    }
  }

  ReferralRepositoryFailure _failureForMessage(String message) {
    return switch (message) {
      'referral_code_invalid' ||
      'referral_code_required' =>
        ReferralRepositoryFailure.invalidCode,
      'referral_claim_invalid' ||
      'referral_claim_required' =>
        ReferralRepositoryFailure.invalidClaim,
      'referral_claim_account_predates_capture' =>
        ReferralRepositoryFailure.accountPredatesClaim,
      'referral_claim_account_conflict' =>
        ReferralRepositoryFailure.claimAccountConflict,
      'referral_claim_consumption_conflict' =>
        ReferralRepositoryFailure.claimConsumptionConflict,
      'referral_self_not_allowed' => ReferralRepositoryFailure.selfReferral,
      'referral_conversion_conflict' => ReferralRepositoryFailure.conflict,
      'referral_code_inactive' => ReferralRepositoryFailure.inactiveCode,
      'referral_investor_not_eligible' =>
        ReferralRepositoryFailure.ineligibleInvestor,
      'referral_profile_not_resolved' =>
        ReferralRepositoryFailure.profileNotResolved,
      _ => ReferralRepositoryFailure.unknown,
    };
  }
}
