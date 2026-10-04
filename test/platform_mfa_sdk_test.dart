import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/services/auth_session_fence.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/mfa_repository.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/mfa_models.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'support/platform_mfa_fakes.dart';

const actorA = 'aa000000-0000-0000-0000-000000000001';
const actorB = 'bb000000-0000-0000-0000-000000000002';
Map<String, dynamic> factorJson({bool verified = true}) => {
      'id': 'factor-1',
      'factor_type': 'totp',
      'status': verified ? 'verified' : 'unverified',
      'created_at': '2026-10-04T00:00:00Z',
      'updated_at': '2026-10-04T00:00:00Z'
    };
Map<String, dynamic> sdkSession(String user,
        {bool aal2 = false, bool factor = true, bool factorVerified = true}) =>
    {
      'access_token': 'synthetic.${base64Url.encode(utf8.encode(jsonEncode({
                'sub': user,
                'aal': aal2 ? 'aal2' : 'aal1',
                'session_id': 'synthetic-session-$user',
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              }))).replaceAll('=', '')}.signature',
      'refresh_token': 'synthetic-refresh-$user-${aal2 ? 2 : 1}',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': user,
        'aud': 'authenticated',
        'created_at': '2026-10-04T00:00:00Z',
        'email': 'synthetic@example.test',
        'app_metadata': {},
        'user_metadata': {},
        'factors': factor ? [factorJson(verified: factorVerified)] : []
      }
    };
