import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/data/investor_onboarding_repository.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/models/onboarding_case.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/presentation/investor_onboarding_controller.dart';
import 'package:mutual_fund_portfolio_app/features/investor_onboarding/presentation/investor_onboarding_page.dart';

OnboardingCase fixture(
        {String status = 'DRAFT',
        int version = 1,
        String id = 'case',
        Map<String, String> fields = const {}}) =>
    OnboardingCase.fromJson({
      'id': id,
      'workspace_id': 'workspace',
      'version': version,
      'legal_name': 'Synthetic Investor',
      'status': status,
      'relationship_status': status == 'DRAFT' ? 'PENDING' : 'READY',
      'account_link_status': 'PENDING_VERIFIED_IDENTITY',
      'nse_state': 'NOT_REGISTERED',
      'investor_profile_id': status == 'DRAFT' ? null : 'investor',
      'missing': ['date_of_birth', 'kyc_verification'],
      'masked_pan': '******001Z',
      'masked_account': '******0001',
      'fields': fields,
    });

class FakeRepository implements InvestorOnboardingRepository {
  bool denied = false, failSave = false;
  final calls = <Map<String, dynamic>>[];
  Completer<OnboardingCase>? pending;
  @override
  Future<List<Map<String, String>>> workspaces() async => denied
      ? []
      : [
          {'id': 'workspace', 'name': 'Synthetic MFD'}
        ];
  @override
  Future<List<OnboardingCase>> list(String workspace) async => [fixture()];
  @override
  Future<OnboardingCase> get(String id) async => fixture(id: id);
  @override
  Future<OnboardingCase> save(String workspace, String id, int version,
      Map<String, String> fields) async {
    calls.add({
      'workspace': workspace,
      'id': id,
      'version': version,
      'fields': Map.of(fields)
    });
    if (failSave) throw const PostgrestException(message: 'invalid_pan');
    if (pending != null) return pending!.future;
    return fixture(
        id: id,
        version: version + 1,
        fields: Map.of(fields)
          ..remove('pan')
          ..remove('account_number'));
  }

  @override
  Future<OnboardingCase> resolve(String id, int version) async =>
      fixture(id: id, version: version + 1, status: 'PROFILE_INCOMPLETE');
}

void main() {
  test(
      'retry retains case id and unsubmitted input; successful capture removes secrets',
      () async {
    final repo = FakeRepository();
    final c = InvestorOnboardingController(repo);
    addTearDown(c.dispose);
    await c.load();
    c.start();
    c.fields.addAll({
      'legal_name': 'Synthetic Investor',
      'pan': 'ZZZPZ0001Z',
      'account_number': '00000001'
    });
    repo.failSave = true;
    await c.save();
    expect(c.error, 'Enter a valid PAN.');
    expect(c.fields['pan'], 'ZZZPZ0001Z');
    repo.failSave = false;
    await c.save();
    expect(repo.calls[0]['id'], repo.calls[1]['id']);
    expect(c.fields.containsKey('pan'), false);
    expect(c.fields.containsKey('account_number'), false);
    expect(c.phase, OnboardingPhase.saved);
  });
  test(
      'double click only sends one mutation and late response after disposal is ignored',
      () async {
    final repo = FakeRepository();
    final c = InvestorOnboardingController(repo);
    await c.load();
    c.start();
    repo.pending = Completer();
    final saving = c.save();
    await c.save();
    expect(repo.calls.length, 1);
    c.dispose();
    repo.pending!.complete(fixture());
    await saving;
    expect(c.current, isNull);
  });
  test('normal Add Investor never accepts auth user ids or requests accounts',
      () async {
    final repo = FakeRepository();
    final c = InvestorOnboardingController(repo);
    addTearDown(c.dispose);
    await c.load();
    c.start();
    c.fields['legal_name'] = 'Synthetic Investor';
    await c.save(resolve: true);
    expect(c.current!.status, 'PROFILE_INCOMPLETE');
    expect(repo.calls.single.keys,
        unorderedEquals(['workspace', 'id', 'version', 'fields']));
    expect(c.current!.missing, contains('date_of_birth'));
  });
  for (final width in [320.0, 1200.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('capture review resume at $width $brightness large text',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = InvestorOnboardingController(FakeRepository());
        addTearDown(c.dispose);
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!),
            home: InvestorOnboardingPage(controller: c)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Investor'));
        await tester.pumpAndSettle();
        expect(find.text('Legal name'), findsOneWidget);
        c.fields.addAll({
          'legal_name': 'Synthetic Investor',
          'pan': 'ZZZPZ0001Z',
          'email': 'synthetic@example.test',
          'account_number': '00000001'
        });
        c.review();
        await tester.pumpAndSettle();
        expect(find.textContaining('ZZZPZ0001Z'), findsNothing);
        expect(find.textContaining('synthetic@example.test'), findsNothing);
        expect(find.textContaining('00000001'), findsNothing);
        expect(tester.takeException(), isNull);
        await c.save(resolve: true);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
            find.text('Remaining prerequisites'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Remaining prerequisites'), findsOneWidget);
        await tester.scrollUntilVisible(
            find.textContaining('date of birth'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.textContaining('date of birth'), findsOneWidget);
        expect(find.textContaining('Explorer'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('Clients Add Investor opens personal details directly',
      (tester) async {
    final c = InvestorOnboardingController(FakeRepository());
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
        home: InvestorOnboardingPage(controller: c, startNew: true)));
    await tester.pumpAndSettle();
    expect(find.text('Personal details'), findsOneWidget);
    expect(find.text('Saved onboarding'), findsNothing);
  });
  testWidgets('authority unavailable is explicit', (tester) async {
    final c = InvestorOnboardingController(FakeRepository()..denied = true);
    addTearDown(c.dispose);
    await tester
        .pumpWidget(MaterialApp(home: InvestorOnboardingPage(controller: c)));
    await tester.pumpAndSettle();
    expect(find.textContaining('active approved MFD'), findsOneWidget);
    expect(find.text('Add Investor'), findsNothing);
  });
}
