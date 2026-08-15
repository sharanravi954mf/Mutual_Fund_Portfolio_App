import 'dart:async';

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
    test('creates a pre-auth claim, binds it, then converts after profile',
        () async {
      final repository = _FakeRepository();
      final controller = _controller(repository);

      controller.capture('opaque-code');
      await controller.synchronize(userId: null, profile: null);
      expect(repository.createdCodes, <String>['opaque-code']);
      expect(repository.boundClaims, isEmpty);
      expect(controller.pendingCode, isNull);
      expect(controller.hasPendingAttribution, isTrue);

      await controller.synchronize(userId: 'user-a', profile: null);
      expect(repository.boundClaims, <String>['server-claim']);
      expect(repository.convertedClaims, isEmpty);

      final profile = _profile('profile-a');
      await controller.synchronize(userId: 'user-a', profile: profile);
      await controller.synchronize(userId: 'user-a', profile: profile);

      expect(repository.convertedClaims, <String>['server-claim']);
      expect(controller.hasPendingAttribution, isFalse);
      expect(controller.state, ReferralAttributionState.applied);
    });

    test('treats an idempotent server replay as terminal success', () async {
      final repository = _FakeRepository(replayed: true);
      final controller = _controller(repository)..capture('opaque-code');

      await controller.synchronize(
        userId: 'user-a',
        profile: _profile('profile-a'),
      );

      expect(controller.state, ReferralAttributionState.replayed);
      expect(controller.hasPendingAttribution, isFalse);
    });

    for (final failure in <ReferralRepositoryFailure>[
      ReferralRepositoryFailure.invalidClaim,
      ReferralRepositoryFailure.accountPredatesClaim,
      ReferralRepositoryFailure.claimAccountConflict,
      ReferralRepositoryFailure.claimConsumptionConflict,
      ReferralRepositoryFailure.selfReferral,
      ReferralRepositoryFailure.conflict,
      ReferralRepositoryFailure.inactiveCode,
      ReferralRepositoryFailure.ineligibleInvestor,
    ]) {
      test('clears the claim after terminal $failure', () async {
        final repository = _FakeRepository(conversionFailure: failure);
        final controller = _controller(repository)..capture('opaque-code');

        await controller.synchronize(
          userId: 'user-a',
          profile: _profile('profile-a'),
        );

        expect(controller.state, ReferralAttributionState.rejected);
        expect(controller.failure, failure);
        expect(controller.hasPendingAttribution, isFalse);
        expect(repository.conversionCalls, 1);
      });
    }

    test('invalid public code stops before authentication or binding',
        () async {
      final repository = _FakeRepository(
        createFailure: ReferralRepositoryFailure.invalidCode,
      );
      final controller = _controller(repository)..capture('bad-code');

      await controller.synchronize(userId: null, profile: null);

      expect(controller.state, ReferralAttributionState.rejected);
      expect(repository.createCalls, 1);
      expect(repository.bindCalls, 0);
      expect(controller.hasPendingAttribution, isFalse);
    });

    test('retries one transient conversion failure then succeeds', () async {
      final delays = <Duration>[];
      final repository = _FakeRepository(conversionFailuresRemaining: 1);
      final controller = ReferralAttributionController(
        repository: repository,
        retryBaseDelay: const Duration(milliseconds: 10),
        retryDelay: (delay) async => delays.add(delay),
      )..capture('opaque-code');

      await controller.synchronize(
        userId: 'user-a',
        profile: _profile('profile-a'),
      );

      expect(repository.conversionCalls, 2);
      expect(delays, <Duration>[const Duration(milliseconds: 10)]);
      expect(controller.state, ReferralAttributionState.applied);
      expect(controller.hasPendingAttribution, isFalse);
    });

    test('concurrent synchronize calls share one bounded retry sequence',
        () async {
      final retryGate = Completer<void>();
      final repository = _FakeRepository(conversionFailuresRemaining: 1);
      final controller = ReferralAttributionController(
        repository: repository,
        retryDelay: (_) => retryGate.future,
      )..capture('opaque-code');

      final first = controller.synchronize(
        userId: 'user-a',
        profile: _profile('profile-a'),
      );
      await repository.firstConversionFailure.future;
      final second = controller.synchronize(
        userId: 'user-a',
        profile: _profile('profile-a'),
      );

      expect(repository.conversionCalls, 1);
      retryGate.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(repository.conversionCalls, 2);
      expect(repository.maxConcurrentConversions, 1);
      expect(controller.state, ReferralAttributionState.applied);
    });

    test('terminal rejection is never retried', () async {
      var delayCalls = 0;
      final repository = _FakeRepository(
        conversionFailure: ReferralRepositoryFailure.invalidClaim,
      );
      final controller = ReferralAttributionController(
        repository: repository,
        retryDelay: (_) async => delayCalls++,
      )..capture('opaque-code');

      await controller.synchronize(
        userId: 'user-a',
        profile: _profile('profile-a'),
      );

      expect(repository.conversionCalls, 1);
      expect(delayCalls, 0);
      expect(controller.state, ReferralAttributionState.rejected);
    });

    test('successful application remains exactly once under concurrent calls',
        () async {
      final processGate = Completer<void>();
      final repository = _FakeRepository(processGate: processGate);
      final controller = _controller(repository)..capture('opaque-code');

      final first = controller.synchronize(
        userId: 'user-a',
        profile: _profile('profile-a'),
      );
      await repository.processStarted.future;
      final second = controller.synchronize(
        userId: 'user-a',
        profile: _profile('profile-a'),
      );
      expect(repository.conversionCalls, 1);

      processGate.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(repository.conversionCalls, 1);
      expect(controller.state, ReferralAttributionState.applied);
    });

    test('logout and account change clear a server-bound referral', () async {
      final logoutRepository = _FakeRepository();
      final logoutController = _controller(logoutRepository)
        ..capture('logout-code');
      await logoutController.synchronize(userId: 'user-a', profile: null);
      expect(logoutController.boundUserId, 'user-a');
      await logoutController.synchronize(userId: null, profile: null);
      expect(logoutController.hasPendingAttribution, isFalse);
      expect(logoutController.state, ReferralAttributionState.idle);

      final changeRepository = _FakeRepository();
      final changeController = _controller(changeRepository)
        ..capture('change-code');
      await changeController.synchronize(userId: 'user-a', profile: null);
      await changeController.synchronize(
        userId: 'user-b',
        profile: _profile('profile-b'),
      );
      expect(changeController.hasPendingAttribution, isFalse);
      expect(changeRepository.conversionCalls, 0);
    });

    test('rejects a resolved non-Investor without conversion', () async {
      final repository = _FakeRepository();
      final controller = _controller(repository)..capture('opaque-code');

      await controller.synchronize(
        userId: 'user-a',
        profile: _profile('profile-a', role: UserRole.advisor),
      );

      expect(controller.state, ReferralAttributionState.rejected);
      expect(repository.conversionCalls, 0);
      expect(controller.hasPendingAttribution, isFalse);
    });
  });
}

