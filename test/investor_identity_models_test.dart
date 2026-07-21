import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/investor_account_link.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_account.dart';

void main() {
  test('maps every account state to its database value', () {
    for (final state in AccountState.values) {
      expect(AccountState.fromDatabase(state.databaseValue), state);
    }
  });

  test('maps a user account with an optional login timestamp', () {
    final account = UserAccount.fromJson({
      'user_id': 'auth-user-id',
      'account_state': 'linked_investor',
      'onboarding_completed': true,
      'last_login_at': '2026-07-22T10:00:00.000Z',
      'created_at': '2026-07-21T10:00:00.000Z',
      'updated_at': '2026-07-22T10:00:00.000Z',
    });

    expect(account.accountState, AccountState.linkedInvestor);
    expect(account.onboardingCompleted, isTrue);
    expect(account.lastLoginAt, isNotNull);
  });

  test('maps an active investor account link', () {
    final link = InvestorAccountLink.fromJson({
      'id': 'link-id',
      'user_id': 'auth-user-id',
      'profile_id': 'business-profile-id',
      'verification_method': 'legacy_migration',
      'verified_at': null,
      'linked_at': '2026-07-22T10:00:00.000Z',
      'link_status': 'active',
      'created_at': '2026-07-22T10:00:00.000Z',
      'updated_at': '2026-07-22T10:00:00.000Z',
    });

    expect(link.linkStatus, InvestorLinkStatus.active);
    expect(link.profileId, 'business-profile-id');
  });
}
