import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/verification_repository.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/verification_models.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/advisor_verification_queue_screen.dart';

void main() {
  testWidgets('advisor verification queue renders with a fake repository',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdvisorVerificationQueueScreen(
          repository: _FakeVerificationRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Verification review queue'), findsOneWidget);
    expect(
      find.text('No verification requests match these filters.'),
      findsOneWidget,
    );
  });

  test('dashboard maps the queue consistently in desktop and mobile navigation',
      () {
    final dashboard =
        File('lib/screens/admin_dashboard.dart').readAsStringSync();

    expect(dashboard, contains("_buildDrawerItem(1, t('verification_queue')"));
    expect(dashboard, contains("_buildSidebarItem(1, t('verification_queue')"));
    expect(
        dashboard,
        contains(
            'case 1:\n        return const AdvisorVerificationQueueScreen('));
    expect(dashboard, contains("? t('verification_queue')"));
    expect(dashboard, contains('if (index == 3)'));
  });
}

class _FakeVerificationRepository implements VerificationRepository {
  @override
  Future<void> approve(String requestId, String profileId, int expectedVersion,
      {String? reasonCode}) async {}

  @override
  Future<void> cancelRequest(String requestId, int expectedVersion) async {}

  @override
  Future<VerificationRequest> createRequest(VerificationMethod method) {
    throw UnimplementedError();
  }

  @override
  Future<PanVerificationSubmission> submitPanVerification(String pan) {
    throw UnimplementedError();
  }

  @override
  Future<List<VerificationEvent>> getHistory(String requestId) async =>
      const [];

  @override
  Future<List<VerificationRequest>> getStatus() async => const [];

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
  Future<void> approvePanCandidate(
      String requestId, String candidateToken, int expectedVersion,
      {String? reasonCode}) async {}
  @override
  Future<void> requestMoreInformation(String requestId, int expectedVersion,
      {required String reasonCode}) async {}
}