ReferralAttributionController _controller(_FakeRepository repository) =>
    ReferralAttributionController(
      repository: repository,
      retryDelay: (_) async {},
    );

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
  _FakeRepository({
    this.replayed = false,
    this.createFailure,
    this.conversionFailure,
    this.conversionFailuresRemaining = 0,
    this.processGate,
  });

  final bool replayed;
  final ReferralRepositoryFailure? createFailure;
  final ReferralRepositoryFailure? conversionFailure;
  int conversionFailuresRemaining;
  final Completer<void>? processGate;
  final Completer<void> processStarted = Completer<void>();
  final Completer<void> firstConversionFailure = Completer<void>();
  final List<String> createdCodes = <String>[];
  final List<String> boundClaims = <String>[];
  final List<String> convertedClaims = <String>[];
  int createCalls = 0;
  int bindCalls = 0;
  int conversionCalls = 0;
  int _activeConversions = 0;
  int maxConcurrentConversions = 0;

  @override
  Future<String> createReferralOnboardingClaim(String referralCode) async {
    createCalls++;
    createdCodes.add(referralCode);
    final failure = createFailure;
    if (failure != null) {
      throw ReferralRepositoryException('test failure', failure);
    }
    return 'server-claim';
  }

  @override
  Future<void> bindCurrentUserReferralOnboardingClaim(String claimToken) async {
    bindCalls++;
    boundClaims.add(claimToken);
  }

  @override
  Future<InvestorReferral> getOrCreateCurrentInvestorReferral() {
    throw UnimplementedError();
  }

  @override
  Future<ReferralConversionResult> processCurrentInvestorReferralConversion(
    String claimToken,
  ) async {
    conversionCalls++;
    convertedClaims.add(claimToken);
    _activeConversions++;
    if (_activeConversions > maxConcurrentConversions) {
      maxConcurrentConversions = _activeConversions;
    }
    if (!processStarted.isCompleted) processStarted.complete();
    try {
      if (conversionFailuresRemaining > 0) {
        conversionFailuresRemaining--;
        if (!firstConversionFailure.isCompleted) {
          firstConversionFailure.complete();
        }
        throw const ReferralRepositoryException();
      }
      final failure = conversionFailure;
      if (failure != null) {
        throw ReferralRepositoryException('test failure', failure);
      }
      final gate = processGate;
      if (gate != null) await gate.future;
      return ReferralConversionResult(
        replayed: replayed,
        rewardEntitlementCount: 2,
      );
    } finally {
      _activeConversions--;
    }
  }
}
