import '../../investor_identity/models/user_account.dart';

enum ProtectedDestination {
  advisorDashboard,
  investorDashboard,
  explorer,
  portfolioLinking,
}

class AccountStateResolver {
  const AccountStateResolver();

  ProtectedDestination resolve(AccountState state) {
    switch (state) {
      case AccountState.advisor:
        return ProtectedDestination.advisorDashboard;
      case AccountState.linkedInvestor:
        return ProtectedDestination.investorDashboard;
      case AccountState.explorer:
        return ProtectedDestination.explorer;
      case AccountState.linkPending:
        return ProtectedDestination.portfolioLinking;
    }
  }
}
