import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_account.dart';
import 'package:mutual_fund_portfolio_app/features/portfolio/data/portfolio_repository.dart';

void main() {
  const policy = PortfolioAccessPolicy();
  const resolver = InvestorOwnershipResolver();

  test('Explorer cannot load a portfolio', () {
    expect(policy.canLoadInvestorPortfolio(AccountState.explorer), isFalse);
  });

  test('Link Pending cannot load a portfolio', () {
    expect(policy.canLoadInvestorPortfolio(AccountState.linkPending), isFalse);
  });

  test('Linked Investor can resolve exactly one active profile', () {
    final profileId = resolver.resolveActiveProfileId(
      accountState: AccountState.linkedInvestor,
      links: [
        {'profile_id': 'profile-1'},
      ],
    );

    expect(profileId, 'profile-1');
    expect(
        policy.canLoadInvestorPortfolio(AccountState.linkedInvestor), isTrue);
  });

  test('Advisor can access all portfolios through the Advisor policy', () {
    expect(policy.canAccessAllPortfolios(AccountState.advisor), isTrue);
    expect(policy.canLoadInvestorPortfolio(AccountState.advisor), isFalse);
  });

  test('Revoked links and no active link deny Investor portfolio access', () {
    expect(
      () => resolver.resolveActiveProfileId(
        accountState: AccountState.linkedInvestor,
        links: const [],
      ),
      throwsA(isA<PortfolioAccessDeniedException>()),
    );
  });

  test('Multiple historical active links are denied defensively', () {
    expect(
      () => resolver.resolveActiveProfileId(
        accountState: AccountState.linkedInvestor,
        links: [
          {'profile_id': 'profile-1'},
          {'profile_id': 'profile-2'},
        ],
      ),
      throwsA(isA<PortfolioAccessDeniedException>()),
    );
  });

  test('Logout state cannot resolve ownership', () {
    expect(
      () => resolver.resolveActiveProfileId(
        accountState: AccountState.explorer,
        links: [
          {'profile_id': 'profile-1'},
        ],
      ),
      throwsA(isA<PortfolioAccessDeniedException>()),
    );
  });
}
