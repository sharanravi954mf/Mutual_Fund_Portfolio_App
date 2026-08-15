import '../domain/investor_referral.dart';

abstract class ReferralRepository {
  Future<InvestorReferral> getOrCreateCurrentInvestorReferral();

  Future<String> createReferralOnboardingClaim(String referralCode);

  Future<void> bindCurrentUserReferralOnboardingClaim(String claimToken);

  Future<ReferralConversionResult> processCurrentInvestorReferralConversion(
    String claimToken,
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
        ReferralRepositoryFailure.invalidClaim ||
        ReferralRepositoryFailure.accountPredatesClaim ||
        ReferralRepositoryFailure.claimAccountConflict ||
        ReferralRepositoryFailure.claimConsumptionConflict ||
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
  invalidClaim,
  accountPredatesClaim,
  claimAccountConflict,
  claimConsumptionConflict,
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
