import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/investor_account_link.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_account.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/workspace_membership.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/advisor_investor_assignment.dart';

void main() {
  test('ended and unknown memberships cannot appear active', () {
    final row = <String, dynamic>{
      'id': 'membership',
      'workspace_id': 'A',
      'profile_id': 'advisor',
      'role': 'advisor',
      'status': 'active',
      'joined_at': '2026-10-01T00:00:00Z',
      'created_at': '2026-10-01T00:00:00Z',
    };
    expect(WorkspaceMembership.fromJson(row).isActive, isTrue);
    expect(
        WorkspaceMembership.fromJson(
            {...row, 'ended_at': '2026-10-02T00:00:00Z'}).isActive,
        isFalse);
    expect(
        WorkspaceMembership.fromJson({...row, 'status': 'future_status'})
            .isActive,
        isFalse);
    expect(WorkspaceMembership.fromJson({...row, 'status': null}).isActive,
        isFalse);
  });

  test('assignment needs workspace provenance and a live relationship', () {
    final row = <String, dynamic>{
      'id': 'assignment',
      'workspace_id': 'A',
      'advisor_id': 'advisor',
      'investor_id': 'investor',
      'status': 'active',
      'assigned_at': '2026-10-01T00:00:00Z',
      'created_at': '2026-10-01T00:00:00Z',
    };
    final active = AdvisorInvestorAssignment.fromJson(row);
    expect(active.isActive, isTrue);
    expect(active.toJson()['workspace_id'], 'A');
    expect(
        AdvisorInvestorAssignment.fromJson({...row, 'workspace_id': null})
            .isActive,
        isFalse);
    expect(
        AdvisorInvestorAssignment.fromJson(
            {...row, 'ended_at': '2026-10-02T00:00:00Z'}).isActive,
        isFalse);
    expect(
        AdvisorInvestorAssignment.fromJson({...row, 'status': 'future_status'})
            .isActive,
        isFalse);
  });

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
