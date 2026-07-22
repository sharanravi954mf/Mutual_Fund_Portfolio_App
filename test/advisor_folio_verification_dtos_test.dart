import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/advisor_folio_verification_dtos.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/folio_verification_models.dart';

void main() {
  test('maps the Advisor queue projection without canonical identifiers', () {
    final item = const AdvisorFolioVerificationQueueItemDto({
      'request_id': 'request-action-id',
      'version': 3,
      'investor_display_label': 'Investor request',
      'registrar_display': 'KFintech',
      'masked_folio': '••••6789',
      'holder_relationship': 'JOINT_HOLDER',
      'status': 'under_review',
      'submitted_at': '2026-07-23T10:00:00Z',
      'updated_at': '2026-07-23T11:00:00Z',
      'folio_reference_id': 'must-not-map',
      'profile_id': 'must-not-map',
      'normalized_folio_number': 'must-not-map',
    }).toDomain();

    expect(item.requestId, 'request-action-id');
    expect(item.maskedFolio, '••••6789');
    expect(item.status, FolioVerificationStatus.underReview);
    expect(item.holderRelationship, FolioHolderRelationship.jointHolder);
    expect(item.toString(), isNot(contains('must-not-map')));
  });

  test('maps an immutable safe Advisor event summary', () {
    final detail = const AdvisorFolioVerificationDetailDto({
      'request_id': 'request-action-id',
      'version': 4,
      'investor_display_label': 'Investor request',
      'registrar_display': 'CAMS',
      'masked_folio': '••••1234',
      'holder_relationship': 'SOLE_HOLDER',
      'status': 'more_information_required',
      'event_summary': [
        {
          'event_type': 'folio_information_requested',
          'previous_status': 'under_review',
          'new_status': 'more_information_required',
          'reason_code': 'INSUFFICIENT_DOCUMENTS',
          'created_at': '2026-07-23T10:00:00Z',
        }
      ],
    }).toDomain();

    expect(detail.history, hasLength(1));
    expect(detail.history.single.reasonCode, 'INSUFFICIENT_DOCUMENTS');
    expect(detail.history.single.newStatus,
        FolioVerificationStatus.moreInformationRequired);
    expect(() => detail.history.add(detail.history.single), throwsUnsupportedError);
  });
}
