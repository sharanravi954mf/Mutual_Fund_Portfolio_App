import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/mfa_controller.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/mfa_models.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/platform_security_screen.dart';
import 'package:mutual_fund_portfolio_app/features/mfd_applications/presentation/mfd_application_screens.dart';
import 'platform_mfa_sdk_test.dart' show SdkFixture, flushSdk, actorA, actorB;
import 'mfd_application_test.dart' show FakeMfdRepository, app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SdkFixture f;
  late MfaController controller;
  late VoidCallback accessChanged;
  setUp(() async {
    f = SdkFixture();
    await f.init();
    controller = MfaController(f.repo);
    // Deliberately the production security screen's actual listener contract.
    accessChanged = () => controller.accessChanged(
        currentAccess: f.auth.platformContextCurrent,
        admin: f.auth.platformContext.isPlatformAdmin,
        stepUp: f.auth.platformContext.stepUpVerified);
    f.auth.addListener(accessChanged);
  });
  tearDown(() async {
    f.auth.removeListener(accessChanged);
    controller.dispose();
    await f.dispose();
  });

  test(
      'real controller plus SDK and provider listener verifies existing factor',
      () async {
    await controller.refresh();
    expect(controller.canVerify, isTrue);
    await controller.verify('001234');
    await flushSdk();
    expect(controller.confirmed, isTrue);
    expect(f.auth.platformContext.stepUpVerified, isTrue);
    expect(f.enrolls, 0);
    expect(f.verifies, 1);
  });

  test('older inspection returns recoverably while newer projection is pending',
      () async {
    final first = Completer<void>();
    f.projectionWait = first;
    f.projectionStarted = Completer<void>();
    final firstStarted = f.projectionStarted!.future;
    final initial = controller.refresh();
    await firstStarted;
    final latest = Completer<void>();
    f.projectionWait = latest;
    f.projectionStarted = Completer<void>();
    final latestStarted = f.projectionStarted!.future;
    final newerProjection = f.auth.refreshPlatformContext();
    await latestStarted;
    first.complete();
    await initial;
    expect(controller.current, isTrue);
    expect(controller.error, MfaError.contextUnavailable);
    expect(controller.canVerify, isFalse);
    expect(controller.canEnroll, isFalse);
    expect(controller.confirmed, isFalse);
    expect(f.auth.platformContext.stepUpVerified, isFalse);
    latest.complete();
    await newerProjection;
    await flushSdk();
    expect(f.auth.platformContextCurrent, isTrue);
    expect(f.auth.platformContext.isPlatformAdmin, isTrue);
    expect(controller.current, isTrue,
        reason: 'A superseded read is not a revoked account.');
    await controller.refresh();
    expect(controller.canVerify, isTrue);
    expect(f.enrolls, 0);
    expect(f.verifies, 0);
    expect(f.refreshes, 2);
    expect(f.projections, lessThanOrEqualTo(5));
  });

  test('pending setup survives superseded success and explicit recovery',
      () async {
    f.hasFactor = false;
    await controller.refresh();
    await controller.enroll();
    final setup = controller.setup;
    expect(setup, isNotNull);
    final first = Completer<void>();
    f.projectionWait = first;
    f.projectionStarted = Completer<void>();
    final started = f.projectionStarted!.future;
    final inspection = controller.refresh();
    await started;
    final latest = Completer<void>();
    f.projectionWait = latest;
    f.projectionStarted = Completer<void>();
    final newerStarted = f.projectionStarted!.future;
    final newer = f.auth.refreshPlatformContext();
    await newerStarted;
    first.complete();
    await inspection;
    expect(controller.setup, same(setup));
    expect(controller.setup.toString(), 'MfaSetup(redacted)');
    expect(controller.status, isNull);
    expect(controller.canVerify, isFalse);
    latest.complete();
    await newer;
    await controller.refresh();
    expect(controller.current, isTrue);
    expect(controller.setup, same(setup));
    expect(controller.canVerify, isTrue);
    expect(controller.confirmed, isFalse);
    expect(f.enrolls, 1);
    expect(f.verifies, 0);
  });

  for (final olderFirst in [true, false]) {
    test('newer authoritative denial is terminal; older first = $olderFirst',
        () async {
      f.hasFactor = false;
      await controller.refresh();
      await controller.enroll();
      final oldGate = Completer<void>();
      f.projectionWait = oldGate;
      f.projectionStarted = Completer<void>();
      final started = f.projectionStarted!.future;
      final old = controller.refresh();
      await started;
      f.platformAdmin = false;
      final latestGate = Completer<void>();
      f.projectionWait = latestGate;
      f.projectionStarted = Completer<void>();
      final latestStarted = f.projectionStarted!.future;
      final latest = f.auth.refreshPlatformContext();
      await latestStarted;
      if (olderFirst) {
        oldGate.complete();
        await old;
        expect(controller.current, isTrue);
      }
      latestGate.complete();
      await latest;
      expect(f.auth.platformContextCurrent, isTrue);
      expect(f.auth.platformContext.isPlatformAdmin, isFalse);
      expect(controller.current, isFalse);
      expect(controller.setup, isNull);
      if (!olderFirst) {
        oldGate.complete();
        await old;
      }
      await controller.refresh();
      expect(controller.current, isFalse);
      expect(controller.canVerify, isFalse);
      expect(f.auth.platformContext.isPlatformAdmin, isFalse);
      expect(f.enrolls, 1);
      expect(f.verifies, 0);
    });
  }

  test('failed projection is recoverable without retaining confirmed assurance',
      () async {
    await controller.refresh();
    await controller.verify('001234');
    expect(controller.confirmed, isTrue);
    f.failProjection = true;
    await controller.refresh();
    expect(controller.error, MfaError.contextUnavailable);
    expect(controller.current, isTrue);
    expect(controller.confirmed, isFalse);
    expect(controller.canVerify, isFalse);
    expect(f.auth.platformContext.stepUpVerified, isFalse);
    final reads = f.projections;
    await flushSdk();
    expect(f.projections, reads); // No polling or automatic read retry.
    f.failProjection = false;
    await controller.refresh();
    expect(controller.confirmed, isTrue);
    expect(f.verifies, 1); // Never repeat OTP verification to recover a read.
    expect(f.enrolls, 0);
  });

  test('newer assurance denial survives an older successful inspection',
      () async {
    await controller.refresh();
    await controller.verify('001234');
    final gate = Completer<void>();
    f.projectionWait = gate;
    f.projectionStarted = Completer<void>();
    final started = f.projectionStarted!.future;
    final old = controller.refresh();
    await started;
    f.serverDenies = true;
    await f.auth.refreshPlatformContext();
    gate.complete();
    await old;
    expect(controller.current, isTrue);
    expect(controller.confirmed, isFalse);
    expect(f.auth.platformContext.stepUpVerified, isFalse);
    expect(f.verifies, 1);
    expect(f.enrolls, 0);
  });

  test('removed factor cannot be restored by an older inspection', () async {
    await controller.refresh();
    await controller.verify('001234');
    final gate = Completer<void>();
    f.projectionWait = gate;
    f.projectionStarted = Completer<void>();
    final started = f.projectionStarted!.future;
    final old = controller.refresh();
    await started;
    f.hasFactor = false;
    await expectLater(f.repo.inspect(), throwsA(isA<MfaFailure>()));
    gate.complete();
    await old;
    expect(f.auth.platformContext.stepUpVerified, isFalse);
    expect(controller.confirmed, isFalse);
    expect(controller.canVerify, isFalse);
    expect(f.verifies, 1);
    expect(f.enrolls, 0);
  });

  test('expired SDK session cannot be confirmed by a late projection',
      () async {
    await controller.refresh();
    await controller.verify('001234');
    final gate = Completer<void>();
    f.projectionWait = gate;
    f.projectionStarted = Completer<void>();
    final started = f.projectionStarted!.future;
    final old = controller.refresh();
    await started;
    // Expire only the synthetic SDK Session model, without changing its token
    // or producing another auth event. Exercise the provider's expiry check.
    f.client.auth.currentSession!.expiresAt =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1;
    f.auth.invalidatePlatformContext();
    gate.complete();
    await old;
    expect(f.auth.platformContextCurrent, isFalse);
    expect(f.auth.platformContext.stepUpVerified, isFalse);
    expect(controller.confirmed, isFalse);
    expect(controller.canVerify, isFalse);
    expect(controller.canEnroll, isFalse);
    expect(f.verifies, 1);
    expect(f.enrolls, 0);
  });

  for (final change in ['logout', 'A -> B', 'A -> B -> A']) {
    test('old status cannot revive controller after $change', () async {
      f.hasFactor = false;
      await controller.refresh();
      await controller.enroll();
      final gate = Completer<void>();
      f.projectionWait = gate;
      f.projectionStarted = Completer<void>();
      final started = f.projectionStarted!.future;
      final old = controller.refresh();
      await started;
      if (change == 'logout') {
        await f.auth.signOut();
      } else {
        await f.client.auth.signInWithPassword(
            email: 'synthetic-b@example.test', password: 'synthetic-only');
        await flushSdk();
        if (change == 'A -> B -> A') {
          f.signInActor = actorA;
          await f.client.auth.signInWithPassword(
              email: 'synthetic-a@example.test', password: 'synthetic-only');
        }
      }
      await flushSdk();
      expect(controller.current, isFalse);
      expect(controller.setup, isNull);
      gate.complete();
      await old;
      await controller.refresh();
      expect(controller.current, isFalse);
      expect(controller.setup, isNull);
      expect(controller.confirmed, isFalse);
      expect(
          f.client.auth.currentUser?.id,
          change == 'logout'
              ? null
              : change == 'A -> B'
                  ? actorB
                  : actorA);
      expect(f.enrolls, 1);
      expect(f.verifies, 0);
    });
  }

  testWidgets('stacked MFD and security resume with overlapping real listeners',
      (tester) async {
    final mfd = FakeMfdRepository()..items = [app('under_review')];
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: f.auth,
        child: MaterialApp(
            home: MfdReviewDetailScreen(
                applicationId: 'application-id',
                repository: mfd,
                mfaRepository: f.repo))));
    await tester.pumpAndSettle();
    final entry = find.text('Verify MFA');
    await tester.ensureVisible(entry);
    // Keep SDK HTTP completions and its auth broadcast in the same real-async
    // zone; use pump only for frames, not to split SDK event delivery.
    await tester.runAsync(() async {
      await tester.tap(entry);
      await flushSdk();
    });
    await tester.pumpAndSettle();
    expect(find.byType(PlatformSecurityScreen), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    final gate = Completer<void>();
    f.projectionWait = gate;
    await tester.runAsync(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flushSdk();
    });
    expect(f.auth.platformContext.stepUpVerified, isFalse);
    // Provider + underlying detail + security screen all receive resume.
    // Release the oldest held projection after the newer requests have settled.
    await tester.runAsync(() async {
      gate.complete();
      await flushSdk();
    });
    await tester.pumpAndSettle();
    final refresh = find.text('Refresh security status');
    await tester.ensureVisible(refresh);
    await tester.runAsync(() async {
      await tester.tap(refresh);
      await flushSdk();
    });
    await tester.pumpAndSettle();
    // Refresh is below the code field in the lazily built scrolling page.
    await tester.scrollUntilVisible(find.byKey(const Key('mfa-code')), -160,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('mfa-code')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('mfa-code'))).enabled,
        isTrue);
    expect(f.enrolls, 0);
    expect(f.verifies, 0);
    expect(mfd.requests, isEmpty);
    expect(f.refreshes, lessThanOrEqualTo(3));
    expect(f.projections, lessThanOrEqualTo(9));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
