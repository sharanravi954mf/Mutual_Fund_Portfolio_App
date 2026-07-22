import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/application/folio_verification_service.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/folio_verification_models.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/folio_verification_presentation_models.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/folio_verification_state.dart';

void main() {
  const display = FolioVerificationListItem(
    registrarDisplay: 'CAMS',
    maskedFolio: '••••1234',
    status: FolioVerificationStatus.pendingAdvisorReview,
    submittedAt: null,
  );
  const row = FolioVerificationRow(
    display: display,
    requestId: 'request',
    version: 1,
  );

  test('ready states compare their immutable presentation rows by value', () {
    const first = FolioVerificationReady(rows: [row]);
    const second = FolioVerificationReady(rows: [row]);

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test(
      'ready supports empty and populated states without altering failure state',
      () {
    const empty = FolioVerificationReady();
    const populated = FolioVerificationReady(rows: [row]);
    const failure = FolioVerificationFailureState(
      FolioVerificationApplicationFailure(
        FolioVerificationApplicationFailureCode.permissionDenied,
      ),
    );

    expect(empty.rows, isEmpty);
    expect(populated.rows, hasLength(1));
    expect(failure.failure.code,
        FolioVerificationApplicationFailureCode.permissionDenied);
  });
}
