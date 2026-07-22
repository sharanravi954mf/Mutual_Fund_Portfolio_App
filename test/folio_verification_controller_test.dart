import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/application/folio_verification_service.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/folio_verification_models.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/folio_verification_controller.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/folio_verification_state.dart';

import 'support/folio_verification_fakes.dart';

void main() {
  FolioVerificationController controller(FolioTestRepository repository) =>
      FolioVerificationController(
        FolioVerificationService(repository, repository),
      );

  test('starts idle and refresh reaches ready once', () async {
    final repository = FolioTestRepository();
    final result = controller(repository);

    expect(result.state, isA<FolioVerificationIdle>());
    await result.refresh();

    expect(result.state, isA<FolioVerificationReady>());
    expect(repository.refreshCalls, 1);
  });

  test('refresh maps only safe records into presentation rows', () async {
    final result = controller(FolioTestRepository());

    await result.refresh();

    final ready = result.state as FolioVerificationReady;
    expect(ready.rows, hasLength(1));
    final row = ready.rows.single;
    expect(row.display.registrarDisplay, 'CAMS');
    expect(row.display.maskedFolio, '••••1234');
    expect(row.display.status, FolioVerificationStatus.pendingAdvisorReview);
    expect(row.display.submittedAt, isNull);
    expect(row.requestId, 'request');
    expect(row.version, 1);
    expect(row.display, isNot(isA<InvestorFolioRequestListRecord>()));
    expect(() => ready.rows.add(row), throwsUnsupportedError);
  });

  test('submit transitions ready and forwards correlation once', () async {
    final repository = FolioTestRepository();
    final result = controller(repository);

    await result.submit(
      const SubmitFolioVerificationCommand(
        token: FolioSubmissionToken('opaque'),
        relationship: FolioHolderRelationship.soleHolder,
        correlationId: 'corr',
      ),
    );

    expect(result.state, isA<FolioVerificationReady>());
    expect(repository.submitCalls, 1);
    expect(repository.correlation, 'corr');
  });

  test('failure is typed and retry reruns the safe-list operation', () async {
    final repository = FolioTestRepository()
      ..error = const FolioVerificationFailure(
        FolioVerificationFailureCode.staleVersion,
      );
    final result = controller(repository);

    await result.refresh();
    expect(result.state, isA<FolioVerificationFailureState>());
    repository.error = null;
    await result.retry();

    expect(result.state, isA<FolioVerificationReady>());
    expect(repository.refreshCalls, 2);
  });

  test('cancel invokes service once', () async {
    final repository = FolioTestRepository();
    final result = controller(repository);

    await result.cancel(
      const FolioVerificationDecisionCommand(
        requestId: 'request',
        expectedVersion: 1,
        correlationId: 'cancel',
      ),
    );

    expect(repository.cancelCalls, 1);
  });
}
