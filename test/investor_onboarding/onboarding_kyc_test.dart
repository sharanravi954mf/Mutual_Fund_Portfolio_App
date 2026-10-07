import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/data/onboarding_kyc_repository.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/presentation/onboarding_kyc_controller.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/presentation/onboarding_kyc_page.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/presentation/investor_onboarding_controller.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/presentation/investor_onboarding_page.dart';
import 'onboarding_test.dart' show FakeRepository;

KycCase kyc(String state, {bool amcs = true}) => KycCase({
      'id': 'case',
      'workspace_id': 'workspace',
      'version': 1,
      'status': state,
      'relationship_status': 'PENDING',
      'account_link_status': 'PENDING_VERIFIED_IDENTITY',
      'nse_state': 'NOT_REGISTERED',
      'missing': <String>[],
      'fields': <String, String>{},
      'amcs': amcs
          ? [
              {'code': 'TEST', 'label': 'Synthetic AMC'}
            ]
          : [],
      'can_open_ekyc': state == 'EKYC_IN_PROGRESS',
    });

class KycRepository implements OnboardingKycRepository {
  @override
  final legacy = FakeRepository();
  String state = 'KYC_CHECK_REQUIRED';
  bool fail = false, hasAmcs = true;
  final calls = <List<String>>[];
  Completer<KycCase>? pending;
  @override
  Future<KycCase> start(String workspace, String id, String pan) async {
    calls.add(['start', id, pan]);
    return kyc(state);
  }

  @override
  Future<KycCase> get(String id) async => kyc(state, amcs: hasAmcs);
  @override
  Future<KycCase> request(String id, String requestId, String action,
      {String? email, String? mobile, String? amc}) async {
    calls.add([action, requestId]);
    if (fail) throw StateError('synthetic failure');
    if (pending != null) return pending!.future;
    return kyc(action == 'EKYC' ? 'EKYC_INITIATION_PENDING' : 'KYC_CHECKING');
  }

  @override
  Future<String?> link(String id) async => Uri.https(
          'nseinvestuat.nseindia.com', '/nsemfdesk/ekycVerifyByUser/synthetic')
      .toString();
}

