import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/verification_models.dart';

void main() {
  test('only open verification states can be cancelled', () {
    expect(VerificationStatus.pendingAdvisorReview.canCancel, isTrue);
    expect(VerificationStatus.approved.canCancel, isFalse);
    expect(VerificationStatus.rejected.canRetry, isTrue);
    expect(VerificationStatus.approved.canRetry, isFalse);
  });

  test(
      'maps verification methods and statuses without accepting unknown values',
      () {
    expect(VerificationMethod.fromDatabase('advisor_assisted'),
        VerificationMethod.advisorAssisted);
    expect(VerificationStatus.fromDatabase('pending_advisor_review'),
        VerificationStatus.pendingAdvisorReview);
    expect(
        () => VerificationStatus.fromDatabase('active'), throwsArgumentError);
  });
}
