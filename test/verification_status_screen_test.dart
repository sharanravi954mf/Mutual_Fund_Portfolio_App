import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/verification_repository.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/verification_models.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/verification_status_screen.dart';

void main() {
  testWidgets('renders a pending investor verification request',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: VerificationStatusScreen(repository: _FakeRepository())));
    await tester.pump();
    expect(find.textContaining('Verification pending advisor review'),
        findsOneWidget);
    expect(find.text('Cancel request'), findsOneWidget);
  });
}

class _FakeRepository implements VerificationRepository {
  @override
  Future<void> approve(String requestId, String profileId, int expectedVersion,
      {String? reasonCode}) async {}
  @override
  Future<void> cancelRequest(String requestId, int expectedVersion) async {}
  @override
  Future<VerificationRequest> createRequest(VerificationMethod method) async =>
      _request;
  @override
  Future<List<VerificationEvent>> getHistory(String requestId) async =>
      const [];
  @override
  Future<List<VerificationRequest>> getStatus() async => [_request];
  @override
  Future<void> reject(String requestId, int expectedVersion,
      {String? reasonCode}) async {}
  @override
  Future<List<VerificationRequest>> reviewQueue(
          [VerificationQueueFilter filter =
              const VerificationQueueFilter()]) async =>
      const [];
  @override
  Future<AdvisorVerificationReview> getReview(String requestId) =>
      throw UnimplementedError();
  @override
  Future<List<AdvisorVerificationCandidate>> searchCandidates(
          String requestId, String query) async =>
      const [];
  @override
  Future<void> approveCandidate(
      String requestId, String candidateToken, int expectedVersion,
      {String? reasonCode}) async {}
  @override
  Future<void> requestMoreInformation(String requestId, int expectedVersion,
      {required String reasonCode}) async {}
}

final _request = VerificationRequest(
  id: 'request-1',
  method: VerificationMethod.advisorAssisted,
  status: VerificationStatus.pendingAdvisorReview,
  createdAt: DateTime.utc(2026),
  version: 1,
);
