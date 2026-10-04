import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/presentation/onboarding_screens.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_account.dart';
import 'package:mutual_fund_portfolio_app/features/mfd_applications/data/mfd_application_repository.dart';
import 'package:mutual_fund_portfolio_app/features/mfd_applications/models/mfd_application.dart';
import 'package:mutual_fund_portfolio_app/features/mfd_applications/presentation/mfd_application_screens.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/models/platform_context.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/presentation/platform_administration_screen.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'authentication/route_guard_test.dart' show FakeAuthProvider;

MfdApplication app(String status, {String? reason}) => MfdApplication(
    id: 'application-id',
    businessName: 'Example Financial',
    claimedArn: 'ARN / claim',
    email: 'applicant@example.test',
    status: status,
    version: status == 'submitted'
        ? 1
        : status == 'under_review'
            ? 2
            : 3,
    submittedAt: DateTime.utc(2026, 10, 4),
    applicantNote: 'My application note',
    decisionNote: reason,
    approvedArn: status == 'approved' ? 'ARN / claim' : null);

class MfdAuth extends FakeAuthProvider {
  MfdAuth({bool platform = false, bool review = false, bool aal2 = false})
      : super(
            isAuthenticated: true,
            userAccount: UserAccount(
                userId: 'user-id',
                accountState: AccountState.explorer,
                onboardingCompleted: true,
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026)),
            platformContext: PlatformContext(
                isPlatformAdmin: platform,
                capabilities: review ? {'mfd_applications.review'} : {},
                stepUpVerified: aal2));
  String sessionUser = 'user-id';
  @override
  User? get user => User(
      id: sessionUser,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-10-04T00:00:00Z');
  void changeSession() {
    accountGeneration++;
    sessionUser = 'another-user';
    notifyListeners();
  }

  int refreshes = 0;
  @override
  Future<void> refreshIdentity() async {
    refreshes++;
  }
}

class FakeMfdRepository implements MfdApplicationRepository {
  bool eligible = true;
  List<MfdApplication> items = [];
  List<MfdRequest> requests = [];
  Object? failure, loadFailure;
  Completer<void>? wait;
  int reads = 0;
  @override
  Future<bool> canApply() async => eligible;
  @override
  Future<List<MfdApplication>> list(
      {bool review = false, int offset = 0}) async {
    reads++;
    return items;
  }

  @override
  Future<MfdApplication> load(String id) async {
    reads++;
    if (loadFailure != null) throw loadFailure!;
    return items.single;
  }

  @override
  Future<List<MfdApplicationEvent>> events(String id) async =>
      [MfdApplicationEvent('submitted', DateTime.utc(2026, 10, 4))];
  @override
  Future<MfdApplication> mutate(MfdRequest request) async {
    requests.add(request);
    if (wait != null) await wait!.future;
    if (failure != null) throw failure!;
    final status = switch (request.operation) {
      MfdOperation.submit => 'submitted',
      MfdOperation.startReview => 'under_review',
      MfdOperation.approve => 'approved',
      MfdOperation.reject => 'rejected',
    };
    final result = app(status, reason: request.note);
    items = [result];
    eligible = status == 'rejected';
    return result;
  }
}

