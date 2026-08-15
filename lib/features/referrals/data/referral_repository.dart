import '../domain/investor_referral.dart';

abstract class ReferralRepository {
  Future<InvestorReferral> getOrCreateCurrentInvestorReferral();
}

class ReferralRepositoryException implements Exception {
  const ReferralRepositoryException([this.message = 'Referral unavailable']);

  final String message;

  @override
  String toString() => message;
}
