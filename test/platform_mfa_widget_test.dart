import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/mfa_setup_panel.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/mfa_models.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/platform_security_screen.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/presentation/platform_administration_screen.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/models/platform_context.dart';
import 'package:mutual_fund_portfolio_app/features/mfd_applications/presentation/mfd_application_screens.dart';
import 'package:mutual_fund_portfolio_app/features/mfd_applications/models/mfd_application.dart';
import 'support/platform_mfa_fakes.dart';
import 'mfd_application_test.dart' show MfdAuth, FakeMfdRepository, app;

void main() {
  late FakeMfaRepository repo;
  late MfdAuth auth;
  Future<void> pump(WidgetTester tester, Widget child,
      {bool dark = false, double scale = 1}) async {
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: child)));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label);
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 180,
          scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(finder.last);
    await tester.pumpAndSettle();
    await tester.tap(finder.last);
    await tester.pumpAndSettle();
  }

  setUp(() {
    repo = FakeMfaRepository();
    auth = MfdAuth(platform: true, review: true);
  });
  tearDown(() => auth.dispose());
  testWidgets('entry and rebuild are read only; setup QR and copy stay local',
      (tester) async {
    await pump(tester, PlatformSecurityScreen(repository: repo));
    expect(repo.enrollments, 0);
    await tap(tester, 'Refresh security status');
    expect(repo.enrollments, 0);
    await tap(tester, 'Set up authenticator');
    expect(repo.enrollments, 1);
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(tester.widget<MfaSetupPanel>(find.byType(MfaSetupPanel)).setup.uri,
        syntheticUri);
    expect(qr.backgroundColor, Colors.white);
    expect(find.byKey(const Key('mfa-manual-key')), findsNothing);
    await tap(tester, 'Reveal setup key');
    expect(find.byKey(const Key('mfa-manual-key')), findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await tap(tester, 'Copy setup key');
    expect(copied, syntheticSecret);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    expect(find.textContaining('same phone'), findsOneWidget);
    await tester.pump();
    expect(repo.enrollments, 1);
  });
  testWidgets(
      'leading-zero paste explicit submission and wrong code retains factor',
      (tester) async {
    repo.factors = [verifiedFactor];
    await pump(tester, PlatformSecurityScreen(repository: repo));
    final code = find.byKey(const Key('mfa-code'));
    await tester.enterText(code, '001234');
    expect(repo.verifications, 0);
    await tap(tester, 'Verify MFA');
    expect(repo.lastCode, '001234');
    expect(repo.enrollments, 0);
    expect(find.text('Current platform session verified by the server.'),
        findsOneWidget);
    expect(find.byKey(const Key('mfa-code')), findsNothing);
  });
  testWidgets('large text narrow dark layout and inactive hides setup',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(tester, PlatformSecurityScreen(repository: repo),
        dark: true, scale: 2);
    await tap(tester, 'Set up authenticator');
    expect(tester.takeException(), null);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.enrollments, 1);
    if (find.byType(QrImageView).evaluate().isEmpty) {
      await tester.scrollUntilVisible(find.byType(QrImageView), 180,
          scrollable: find.byType(Scrollable).first);
    }
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), null);
  });
  testWidgets('pending setup has honest restart guidance, never auto enrolls',
      (tester) async {
    repo.factors = [pendingFactor];
    await pump(tester, PlatformSecurityScreen(repository: repo));
    expect(find.textContaining('page reload cannot recover'), findsOneWidget);
    await tap(tester, 'Start new setup');
    expect(repo.enrollments, 0);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tap(tester, 'Start new setup');
    expect(repo.enrollments, 1);
  });
  testWidgets('platform tile opens same account security feature',
      (tester) async {
    await pump(tester, PlatformAdministrationScreen(mfaRepository: repo));
    await tap(tester, 'Account security');
    expect(find.byType(PlatformSecurityScreen), findsOneWidget);
    expect(repo.enrollments, 0);
  });
  testWidgets(
      'MFD step-up return reloads exact application with no business action',
      (tester) async {
    final mfd = FakeMfdRepository()..items = [app('under_review')];
    repo.factors = [verifiedFactor];
    repo.onVerified = () => auth.updatePlatformContext(repo.platform);
    await pump(
        tester,
        MfdReviewDetailScreen(
            applicationId: 'application-id',
            repository: mfd,
            mfaRepository: repo));
    await tap(tester, 'Set up / Verify MFA');
    await tester.enterText(find.byKey(const Key('mfa-code')), '001234');
    await tap(tester, 'Verify MFA');
    final before = mfd.reads;
    await tap(tester, 'Return to application');
    expect(mfd.reads, greaterThan(before));
    expect(mfd.requests, isEmpty);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'))
            .onPressed,
        isNotNull);
  });
  testWidgets(
      'another reviewer terminal result replaces stale action form on return',
      (tester) async {
    final mfd = FakeMfdRepository()..items = [app('under_review')];
    repo.factors = [verifiedFactor];
    repo.onVerified = () {
      auth.updatePlatformContext(repo.platform);
      mfd.items = [app('rejected', reason: 'Another review')];
    };
    await pump(
        tester,
        MfdReviewDetailScreen(
            applicationId: 'application-id',
            repository: mfd,
            mfaRepository: repo));
    await tap(tester, 'Set up / Verify MFA');
    await tester.enterText(find.byKey(const Key('mfa-code')), '001234');
    await tap(tester, 'Verify MFA');
    await tap(tester, 'Return to application');
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(mfd.requests, isEmpty);
  });
  testWidgets(
      'missing capability gives access error without enrollment invitation',
      (tester) async {
    auth.updatePlatformContext(const PlatformContext(isPlatformAdmin: true));
    final mfd = FakeMfdRepository();
    await pump(
        tester,
        MfdReviewDetailScreen(
            applicationId: 'application-id',
            repository: mfd,
            mfaRepository: repo));
    expect(find.text('Application review permission is required.'),
        findsOneWidget);
    expect(mfd.reads, 0);
    expect(find.text('Set up / Verify MFA'), findsNothing);
  });
  testWidgets('revoked review capability hides setup in the shared flow',
      (tester) async {
    await pump(
        tester,
        PlatformSecurityScreen(
            repository: repo,
            destination: const MfaDestination.review('application-id')));
    expect(find.text('Set up authenticator'), findsOneWidget);
    auth.updatePlatformContext(const PlatformContext(isPlatformAdmin: true));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Application review permission is unavailable. MFA does not grant that permission.'),
        findsOneWidget);
    expect(find.text('Set up authenticator'), findsNothing);
    expect(find.text('Verify MFA'), findsNothing);
    expect(repo.enrollments, 0);
  });
  testWidgets(
      'uncertain sent approval retains original UUID and payload across MFA',
      (tester) async {
    final mfd = FakeMfdRepository()
      ..items = [app('under_review')]
      ..failure = TimeoutException('synthetic');
    auth.updatePlatformContext(const PlatformContext(
        isPlatformAdmin: true,
        capabilities: {'mfd_applications.review'},
        stepUpVerified: true));
    repo.factors = [verifiedFactor];
    repo.onVerified = () => auth.updatePlatformContext(repo.platform);
    await pump(
        tester,
        MfdApplicationForm(
            repository: mfd,
            operation: MfdOperation.approve,
            application: app('under_review'),
            mfaRepository: repo));
    await tester.enterText(
        find.byKey(const Key('mfd-note')), 'Synthetic honest review');
    await tester.tap(find.byType(CheckboxListTile));
    await tap(tester, 'Confirm approval');
    final sent = mfd.requests.single;
    auth.updatePlatformContext(reviewContext);
    await tester.pumpAndSettle();
    await tap(tester, 'Verify MFA');
    await tester.enterText(find.byKey(const Key('mfa-code')), '001234');
    await tap(tester, 'Verify MFA');
    await tap(tester, 'Return to application');
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('mfd-note')))
            .controller!
            .text,
        'Synthetic honest review');
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false);
    await tap(tester, 'Retry safely');
    expect(mfd.requests.length, 1);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tap(tester, 'Retry safely');
    expect(mfd.requests.length, 2);
    expect(identical(mfd.requests.last, sent), true);
  });
  testWidgets(
      'late Start review result cannot navigate or expose actor state after account switch',
      (tester) async {
    final wait = Completer<void>();
    final mfd = FakeMfdRepository()
      ..items = [app('submitted')]
      ..wait = wait;
    await pump(
        tester,
        MfdReviewDetailScreen(
            applicationId: 'application-id',
            repository: mfd,
            mfaRepository: repo));
    await tester.tap(find.text('Start review'));
    await tester.pump();
    expect(mfd.requests.length, 1);
    auth.changeSession();
    await tester.pump();
    wait.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('signed-in account changed'), findsOneWidget);
    expect(find.text('Start review'), findsNothing);
    auth.sessionUser = 'user-id';
    auth.notifyListeners();
    await tester.pump();
    expect(find.textContaining('signed-in account changed'), findsOneWidget);
    expect(mfd.requests.length, 1);
  });
  testWidgets(
      'cancel clears setup, leaves pending factor and reentry never enrolls',
      (tester) async {
    await pump(tester, PlatformAdministrationScreen(mfaRepository: repo));
    await tap(tester, 'Account security');
    await tap(tester, 'Set up authenticator');
    await tap(tester, 'Cancel');
    await tap(tester, 'Leave');
    expect(find.byType(PlatformSecurityScreen), findsNothing);
    await tap(tester, 'Account security');
    expect(repo.enrollments, 1);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining('Incomplete setup exists'), findsOneWidget);
  });
  testWidgets('a server denial disables a previously enabled decision',
      (tester) async {
    final mfd = FakeMfdRepository()
      ..items = [app('under_review')]
      ..failure =
          const PostgrestException(message: 'platform_admin_step_up_required');
    auth.updatePlatformContext(const PlatformContext(
        isPlatformAdmin: true,
        capabilities: {'mfd_applications.review'},
        stepUpVerified: true));
    await pump(
        tester,
        MfdApplicationForm(
            repository: mfd,
            operation: MfdOperation.reject,
            application: app('under_review'),
            mfaRepository: repo));
    await tester.enterText(
        find.byKey(const Key('mfd-note')), 'Synthetic rejection reason');
    await tap(tester, 'Confirm rejection');
    expect(mfd.requests.length, 1);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Retry safely'))
            .onPressed,
        null);
    expect(find.text('Verify MFA'), findsOneWidget);
  });
  testWidgets(
      'failed application reload after MFA leaves no stale decision buttons',
      (tester) async {
    final mfd = FakeMfdRepository()..items = [app('under_review')];
    repo.factors = [verifiedFactor];
    repo.onVerified = () {
      auth.updatePlatformContext(repo.platform);
      mfd.loadFailure = StateError('synthetic read failure');
    };
    await pump(
        tester,
        MfdReviewDetailScreen(
            applicationId: 'application-id',
            repository: mfd,
            mfaRepository: repo));
    await tap(tester, 'Set up / Verify MFA');
    await tester.enterText(find.byKey(const Key('mfa-code')), '001234');
    await tap(tester, 'Verify MFA');
    await tap(tester, 'Return to application');
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(mfd.requests, isEmpty);
    expect(find.byKey(const Key('mfd-error')), findsOneWidget);
  });
}
