import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_profile.dart';
import 'package:mutual_fund_portfolio_app/features/referrals/application/referral_attribution_controller.dart';
import 'package:mutual_fund_portfolio_app/features/referrals/data/referral_repository.dart';
import 'package:mutual_fund_portfolio_app/features/referrals/domain/investor_referral.dart';
import 'package:mutual_fund_portfolio_app/features/referrals/presentation/referral_join_route.dart';

void main() {
  group('ReferralJoinRoute', () {
    test('captures the one opaque ref value from the real join route', () {
      const code = 'opaque+/=? value';
      final route = Uri(
        path: '/join',
        queryParameters: const <String, String>{'ref': code},
      ).toString();

      expect(ReferralJoinRoute.referralCodeFrom(route), code);
      expect(route, isNot(contains('profile_id')));
      expect(route, isNot(contains('user_id')));
    });

    test('rejects unrelated, empty, duplicate, and oversized routes', () {
      expect(ReferralJoinRoute.referralCodeFrom('/'), isNull);
      expect(ReferralJoinRoute.referralCodeFrom('/join'), isNull);
      expect(ReferralJoinRoute.referralCodeFrom('/join?ref='), isNull);
      expect(
        ReferralJoinRoute.referralCodeFrom('/join?ref=first&ref=second'),
        isNull,
      );
      expect(
        ReferralJoinRoute.referralCodeFrom('/join?ref=${'a' * 513}'),
        isNull,
      );
    });
  });

  group('ReferralAttributionController', () {
    test('waits for canonical profile then invokes conversion exactly once',
        () async {
      final repository = _FakeRepository();
      final controller = ReferralAttributionController(repository: repository);

      controller.capture('opaque-code');
      await controller.synchronize(userId: null, profile: null);
      await controller.synchronize(userId: 'user-a', profile: null);
      expect(repository.codes, isEmpty);
      expect(controller.pendingCode, 'opaque-code');

      final profile = _profile('profile-a');
      await controller.synchronize(userId: 'user-a', profile: profile);
      await controller.synchronize(userId: 'user-a', profile: profile);

      expect(repository.codes, <String>['opaque-code']);
      expect(controller.pendingCode, isNull);
      expect(controller.state, ReferralAttributionState.applied);
    });

    test('treats an idempotent server replay as terminal success', () async {
      final repository = _FakeRepository(replayed: true);
      final controller = ReferralAttributionController(repository: repository)
        ..capture('opaque-code');

      await controller.synchronize(
        userId: 'user-a',
        profile: _profile('profile-a'),
      );

      expect(controller.state, ReferralAttributionState.replayed);
      expect(controller.pendingCode, isNull);
    });

    for (final failure in <ReferralRepositoryFailure>[
      ReferralRepositoryFailure.invalidCode,
      ReferralRepositoryFailure.selfReferral,
      ReferralRepositoryFailure.conflict,
      ReferralRepositoryFailure.inactiveCode,
      ReferralRepositoryFailure.ineligibleInvestor,
    ]) {
      test('clears the token after terminal $failure', () async {
        final controller = ReferralAttributionController(
          repository: _FakeRepository(failure: failure),
        )..capture('opaque-code');

        await controller.synchronize(
          userId: 'user-a',
          profile: _profile('profile-a'),
        );

        expect(controller.state, ReferralAttributionState.rejected);
        expect(controller.failure, failure);
        expect(controller.pendingCode, isNull);
      });
    }

    test('retains retryable failures without interrupting onboarding',
        () async {
      final repository = _FakeRepository(
        failure: ReferralRepositoryFailure.profileNotResolved,
      );
      final controller = ReferralAttributionController(repository: repository)
        ..capture('opaque-code');

      await controller.synchronize(
        userId: 'user-a',
        profile: _profile('profile-a'),
      );

      expect(controller.state, ReferralAttributionState.retryableFailure);
      expect(controller.pendingCode, 'opaque-code');
    });

    test('never carries a bound token into another authenticated session',
        () async {
      final repository = _FakeRepository();
      final controller = ReferralAttributionController(repository: repository)
        ..capture('opaque-code');

      await controller.synchronize(userId: 'user-a', profile: null);
      await controller.synchronize(
        userId: 'user-b',
        profile: _profile('profile-b'),
      );

      expect(controller.pendingCode, isNull);
      expect(controller.state, ReferralAttributionState.idle);
      expect(repository.codes, isEmpty);
    });

    test('rejects a resolved non-Investor without calling the RPC', () async {
      final repository = _FakeRepository();
      final controller = ReferralAttributionController(repository: repository)
        ..capture('opaque-code');

      await controller.synchronize(
        userId: 'user-a',
        profile: _profile('profile-a', role: UserRole.advisor),
      );

      expect(controller.state, ReferralAttributionState.rejected);
      expect(repository.codes, isEmpty);
      expect(controller.pendingCode, isNull);
    });
  });
}

UserProfile _profile(String id, {UserRole role = UserRole.investor}) {
  return UserProfile(
    id: id,
    role: role,
    accountStatus: AccountStatus.active,
    createdAt: DateTime.utc(2026, 8, 15),
    updatedAt: DateTime.utc(2026, 8, 15),
  );
}

class _FakeRepository implements ReferralRepository {
  _FakeRepository({this.replayed = false, this.failure});

  final bool replayed;
  final ReferralRepositoryFailure? failure;
  final List<String> codes = <String>[];

  @override
  Future<InvestorReferral> getOrCreateCurrentInvestorReferral() {
    throw UnimplementedError();
  }

  @override
  Future<ReferralConversionResult> processCurrentInvestorReferralConversion(
    String referralCode,
  ) async {
    codes.add(referralCode);
    final failure = this.failure;
    if (failure != null) {
      throw ReferralRepositoryException('test failure', failure);
    }
    return ReferralConversionResult(
      replayed: replayed,
      rewardEntitlementCount: 2,
    );
  }
}
