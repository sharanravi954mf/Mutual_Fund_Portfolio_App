import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/application/folio_verification_service.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/folio_verification_models.dart'
    hide FolioVerificationPage;
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/folio_verification_controller.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/pages/folio_verification_page.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/widgets/folio_status_badge.dart';

import 'support/folio_verification_fakes.dart';

void main() {
  Future<FolioVerificationController> pumpPage(
    WidgetTester tester,
    FolioTestRepository repository, {
    Size size = const Size(1000, 900),
  }) async {
    final controller = FolioVerificationController(
      FolioVerificationService(repository, repository),
    );
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: FolioVerificationPage()),
      ),
    );
    await tester.pump();
    await tester.pump();
    return controller;
  }

  testWidgets('obtains the controller from Provider and renders a safe request',
      (tester) async {
    final repository = FolioTestRepository()
      ..safeRows = [
        _row(
          status: FolioVerificationStatus.pendingAdvisorReview,
          submittedAt: DateTime.utc(2026, 7, 23),
        ),
      ];

    await pumpPage(tester, repository);

    expect(find.text('Verify Mutual Fund Folio'), findsOneWidget);
    expect(find.text('CAMS'), findsOneWidget);
    expect(find.text('Folio ••••1234'), findsOneWidget);
    expect(find.textContaining('Submitted'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(repository.refreshCalls, 1);
  });

  testWidgets('renders an empty state while keeping the submission form',
      (tester) async {
    final repository = FolioTestRepository()..safeRows = const [];

    await pumpPage(tester, repository);

    expect(find.text('No verification requests yet'), findsOneWidget);
    expect(find.byKey(const Key('folio-number-field')), findsOneWidget);
  });

  testWidgets('validates all required submission fields', (tester) async {
    await pumpPage(tester, FolioTestRepository());

    await tester.tap(find.text('Submit verification'));
    await tester.pump();

    expect(find.text('Select a registrar.'), findsOneWidget);
    expect(find.text('Enter a folio number.'), findsOneWidget);
    expect(find.text('Select a relationship.'), findsOneWidget);
  });

  testWidgets('disables submission and prevents duplicate taps while pending',
      (tester) async {
    final repository = FolioTestRepository()
      ..pendingSubmit = Completer<FolioVerificationRequest>();
    await pumpPage(tester, repository);

    await _completeForm(tester);
    await tester.tap(find.text('Submit verification'));
    await tester.pump();

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Submitting…'),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('Submitting…'));
    await tester.pump();
    expect(repository.submitCalls, 1);

    repository.pendingSubmit!.complete(repository.request);
    await tester.pump();
    await tester.pump();
  });

  testWidgets('renders each supported status and only valid actions',
      (tester) async {
    final repository = FolioTestRepository()
      ..safeRows = [
        _row(status: FolioVerificationStatus.pendingAdvisorReview),
        _row(
          requestId: 'more',
          status: FolioVerificationStatus.moreInformationRequired,
        ),
        _row(requestId: 'approved', status: FolioVerificationStatus.approved),
        _row(requestId: 'rejected', status: FolioVerificationStatus.rejected),
      ];

    await pumpPage(tester, repository);

    expect(find.byType(FolioStatusBadge), findsNWidgets(4));
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('More information required'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Resubmit'), findsOneWidget);
  });

  testWidgets('delegates visible row actions through the controller',
      (tester) async {
    final repository = FolioTestRepository()
      ..safeRows = [
        _row(status: FolioVerificationStatus.pendingAdvisorReview),
        _row(
          requestId: 'more',
          status: FolioVerificationStatus.moreInformationRequired,
        ),
      ];
    await pumpPage(tester, repository);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump();
    expect(repository.cancelCalls, 1);

    await tester.tap(find.text('Resubmit'));
    await tester.pump();
    await tester.pump();
    expect(repository.resubmitCalls, 1);
  });

  testWidgets('renders a typed failure and retries through the controller',
      (tester) async {
    final repository = FolioTestRepository()
      ..error = const FolioVerificationFailure(
        FolioVerificationFailureCode.permissionDenied,
      );
    await pumpPage(tester, repository);

    expect(
      find.text('You do not have permission to complete this action.'),
      findsOneWidget,
    );
    repository.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(repository.refreshCalls, 2);
  });

  testWidgets('renders on a narrow viewport without overflow', (tester) async {
    final repository = FolioTestRepository();

    await pumpPage(tester, repository, size: const Size(360, 800));

    expect(tester.takeException(), isNull);
    expect(find.text('Verify Mutual Fund Folio'), findsOneWidget);
  });
}

InvestorFolioRequestListRecord _row({
  String requestId = 'pending',
  required FolioVerificationStatus status,
  DateTime? submittedAt,
}) =>
    InvestorFolioRequestListRecord(
      requestId: requestId,
      version: 1,
      registrarDisplay: 'CAMS',
      maskedFolio: '••••1234',
      status: status,
      submittedAt: submittedAt,
    );

Future<void> _completeForm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('folio-registrar-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('CAMS').last);
  await tester.pump();
  await tester.enterText(
    find.byKey(const Key('folio-number-field')),
    '12345678',
  );
  await tester.tap(find.byKey(const Key('folio-relationship-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sole holder').last);
  await tester.pump();
}
