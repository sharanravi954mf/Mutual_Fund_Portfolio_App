import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/data/identity_repository.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/models/identity_bootstrap_result.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/services/account_state_resolver.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/services/identity_bootstrap_service.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/services/identity_verification_service.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/services/onboarding_coordinator.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_account.dart';

void main() {
  group('AccountStateResolver', () {
    const resolver = AccountStateResolver();

    test('routes every protected account state centrally', () {
      expect(
        resolver.resolve(AccountState.advisor),
        ProtectedDestination.advisorDashboard,
      );
      expect(
        resolver.resolve(AccountState.linkedInvestor),
        ProtectedDestination.investorDashboard,
      );
      expect(
        resolver.resolve(AccountState.explorer),
        ProtectedDestination.explorer,
      );
      expect(
        resolver.resolve(AccountState.linkPending),
        ProtectedDestination.portfolioLinking,
      );
    });
  });

  group('IdentityBootstrapService', () {
    test('preserves an existing linked investor', () async {
      final result = await IdentityBootstrapService(
        _FakeIdentityRepository(_result(
            AccountState.linkedInvestor, IdentityResolution.existingLink)),
      ).load();

      expect(result.account.accountState, AccountState.linkedInvestor);
      expect(result.resolution, IdentityResolution.existingLink);
    });

    test('accepts a safe automatic link result', () async {
      final result = await IdentityBootstrapService(
        _FakeIdentityRepository(_result(
            AccountState.linkedInvestor, IdentityResolution.automaticLink)),
      ).load();

      expect(result.account.accountState, AccountState.linkedInvestor);
      expect(result.resolution, IdentityResolution.automaticLink);
    });

    test('routes zero and multiple matches to link pending', () async {
      for (final resolution in [
        IdentityResolution.noMatch,
        IdentityResolution.ambiguousMatch,
      ]) {
        final result = await IdentityBootstrapService(
          _FakeIdentityRepository(
              _result(AccountState.linkPending, resolution)),
        ).load();

        expect(result.account.accountState, AccountState.linkPending);
        expect(result.resolution, resolution);
      }
    });
  });

  test('OnboardingCoordinator records only approved pending-account choices',
      () async {
    final repository = _FakeIdentityRepository(
      _result(AccountState.linkPending, IdentityResolution.noMatch),
    );
    final coordinator = OnboardingCoordinator(
      repository: repository,
      verificationService: const PlaceholderIdentityVerificationService(),
    );

    final explorer = await coordinator.chooseExplorer();
    expect(explorer.accountState, AccountState.explorer);
    expect(repository.choice, AccountState.explorer);

    final pending = await coordinator.choosePortfolioLinking();
    expect(pending.accountState, AccountState.linkPending);
    expect(repository.choice, AccountState.linkPending);
    expect(coordinator.verificationMethods(), hasLength(3));
  });
}

IdentityBootstrapResult _result(
    AccountState state, IdentityResolution resolution) {
  final now = DateTime.utc(2026, 7, 22);
  return IdentityBootstrapResult(
    account: UserAccount(
      userId: 'user-id',
      accountState: state,
      onboardingCompleted: state != AccountState.linkPending,
      createdAt: now,
      updatedAt: now,
    ),
    resolution: resolution,
  );
}

class _FakeIdentityRepository implements IdentityRepository {
  _FakeIdentityRepository(this.result);

  final IdentityBootstrapResult result;
  AccountState? choice;

  @override
  Future<IdentityBootstrapResult> bootstrap() async => result;

  @override
  Future<UserAccount> completeOnboardingChoice(
      AccountState accountState) async {
    choice = accountState;
    return UserAccount(
      userId: result.account.userId,
      accountState: accountState,
      onboardingCompleted: true,
      createdAt: result.account.createdAt,
      updatedAt: result.account.updatedAt,
    );
  }
}