Future<void> flushSdk() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class SdkFixture {
  late final AuthSessionFence fence;
  late final SupabaseClient client;
  late final AuthProvider auth;
  late final SupabaseMfaRepository repo;
  bool forceServerAssurance = false;
  bool platformAdmin = true, factorVerified = true;
  String signInActor = actorB;
  bool aal2 = false,
      serverDenies = false,
      hasFactor = true,
      failProjection = false;
  int refreshes = 0, verifies = 0, enrolls = 0, projections = 0, bootstraps = 0;
  Completer<void>? verifyWait, refreshWait, projectionWait;
  Completer<void>? verifyStarted, refreshStarted, projectionStarted;
  int verifyStatus = 200;
  String verifyError = 'mfa_verification_failed';
  Future<void> init() async {
    fence = AuthSessionFence(
        supabaseUrl: 'https://synthetic.invalid',
        inner: MockClient((request) async {
          expect(request.url.host, 'synthetic.invalid');
          final path = request.url.path;
          Object body = {};
          int status = 200;
          if (path.endsWith('/logout')) {
            body = {};
          } else if (path.endsWith('/token')) {
            if (request.url.queryParameters['grant_type'] == 'refresh_token') {
              refreshes++;
              refreshStarted?.complete();
              refreshStarted = null;
              final snapshot = sdkSession(client.auth.currentUser?.id ?? actorA,
                  aal2: aal2,
                  factor: hasFactor,
                  factorVerified: factorVerified);
              final wait = refreshWait;
              refreshWait = null;
              if (wait != null) await wait.future;
              body = snapshot;
            } else {
              body = sdkSession(signInActor);
            }
          } else if (path.endsWith('/factors')) {
            enrolls++;
            hasFactor = true;
            factorVerified = false;
            expect(jsonDecode(request.body)['factor_type'], 'totp');
            body = {
              'id': 'factor-1',
              'type': 'totp',
              'totp': {
                'qr_code': '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
                'secret': syntheticSecret,
                'uri': syntheticUri.replaceAll('MoneyBowl%20DEV', 'MoneyBowl')
              }
            };
          } else if (path.endsWith('/challenge')) {
            body = {
              'id': 'challenge-1',
              'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30
            };
          } else if (path.endsWith('/verify')) {
            verifies++;
            expect(jsonDecode(request.body)['code'], '001234');
            expect(jsonDecode(request.body)['challenge_id'], 'challenge-1');
            verifyStarted?.complete();
            verifyStarted = null;
            final wait = verifyWait;
            verifyWait = null;
            if (wait != null) await wait.future;
            status = verifyStatus;
            if (status == 200) {
              aal2 = true;
              factorVerified = true;
              body = sdkSession(actorA, aal2: true);
            } else {
              body = {'code': verifyError, 'message': 'synthetic safe error'};
            }
          } else if (path.endsWith('/get_my_platform_context')) {
            projections++;
            final deny = serverDenies,
                fail = failProjection,
                admin = platformAdmin;
            final assured =
                client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
                    AuthenticatorAssuranceLevels.aal2;
            projectionStarted?.complete();
            projectionStarted = null;
            final wait = projectionWait;
            projectionWait = null;
            if (wait != null) await wait.future;
            status = fail ? 403 : 200;
            body = fail
                ? {'message': 'denied', 'code': '42501'}
                : {
                    'is_platform_admin': admin,
                    'capabilities': [if (admin) 'mfd_applications.review'],
                    'step_up_verified':
                        (assured || forceServerAssurance) && !deny && admin,
                    'mfa_enrolled': hasFactor
                  };
          } else if (path.endsWith('/bootstrap_identity')) {
            bootstraps++;
            body = [
              {
                'account_state': 'explorer',
                'onboarding_completed': true,
                'resolution': 'no_match'
              }
            ];
          } else {
            throw StateError('Unexpected mocked request path');
          }
          return http.Response(jsonEncode(body), status,
              request: request,
              headers: {
                'content-type': 'application/json',
                'x-supabase-api-version': '2024-01-01',
                if (status == 429) 'retry-after': '60'
              });
        }));
    client = SupabaseClient('https://synthetic.invalid', 'synthetic-public-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: fence);
    fence.attach(client);
    await client.auth
        .recoverSession(jsonEncode(sdkSession(actorA, factor: hasFactor)));
    auth = AuthProvider(client: client);
    await flushSdk();
    repo = SupabaseMfaRepository(client, auth);
  }

  Future<void> dispose() async {
    auth.dispose();
    await client.dispose();
    fence.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SdkFixture f;
  setUp(() async {
    f = SdkFixture();
    await f.init();
  });
  tearDown(() async => f.dispose());
  test(
      'real SDK verify installs AAL2 and emits event; focused projection confirms',
      () async {
    final events = <AuthChangeEvent>[];
    final sub =
        f.client.auth.onAuthStateChange.listen((s) => events.add(s.event));
    expect(await f.client.rpc('get_my_platform_context'), isA<Map>());
    expect(f.auth.errorMessage, isNull);
    expect(f.auth.platformContextCurrent, true);
    final before = f.bootstraps;
    await f.repo.inspect();
    await f.repo.verify('factor-1', '001234');
    final status = await f.repo.inspect();
    await flushSdk();
    expect(status.confirmed, true);
    expect(f.auth.platformContext.stepUpVerified, true);
    expect(events, contains(AuthChangeEvent.mfaChallengeVerified));
    expect(f.client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel,
        AuthenticatorAssuranceLevels.aal2);
    expect(f.enrolls, 0);
    expect(f.bootstraps, before);
    expect(f.refreshes, 2);
    await sub.cancel();
  });
  test('SDK listFactors and tokenRefreshed have no recursive factor refresh',
      () async {
    final before = f.bootstraps;
    await f.repo.inspect();
    await flushSdk();
    expect(f.refreshes, 1);
    expect(f.projections, lessThanOrEqualTo(4));
    expect(f.bootstraps, before);
  });
  test('SDK enrollment accepts prefixed SVG but renders validated returned URI',
      () async {
    final setup = await f.repo.enroll();
    expect(setup.uri, startsWith('otpauth://totp/'));
    expect(setup.toString(), isNot(contains(syntheticSecret)));
    expect(f.client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel,
        AuthenticatorAssuranceLevels.aal1);
    expect(f.auth.platformContext.stepUpVerified, false);
    expect(f.enrolls, 1);
  });
  for (final change in ['logout', 'login B']) {
    test('delayed actual SDK MFA response cannot restore A after $change',
        () async {
      final wait = Completer<void>();
      f.verifyWait = wait;
      f.verifyStarted = Completer();
      final started = f.verifyStarted!.future;
      final pending = f.repo.verify('factor-1', '001234');
      final assertion = expectLater(pending, throwsA(isA<MfaFailure>()));
      await started;
      if (change == 'logout') {
        await f.auth.signOut();
      } else {
        await f.client.auth.signInWithPassword(
            email: 'synthetic-b@example.test', password: 'synthetic-only');
      }
      await flushSdk();
      wait.complete();
      await assertion;
      await flushSdk();
      expect(f.client.auth.currentUser?.id, change == 'logout' ? null : actorB);
      expect(f.auth.user?.id, change == 'logout' ? null : actorB);
      expect(f.auth.platformContext.stepUpVerified, false);
    });
    test('delayed actual SDK refresh cannot replace $change', () async {
      final wait = Completer<void>();
      f.refreshWait = wait;
      f.refreshStarted = Completer();
      final started = f.refreshStarted!.future;
      final pending = f.repo.inspect();
      final assertion = expectLater(pending, throwsA(isA<MfaFailure>()));
      await started;
      if (change == 'logout') {
        await f.auth.signOut();
      } else {
        await f.client.auth.signInWithPassword(
            email: 'synthetic-b@example.test', password: 'synthetic-only');
      }
      await flushSdk();
      wait.complete();
      await assertion;
      await flushSdk();
      expect(f.client.auth.currentUser?.id, change == 'logout' ? null : actorB);
    });
  }
  test('late AAL1 projection cannot overwrite verified AAL2 projection',
      () async {
    final wait = Completer<void>();
    f.projectionWait = wait;
    f.projectionStarted = Completer();
    final started = f.projectionStarted!.future;
    final old = f.auth.refreshPlatformContext();
    await started;
    await f.repo.verify('factor-1', '001234');
    await flushSdk();
    expect(f.auth.platformContext.stepUpVerified, true);
    wait.complete();
    await old;
    expect(f.auth.platformContext.stepUpVerified, true);
  });
  test('old AAL2 success cannot override a later server denial', () async {
    await f.repo.verify('factor-1', '001234');
    await flushSdk();
    final wait = Completer<void>();
    f.projectionWait = wait;
    f.projectionStarted = Completer();
    final started = f.projectionStarted!.future;
    final old = f.auth.refreshPlatformContext();
    await started;
    f.serverDenies = true;
    await f.auth.refreshPlatformContext();
    wait.complete();
    await old;
    expect(f.auth.platformContext.stepUpVerified, false);
  });
  test('old request failure cannot erase newer confirmed context', () async {
    f.failProjection = true;
    final wait = Completer<void>();
    f.projectionWait = wait;
    f.projectionStarted = Completer();
    final started = f.projectionStarted!.future;
    final old = f.auth.refreshPlatformContext();
    await started;
    f.failProjection = false;
    await f.repo.verify('factor-1', '001234');
    await flushSdk();
    wait.complete();
    await old;
    expect(f.auth.platformContext.stepUpVerified, true);
  });
  test('SDK AAL2 alone never overrides server denial', () async {
    f.serverDenies = true;
    await f.repo.verify('factor-1', '001234');
    final status = await f.repo.inspect();
    expect(status.aal2, true);
    expect(status.confirmed, false);
    expect(f.auth.platformContext.stepUpVerified, false);
  });
  test('actual SDK wrong code and Retry-After map to safe typed errors',
      () async {
    f.verifyStatus = 422;
    await expectLater(
        f.repo.verify('factor-1', '001234'),
        throwsA(isA<MfaFailure>()
            .having((e) => e.kind, 'kind', MfaError.invalidCode)));
    f.verifyStatus = 429;
    await expectLater(
        f.repo.verify('factor-1', '001234'),
        throwsA(isA<MfaFailure>()
            .having((e) => e.kind, 'kind', MfaError.rateLimited)));
    expect(f.repo.retryNotBefore, isNotNull);
    expect(f.verifies, 2);
    expect(f.enrolls, 0);
  });
  test('server AAL2 with SDK AAL1 is uncertain and never enables decisions',
      () async {
    f.forceServerAssurance = true;
    await expectLater(
        f.repo.inspect(),
        throwsA(isA<MfaFailure>()
            .having((e) => e.kind, 'kind', MfaError.contextMismatch)));
    expect(f.auth.platformContext.stepUpVerified, false);
  });
  test('removed factor after verification disables decisions on revalidation',
      () async {
    await f.repo.verify('factor-1', '001234');
    await flushSdk();
    f.hasFactor = false;
    await expectLater(f.repo.inspect(), throwsA(isA<MfaFailure>()));
    expect(f.auth.platformContext.stepUpVerified, false);
  });
  test('background invalidates access and resume requests fresh projection',
      () async {
    await f.repo.verify('factor-1', '001234');
    await flushSdk();
    f.auth.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(f.auth.platformContext.stepUpVerified, false);
    f.serverDenies = true;
    f.auth.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await flushSdk();
    expect(f.auth.platformContext.stepUpVerified, false);
  });
  test('Retry-After accepts delta seconds and HTTP dates', () {
    final now = DateTime.utc(2026, 10, 4, 10);
    expect(mfaRetryDeadline('60', now), now.add(const Duration(minutes: 1)));
    expect(mfaRetryDeadline('Sun, 04 Oct 2026 10:01:00 GMT', now),
        DateTime.utc(2026, 10, 4, 10, 1));
    expect(mfaRetryDeadline('unavailable', now), null);
  });
  for (final entry in {
    'mfa_challenge_expired': MfaError.expired,
    'mfa_totp_verify_not_enabled': MfaError.disabled,
    'mfa_factor_limit_exceeded': MfaError.factorLimit,
  }.entries) {
    test('SDK maps ${entry.key} safely without retries', () async {
      f.verifyStatus = 400;
      f.verifyError = entry.key;
      await expectLater(
          f.repo.verify('factor-1', '001234'),
          throwsA(
              isA<MfaFailure>().having((e) => e.kind, 'kind', entry.value)));
      expect(f.verifies, 1);
      expect(f.enrolls, 0);
    });
  }
}