void main() {
  testWidgets(
      'V2 remaining details hide account linkage and reported KYC claims',
      (tester) async {
    final c = InvestorOnboardingController(FakeRepository());
    addTearDown(c.dispose);
    await c.load();
    await c.resume('case');
    c.fields.addAll({'kyc_status': 'completed', 'kyc_method': 'kra'});
    await tester.pumpWidget(MaterialApp(
        home: InvestorOnboardingPage(
            controller: c, providerKyc: true, alreadyLoaded: true)));
    expect(find.textContaining('Account linkage'), findsNothing);
    c.edit();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Next'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Next'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Reported KYC status'), findsNothing);
    expect(find.text('KYC type'), findsNothing);
    c.review();
    await tester.pumpAndSettle();
    expect(find.textContaining('Reported KYC status:'), findsNothing);
  });
  testWidgets('a V1 draft without PAN resumes at PAN capture', (tester) async {
    final repo = KycRepository();
    final c = OnboardingKycController(repo);
    addTearDown(c.dispose);
    await tester
        .pumpWidget(MaterialApp(home: OnboardingKycPage(controller: c)));
    await tester.pumpAndSettle();
    repo.state = 'DRAFT';
    await c.resume('case');
    await tester.pumpAndSettle();
    expect(find.text('PAN'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ZZZPZ0001Z');
    repo.state = 'KYC_CHECK_REQUIRED';
    await tester.tap(find.text('Continue / Check KYC'));
    await tester.pumpAndSettle();
    expect(repo.calls.first, ['start', 'case', 'ZZZPZ0001Z']);
    expect(find.text('Checking KYC…'), findsOneWidget);
  });
  testWidgets('PAN-first, progress, no account lookup or giant form',
      (tester) async {
    final repo = KycRepository();
    final c = OnboardingKycController(repo);
    addTearDown(c.dispose);
    await tester
        .pumpWidget(MaterialApp(home: OnboardingKycPage(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('PAN'), findsOneWidget);
    expect(find.text('Legal name'), findsNothing);
    expect(find.textContaining('Explorer'), findsNothing);
    expect(find.textContaining('account selection'), findsNothing);
    await tester.enterText(find.byType(TextField), 'ZZZPZ0001Z');
    await tester.tap(find.text('Continue / Check KYC'));
    await tester.pumpAndSettle();
    expect(find.text('Checking KYC…'), findsOneWidget);
    expect(repo.calls.first[2], 'ZZZPZ0001Z');
    expect(find.text('ZZZPZ0001Z'), findsNothing);
  });
  testWidgets(
      'not available requests missing contacts and explicit AMC; eKYC progress, secure open and refresh',
      (tester) async {
    final repo = KycRepository();
    final c = OnboardingKycController(repo);
    addTearDown(c.dispose);
    int opens = 0;
    await tester.pumpWidget(MaterialApp(
        home: OnboardingKycPage(
            controller: c,
            openLink: (_) async {
              opens++;
              return true;
            })));
    await tester.pumpAndSettle();
    repo.state = 'KYC_NOT_AVAILABLE';
    await c.resume('case');
    await tester.pumpAndSettle();
    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Mobile'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synthetic AMC').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Proceed to eKYC'));
    await tester.pumpAndSettle();
    expect(find.text('Preparing eKYC…'), findsOneWidget);
    repo.state = 'EKYC_IN_PROGRESS';
    await c.refreshView();
    await tester.pumpAndSettle();
    expect(find.text('eKYC in progress'), findsOneWidget);
    expect(find.textContaining('https://'), findsNothing);
    expect(find.textContaining('ekycVerifyByUser'), findsNothing);
    await tester.tap(find.text('Open eKYC'));
    await tester.pumpAndSettle();
    expect(opens, 1);
    await tester.tap(find.text('Refresh KYC Status'));
    await tester.pumpAndSettle();
    expect(repo.calls.last.first, 'REFRESH');
  });
  testWidgets(
      'no trusted AMC is a visible blocker; reconciliation shows no provider action',
      (tester) async {
    final repo = KycRepository()..hasAmcs = false;
    final c = OnboardingKycController(repo);
    addTearDown(c.dispose);
    await tester
        .pumpWidget(MaterialApp(home: OnboardingKycPage(controller: c)));
    await tester.pumpAndSettle();
    repo.state = 'KYC_NOT_AVAILABLE';
    await c.resume('case');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Proceed to eKYC'))
            .onPressed,
        isNull);
    for (final state in [
      'IDENTITY_RECONCILIATION_REQUIRED',
      'RELATIONSHIP_RECONCILIATION_REQUIRED',
      'PROVIDER_RECONCILIATION_REQUIRED',
      'KYC_PROVIDER_REVIEW_REQUIRED'
    ]) {
      repo.state = state;
      await c.resume('case');
      await tester.pumpAndSettle();
      expect(find.text('Review required'), findsOneWidget);
      expect(find.text('Proceed to eKYC'), findsNothing);
    }
  });
  test(
      'double click and failed retry preserve one business request; disposal fences late result',
      () async {
    final repo = KycRepository();
    final c = OnboardingKycController(repo);
    await c.load();
    await c.resume('case');
    repo.fail = true;
    await c.check('');
    await c.check('');
    expect(repo.calls[0][1], repo.calls[1][1]);
    repo.fail = false;
    repo.pending = Completer<KycCase>();
    final first = c.check('');
    await c.check('');
    expect(repo.calls.length, 3);
    c.dispose();
    repo.pending!.complete(kyc('KYC_CHECKING'));
    await first;
    expect(c.current, isNull);
  });
  for (final width in [320.0, 1200.0]) {
    testWidgets('KYC screen supports width $width and large text',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = KycRepository();
      final c = OnboardingKycController(repo);
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: OnboardingKycPage(controller: c))));
      await tester.pumpAndSettle();
      repo.state = 'KYC_NOT_AVAILABLE';
      await c.resume('case');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
