import '../../investor_identity/models/user_account.dart';

class PortfolioAccessDeniedException implements Exception {
  const PortfolioAccessDeniedException();
}

class InvestorPortfolioData {
  const InvestorPortfolioData({
    required this.portfolio,
    required this.transactions,
    required this.allFunds,
    required this.profile,
  });

  final Map<String, dynamic>? portfolio;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> allFunds;
  final Map<String, dynamic>? profile;
}

abstract class PortfolioRepository {
  Future<InvestorPortfolioData> loadCurrentInvestorPortfolio();
}

class PortfolioAccessPolicy {
  const PortfolioAccessPolicy();

  bool canLoadInvestorPortfolio(AccountState accountState) {
    return accountState == AccountState.linkedInvestor;
  }

  bool canAccessAllPortfolios(AccountState accountState) {
    return accountState == AccountState.advisor;
  }
}

class InvestorOwnershipResolver {
  const InvestorOwnershipResolver();

  String resolveActiveProfileId({
    required AccountState accountState,
    required List<Map<String, dynamic>> links,
  }) {
    if (accountState != AccountState.linkedInvestor || links.length != 1) {
      throw const PortfolioAccessDeniedException();
    }
    final profileId = links.single['profile_id'] as String?;
    if (profileId == null || profileId.isEmpty) {
      throw const PortfolioAccessDeniedException();
    }
    return profileId;
  }
}
