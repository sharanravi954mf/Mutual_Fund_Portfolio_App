import '../domain/investor_referral.dart';

abstract class ReferralRepository {
  Future<InvestorReferral> getOrCreateCurrentInvestorReferral();

  Future<ReferralConversionResult> processCurrentInvestorReferralConversion(
    String referralCode,
  );
}

class ReferralRepositoryException implements Exception {
  const ReferralRepositoryException([
    this.message = 'Referral unavailable',
    this.reason = ReferralRepositoryFailure.unknown,
  ]);

  final String message;
  final ReferralRepositoryFailure reason;

  bool get isTerminal => switch (reason) {
        ReferralRepositoryFailure.invalidCode ||
        ReferralRepositoryFailure.selfReferral ||
        ReferralRepositoryFailure.conflict ||
        ReferralRepositoryFailure.inactiveCode ||
        ReferralRepositoryFailure.ineligibleInvestor =>
          true,
        ReferralRepositoryFailure.profileNotResolved ||
        ReferralRepositoryFailure.unknown =>
          false,
      };

  @override
  String toString() => message;
}

enum ReferralRepositoryFailure {
  invalidCode,
  selfReferral,
  conflict,
  inactiveCode,
  ineligibleInvestor,
  profileNotResolved,
  unknown,
}

class ReferralConversionResult {
  const ReferralConversionResult({
    required this.replayed,
    required this.rewardEntitlementCount,
  });

  final bool replayed;
  final int rewardEntitlementCount;
}