void main() {
  late FakeMfdRepository repo;
  late MfdAuth auth;
  setUp(() {
    repo = FakeMfdRepository();
    auth = MfdAuth();
  });
  tearDown(() {
    auth.dispose();
  });
  Future<void> mount(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth, child: MaterialApp(home: screen)));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label).last;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  void reviewer({bool aal2 = true, bool review = true}) {
    auth.dispose();
    auth = MfdAuth(platform: true, review: review, aal2: aal2);
  }

  testWidgets(
      'eligible Explorer sees application entry without signup role selection',
      (tester) async {
    await mount(tester, const ExplorerHomeScreen());
    expect(find.text('Apply as MFD'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('Advisor'), findsNothing);
  });
  testWidgets('applicant form validates and submits immutable claims',
      (tester) async {
    await mount(tester, MfdApplicantScreen(repository: repo));
    await tap(tester, 'Apply as MFD');
    await tap(tester, 'Submit application');
    expect(find.text('This field is required.'), findsNWidgets(2));
    expect(repo.requests, isEmpty);
    await tester.enterText(
        find.byKey(const Key('mfd-business')), 'Example Financial');
    await tester.enterText(find.byKey(const Key('mfd-arn')), 'ARN / claim');
    await tester.enterText(find.byKey(const Key('mfd-note')), 'note');
    await tap(tester, 'Submit application');
    expect(repo.requests.single.operation, MfdOperation.submit);
    expect(repo.requests.single.applicationId, isNull);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Apply as MFD'), findsNothing);
  });
  for (final status in ['submitted', 'under_review', 'rejected']) {
    testWidgets('applicant sees $status with correct reapplication policy',
        (tester) async {
      repo.items = [app(status, reason: 'Please provide a clearer reference')];
      repo.eligible = status == 'rejected';
      await mount(tester, MfdApplicantScreen(repository: repo));
      expect(find.text(repo.items.single.statusLabel), findsOneWidget);
      if (status == 'rejected') {
        expect(find.textContaining('Please provide a clearer reference'),
            findsOneWidget);
        await tap(tester, 'Start a new application');
        expect(find.text('Submit application'), findsOneWidget);
      } else {
        expect(find.text('Start a new application'), findsNothing);
      }
    });
  }
  testWidgets('approved result refreshes identity and displays status',
      (tester) async {
    repo.items = [app('approved', reason: 'Reviewed reference')];
    repo.eligible = false;
    await mount(tester, MfdApplicantScreen(repository: repo));
    expect(find.text('Approved'), findsOneWidget);
    expect(auth.refreshes, 1);
    expect(find.text('Continue to workspace'), findsOneWidget);
  });
  testWidgets('backend eligibility removes application action', (tester) async {
    repo.eligible = false;
    await mount(tester, MfdApplicantScreen(repository: repo));
    expect(find.text('Apply as MFD'), findsNothing);
    expect(
        find.textContaining('V1 supports verified Explorers'), findsOneWidget);
  });
  testWidgets('submission retry retains UUID and frozen payload',
      (tester) async {
    await mount(tester, MfdApplicantScreen(repository: repo));
    await tap(tester, 'Apply as MFD');
    await tester.enterText(
        find.byKey(const Key('mfd-business')), 'Example Financial');
    await tester.enterText(find.byKey(const Key('mfd-arn')), 'ARN / claim');
    repo.failure = const PostgrestException(
        message: 'private database details password=secret');
    await tap(tester, 'Submit application');
    expect(find.textContaining('private database'), findsNothing);
    expect(find.textContaining('Retry safely with the same request'),
        findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.descendant(
                of: find.byKey(const Key('mfd-business')),
                matching: find.byType(TextField)))
            .readOnly,
        isTrue);
    repo.failure = null;
    await tap(tester, 'Retry safely');
    expect(repo.requests.length, 2);
    expect(identical(repo.requests[0], repo.requests[1]), isTrue);
    expect(repo.requests[0].requestId, repo.requests[1].requestId);
  });
  testWidgets('platform capability makes tile actionable and renders queue',
      (tester) async {
    reviewer(aal2: false);
    repo.items = [app('submitted')];
    await mount(tester, PlatformAdministrationScreen(mfdRepository: repo));
    await tap(tester, 'MFD applications');
    expect(find.text('Example Financial'), findsOneWidget);
    expect(find.textContaining('ARN / claim'), findsOneWidget);
    expect(find.textContaining('04 Oct 2026'), findsOneWidget);
  });
  testWidgets('missing capability disables queue tile and direct screen reads',
      (tester) async {
    reviewer(review: false);
    await mount(tester, PlatformAdministrationScreen(mfdRepository: repo));
    expect(
        tester
            .widget<ListTile>(find.ancestor(
                of: find.text('MFD applications'),
                matching: find.byType(ListTile)))
            .onTap,
        isNull);
    await mount(tester, MfdReviewQueueScreen(repository: repo));
    expect(repo.reads, 0);
    expect(find.text('Application review permission is required.'),
        findsOneWidget);
  });
  testWidgets('detail opening is read-only; Start review is explicit',
      (tester) async {
    reviewer(aal2: false);
    repo.items = [app('submitted')];
    await mount(
        tester,
        MfdReviewDetailScreen(
            applicationId: 'application-id', repository: repo));
    expect(find.text('Applicant: applicant@example.test'), findsOneWidget);
    expect(find.text('Applicant note: My application note'), findsOneWidget);
    expect(find.textContaining('Submitted 04 Oct'), findsOneWidget);
    expect(repo.requests, isEmpty);
    await tap(tester, 'Start review');
    expect(repo.requests.single.operation, MfdOperation.startReview);
    expect(find.text('Under review'), findsOneWidget);
  });
  testWidgets('AAL1 blocks both decisions and explains MFA', (tester) async {
    reviewer(aal2: false);
    repo.items = [app('under_review')];
    await mount(
        tester,
        MfdReviewDetailScreen(
            applicationId: 'application-id', repository: repo));
    expect(find.textContaining('MFA verification is required'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Approve'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Reject'))
            .onPressed,
        isNull);
    expect(repo.requests, isEmpty);
  });
  testWidgets('approval requires evidence and confirmation then updates state',
      (tester) async {
    reviewer();
    repo.items = [app('under_review')];
    await mount(
        tester,
        MfdReviewDetailScreen(
            applicationId: 'application-id', repository: repo));
    await tap(tester, 'Approve');
    await tap(tester, 'Confirm approval');
    expect(find.text('This field is required.'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('mfd-note')), 'Manually checked reference 123');
    await tap(tester, 'Confirm approval');
    expect(repo.requests, isEmpty);
    expect(find.textContaining('Confirm that you manually reviewed'),
        findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tap(tester, 'Confirm approval');
    expect(repo.requests.single.operation, MfdOperation.approve);
    expect(repo.requests.single.note, 'Manually checked reference 123');
    expect(find.text('Approved'), findsOneWidget);
    expect(find.textContaining('Manually accepted ARN'), findsOneWidget);
  });
  testWidgets('rejection requires reason and updates state', (tester) async {
    reviewer();
    repo.items = [app('under_review')];
    await mount(
        tester,
        MfdReviewDetailScreen(
            applicationId: 'application-id', repository: repo));
    await tap(tester, 'Reject');
    await tap(tester, 'Confirm rejection');
    expect(find.text('This field is required.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('mfd-note')),
        'Insufficient registration evidence');
    await tap(tester, 'Confirm rejection');
    expect(repo.requests.single.operation, MfdOperation.reject);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.textContaining('Insufficient registration evidence'),
        findsOneWidget);
  });
  for (final operation in [MfdOperation.approve, MfdOperation.reject]) {
    testWidgets(
        '$operation retries exact decision after unknown network outcome',
        (tester) async {
      reviewer();
      repo.items = [app('under_review')];
      await mount(
          tester,
          MfdReviewDetailScreen(
              applicationId: 'application-id', repository: repo));
      await tap(
          tester, operation == MfdOperation.approve ? 'Approve' : 'Reject');
      await tester.enterText(
          find.byKey(const Key('mfd-note')), 'Manual review evidence');
      if (operation == MfdOperation.approve) {
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
      }
      repo.failure = Exception('raw transport secret');
      await tap(
          tester,
          operation == MfdOperation.approve
              ? 'Confirm approval'
              : 'Confirm rejection');
      expect(find.textContaining('raw transport'), findsNothing);
      repo.failure = null;
      await tap(tester, 'Retry safely');
      expect(repo.requests.length, 2);
      expect(identical(repo.requests.first, repo.requests.last), isTrue);
      expect(repo.requests.last.expectedVersion, 2);
    });
  }
  testWidgets('revoked platform context removes data and decision actions',
      (tester) async {
    reviewer();
    repo.items = [app('under_review')];
    await mount(
        tester,
        MfdReviewDetailScreen(
            applicationId: 'application-id', repository: repo));
    auth.updatePlatformContext(const PlatformContext());
    await tester.pump();
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Example Financial'), findsNothing);
    expect(find.text('Application review permission is required.'),
        findsOneWidget);
  });
  testWidgets('step-up loss while decision form is open disables confirm',
      (tester) async {
    reviewer();
    repo.items = [app('under_review')];
    await mount(
        tester,
        MfdReviewDetailScreen(
            applicationId: 'application-id', repository: repo));
    await tap(tester, 'Reject');
    auth.updatePlatformContext(const PlatformContext(
        isPlatformAdmin: true, capabilities: {'mfd_applications.review'}));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirm rejection'))
            .onPressed,
        isNull);
  });
  testWidgets('submission double click sends only one request while pending',
      (tester) async {
    await mount(tester, MfdApplicantScreen(repository: repo));
    await tap(tester, 'Apply as MFD');
    await tester.enterText(
        find.byKey(const Key('mfd-business')), 'Example Financial');
    await tester.enterText(find.byKey(const Key('mfd-arn')), 'ARN');
    repo.wait = Completer<void>();
    await tester.tap(find.text('Submit application'));
    await tester.pump();
    expect(repo.requests.length, 1);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Retry safely'))
            .onPressed,
        isNull);
    repo.wait!.complete();
    await tester.pumpAndSettle();
    expect(repo.requests.length, 1);
    expect(find.text('Submitted'), findsOneWidget);
  });
  testWidgets('Start review retry reuses its original request', (tester) async {
    reviewer(aal2: false);
    repo.items = [app('submitted')];
    repo.failure = Exception('network');
    await mount(
        tester,
        MfdReviewDetailScreen(
            applicationId: 'application-id', repository: repo));
    await tap(tester, 'Start review');
    repo.failure = null;
    await tap(tester, 'Retry start review safely');
    expect(repo.requests.length, 2);
    expect(identical(repo.requests.first, repo.requests.last), isTrue);
    expect(find.text('Under review'), findsOneWidget);
  });
  testWidgets('account change hides applicant history and pending form',
      (tester) async {
    repo.items = [app('submitted')];
    repo.eligible = false;
    await mount(tester, MfdApplicantScreen(repository: repo));
    auth.changeSession();
    await tester.pump();
    expect(find.text('Example Financial'), findsNothing);
    expect(
        find.textContaining('Your signed-in account changed'), findsOneWidget);
  });
  testWidgets('account change prevents pending form submission',
      (tester) async {
    await mount(tester, MfdApplicantScreen(repository: repo));
    await tap(tester, 'Apply as MFD');
    auth.changeSession();
    await tester.pump();
    expect(find.text('Submit application'), findsNothing);
    expect(
        find.textContaining('Your signed-in account changed'), findsOneWidget);
    expect(repo.requests, isEmpty);
  });
  test('known backend failures map to safe messages', () {
    for (final code in [
      'mfd_application_changed',
      'mfd_application_decided',
      'mfd_applicant_ineligible',
      'platform_admin_step_up_required',
      'platform_capability_required',
      'mfd_request_conflict'
    ]) {
      final text = mfdErrorMessage(PostgrestException(message: code));
      expect(text, isNot(contains(code)));
      expect(text, isNotEmpty);
    }
  });
  test('UUIDs have v4 format and independent entropy', () {
    final ids = List.generate(100, (_) => newMfdRequestId());
    expect(ids.toSet().length, 100);
    for (final id in ids) {
      expect(
          id,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    }
  });
  test(
      'Supabase mutation wire contract contains no applicant-controlled authority',
      () async {
    final calls = <Map<String, dynamic>>[];
    final client = SupabaseClient('http://localhost.invalid', 'synthetic-key',
        httpClient: MockClient((request) async {
      calls.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
          jsonEncode({
            'id': 'a',
            'business_name': 'B',
            'claimed_arn': 'A',
            'applicant_email': 'test@example.test',
            'status': 'submitted',
            'version': 1,
            'submitted_at': '2026-10-04T00:00:00Z'
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }));
    final repository = SupabaseMfdApplicationRepository(client);
    await repository.mutate(const MfdRequest(
        operation: MfdOperation.submit,
        requestId: 'request',
        businessName: 'B',
        claimedArn: 'A'));
    expect(calls.single.keys.toSet(), {
      'p_request_id',
      'p_business_name',
      'p_claimed_arn',
      'p_applicant_note'
    });
    await client.dispose();
  });
}
