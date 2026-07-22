import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/folio_verification_models.dart';

void main() {
  test('serializes and parses only typed folio review reason codes', () {
    const code = FolioReviewReasonCode.verifiedJointHolder;

    expect(code.databaseValue, 'VERIFIED_JOINT_HOLDER');
    expect(
      FolioReviewReasonCode.fromDatabase('VERIFIED_JOINT_HOLDER'),
      code,
    );
    expect(
      () => FolioReviewReasonCode.fromDatabase('ARBITRARY_REASON'),
      throwsArgumentError,
    );
  });
}
