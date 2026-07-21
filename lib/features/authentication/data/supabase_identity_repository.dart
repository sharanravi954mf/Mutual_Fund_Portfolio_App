import 'package:supabase_flutter/supabase_flutter.dart';

import '../../investor_identity/models/user_account.dart';
import '../models/identity_bootstrap_result.dart';
import 'identity_repository.dart';

class SupabaseIdentityRepository implements IdentityRepository {
  SupabaseIdentityRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<IdentityBootstrapResult> bootstrap() async {
    final response = await _client.rpc('bootstrap_identity');
    final row = _singleRow(response);
    return IdentityBootstrapResult(
      account: _accountFromRow(row),
      resolution: IdentityResolution.fromDatabase(row['resolution'] as String),
    );
  }

  @override
  Future<UserAccount> completeOnboardingChoice(
      AccountState accountState) async {
    if (accountState != AccountState.explorer &&
        accountState != AccountState.linkPending) {
      throw ArgumentError.value(
        accountState,
        'accountState',
        'Only Explorer or Link Pending may be selected during onboarding',
      );
    }

    await _client.rpc(
      'complete_onboarding_choice',
      params: {'choice': accountState.databaseValue},
    );

    final bootstrap = await this.bootstrap();
    return bootstrap.account;
  }

  Map<String, dynamic> _singleRow(dynamic response) {
    if (response is List && response.length == 1 && response.single is Map) {
      return Map<String, dynamic>.from(response.single as Map);
    }
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    throw StateError('Identity service returned an unexpected response.');
  }

  UserAccount _accountFromRow(Map<String, dynamic> row) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No authenticated user is available.');
    }
    final now = DateTime.now().toUtc();
    return UserAccount(
      userId: userId,
      accountState: AccountState.fromDatabase(row['account_state'] as String),
      onboardingCompleted: row['onboarding_completed'] as bool,
      createdAt: now,
      updatedAt: now,
    );
  }
}
