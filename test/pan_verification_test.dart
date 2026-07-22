import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/verification_repository.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/verification_models.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/pan_verification_submission_screen.dart';

void main() {
  test('PAN projection maps only masked safe values', () {
    final summary = PanVerificationSummary.fromJson({
      'masked_pan': '******1234',
      'pan_match_result': 'SINGLE_MATCH',
      'pan_conflict_reason': 'NONE',
    });

    expect(summary.maskedPan, '******1234');
    expect(summary.matchResult, VerificationMatchResult.singleMatch);
    expect(summary.conflictReason, VerificationConflictReason.none);
  });

  testWidgets('invalid PAN is rejected before repository submission',
      (tester) async {
    final repository = _FakePanRepository();
    await tester.pumpWidget(MaterialApp(
      home: PanVerificationSubmissionScreen(repository: repository),
    ));
    await tester.enterText(find.byType(TextField), 'invalid');
    await tester.tap(find.text('Submit securely'));
    await tester.pump();

    expect(find.textContaining('Enter a valid PAN'), findsOneWidget);
    expect(repository.submittedPan, isNull);
  });

  testWidgets('valid PAN is sent through the repository and masked on return',
      (tester) async {
    final repository = _FakePanRepository();
    await tester.pumpWidget(MaterialApp(
      home: PanVerificationSubmissionScreen(repository: repository),
    ));
    await tester.enterText(find.byType(TextField), 'abcde1234f');
    await tester.tap(find.text('Submit securely'));
    await tester.pumpAndSettle();

    expect(repository.submittedPan, 'ABCDE1234F');
  });
}

class _FakePanRepository implements VerificationRepository {
  String? submittedPan;

  @override
  Future<void> approve(String requestId, String profileId, int expectedVersion,
      {String? reasonCode}) async {}
  @override
  Future<void> approveCandidate(
      String requestId, String candidateToken, int expectedVersion,
      {String? reasonCode}) async {}
  @override
  Future<void> approvePanCandidate(
      String requestId, String candidateToken, int expectedVersion,
      {String? reasonCode}) async {}
  @override
  Future<void> cancelRequest(String requestId, int expectedVersion) async {}
  @override
  Future<VerificationRequest> createRequest(VerificationMethod method) =>
      throw UnimplementedError();
  @override
  Future<List<VerificationEvent>> getHistory(String requestId) async =>
      const [];
  @override
  Future<AdvisorVerificationReview> getReview(String requestId) =>
      throw UnimplementedError();
  @override
  Future<List<VerificationRequest>> getStatus() async => const [];
  @override
  Future<void> reject(String requestId, int expectedVersion,
      {String? reasonCode}) async {}
  @override
  Future<void> requestMoreInformation(String requestId, int expectedVersion,
      {required String reasonCode}) async {}
  @override
  Future<List<VerificationRequest>> reviewQueue(
          [VerificationQueueFilter filter =
              const VerificationQueueFilter()]) async =>
      const [];
  @override
  Future<List<AdvisorVerificationCandidate>> searchCandidates(
          String requestId, String query) async =>
      const [];
  @override
  Future<PanVerificationSubmission> submitPanVerification(String pan) async {
    submittedPan = pan;
    return const PanVerificationSubmission(
      requestId: 'request-id',
      status: VerificationStatus.pendingAdvisorReview,
      summary: PanVerificationSummary(
        maskedPan: '******1234',
        matchResult: VerificationMatchResult.singleMatch,
        conflictReason: VerificationConflictReason.none,
      ),
    );
  }
}
