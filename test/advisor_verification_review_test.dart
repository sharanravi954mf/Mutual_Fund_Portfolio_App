import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/verification_repository.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/verification_models.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/advisor_verification_queue_screen.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/advisor_verification_request_detail_screen.dart';

void main() {
  test('fake review repository returns its review projection', () async {
    final review = await _FakeRepository().getReview(_request.id);
    expect(review.maskedEmail, 'a•••@example.com');
    expect(review.request.status, VerificationStatus.pendingAdvisorReview);
  });

  test('repository contract passes only an opaque candidate token for approval',
      () async {
    final repository = _FakeRepository();

    await repository.approveCandidate(_request.id, 'opaque-token', 3);

    expect(repository.approvedCandidateToken, 'opaque-token');
    expect(repository.approvedProfileIds, isEmpty);
  });

  test('repository contract keeps rejection and more-information versioned',
      () async {
    final repository = _FakeRepository();

    await repository.reject(_request.id, 3, reasonCode: 'contact_changed');
    await repository.requestMoreInformation(_request.id, 3,
        reasonCode: 'confirm_contact');

    expect(repository.rejection, (_request.id, 3, 'contact_changed'));
    expect(repository.moreInformation, (_request.id, 3, 'confirm_contact'));
  });

  testWidgets('queue exposes loading, empty, and error states', (tester) async {
    await _setViewport(tester);
    final loading = Completer<List<VerificationRequest>>();
    final repository = _FakeRepository(queue: () => loading.future);
    await tester.pumpWidget(MaterialApp(
      home: AdvisorVerificationQueueScreen(repository: repository),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    loading.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('No verification requests match these filters.'),
        findsOneWidget);

    final failedRepository =
        _FakeRepository(queue: () => Future.error('denied'));
    await tester.pumpWidget(MaterialApp(
      home: AdvisorVerificationQueueScreen(
        key: UniqueKey(),
        repository: failedRepository,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('The verification queue is unavailable.'), findsOneWidget);
  });

  testWidgets('queue opens request detail and returns to the same queue',
      (tester) async {
    await _setViewport(tester);
    final repository = _FakeRepository();
    await tester.pumpWidget(MaterialApp(
      home: AdvisorVerificationQueueScreen(repository: repository),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Request request-'));
    await tester.pumpAndSettle();

    expect(find.text('Verification request detail'), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    expect(find.text('Verification review queue'), findsOneWidget);
    expect(repository.filters, isNotEmpty);
  });

  testWidgets('detail selects a candidate without exposing a profile id',
      (tester) async {
    await _setViewport(tester);
    final repository = _FakeRepository();
    await tester.pumpWidget(_detailHost(repository));
    await tester.tap(find.text('Open request detail'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Find investor candidate'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Priya');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Priya Shah'));
    await tester.tap(find.text('Use selected'));
    await tester.pumpAndSettle();

    expect(find.text('Priya Shah', skipOffstage: false), findsOneWidget);
    expect(repository.approvedProfileIds, isEmpty);
  });

  testWidgets('detail renders the available decision actions', (tester) async {
    await _setViewport(tester);
    final repository = _FakeRepository();
    await tester.pumpWidget(_detailHost(repository));
    await tester.tap(find.text('Open request detail'));
    await tester.pumpAndSettle();

    expect(find.text('Approve', skipOffstage: false), findsOneWidget);
    expect(find.text('Reject', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Request more information', skipOffstage: false),
      findsOneWidget,
    );
  });
}

Future<void> _setViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(const Size(1000, 1400));
}

Widget _detailHost(VerificationRepository repository) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AdvisorVerificationRequestDetailScreen(
                    requestId: _request.id,
                    repository: repository,
                  ),
                ),
              ),
              child: const Text('Open request detail'),
            ),
          ),
        ),
      ),
    );

final _request = VerificationRequest(
  id: 'request-12345678',
  method: VerificationMethod.advisorAssisted,
  status: VerificationStatus.pendingAdvisorReview,
  createdAt: DateTime.utc(2026, 7, 22),
  submittedAt: DateTime.utc(2026, 7, 22),
  version: 3,
  retryOfRequestId: 'request-old',
);

class _FakeRepository implements VerificationRepository {
  _FakeRepository({Future<List<VerificationRequest>> Function()? queue})
      : _queue = queue ?? (() async => [_request]);

  final Future<List<VerificationRequest>> Function() _queue;
  final List<VerificationQueueFilter> filters = [];
  String? approvedCandidateToken;
  final List<String> approvedProfileIds = [];
  (String, int, String)? rejection;
  (String, int, String)? moreInformation;

  @override
  Future<void> approve(String requestId, String profileId, int expectedVersion,
      {String? reasonCode}) async {
    approvedProfileIds.add(profileId);
  }

  @override
  Future<void> approveCandidate(
      String requestId, String candidateToken, int expectedVersion,
      {String? reasonCode}) async {
    approvedCandidateToken = candidateToken;
  }

  @override
  Future<void> approvePanCandidate(
      String requestId, String candidateToken, int expectedVersion,
      {String? reasonCode}) async {
    approvedCandidateToken = candidateToken;
  }

  @override
  Future<void> cancelRequest(String requestId, int expectedVersion) async {}

  @override
  Future<VerificationRequest> createRequest(VerificationMethod method) async =>
      _request;

  @override
  Future<PanVerificationSubmission> submitPanVerification(String pan) async =>
      const PanVerificationSubmission(
        requestId: 'request-12345678',
        status: VerificationStatus.pendingAdvisorReview,
        summary: PanVerificationSummary(
          maskedPan: '******1234',
          matchResult: VerificationMatchResult.singleMatch,
          conflictReason: VerificationConflictReason.none,
        ),
      );

  @override
  Future<List<VerificationEvent>> getHistory(String requestId) async =>
      const [];

  @override
  Future<AdvisorVerificationReview> getReview(String requestId) async =>
      AdvisorVerificationReview(
        request: _request,
        timeline: [
          VerificationEvent(
            id: 'event-1',
            type: 'submitted',
            createdAt: DateTime.utc(2026, 7, 22),
          ),
        ],
        maskedEmail: 'a•••@example.com',
        maskedMobile: '••••••1234',
      );

  @override
  Future<List<VerificationRequest>> getStatus() async => [_request];

  @override
  Future<void> reject(String requestId, int expectedVersion,
      {String? reasonCode}) async {
    rejection = (requestId, expectedVersion, reasonCode!);
  }

  @override
  Future<void> requestMoreInformation(String requestId, int expectedVersion,
      {required String reasonCode}) async {
    moreInformation = (requestId, expectedVersion, reasonCode);
  }

  @override
  Future<List<VerificationRequest>> reviewQueue(
      [VerificationQueueFilter filter = const VerificationQueueFilter()]) {
    filters.add(filter);
    return _queue();
  }

  @override
  Future<List<AdvisorVerificationCandidate>> searchCandidates(
          String requestId, String query) async =>
      const [
        AdvisorVerificationCandidate(
          token: 'opaque-token',
          name: 'Priya Shah',
          maskedEmail: 'p••••@example.com',
          maskedMobile: '••••••6789',
          profileSummary: 'Portfolio record available',
        ),
      ];
}
