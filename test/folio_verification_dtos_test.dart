import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/folio_verification_dtos.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/folio_verification_models.dart';

void main() {
  test('maps every safe folio-list projection field', () {
    final record = const InvestorFolioRequestListRecordDto({
      'request_id': 'request-public-id',
      'version': 7,
      'registrar_display': 'KFintech',
      'masked_folio': '••••1234',
      'status': 'more_information_required',
      'submitted_at': '2026-07-23T10:15:00Z',
      // Sensitive fields from an unsafe response must not have a destination
      // in the domain model.
      'folio_number': 'RAWFOLIO1234',
      'normalized_folio_number': 'RAWFOLIO1234',
      'profile_id': 'profile-internal-id',
      'submission_token': 'opaque-token',
    }).toDomain();

    expect(record.requestId, 'request-public-id');
    expect(record.version, 7);
    expect(record.registrarDisplay, 'KFintech');
    expect(record.maskedFolio, '••••1234');
    expect(record.status, FolioVerificationStatus.moreInformationRequired);
    expect(record.submittedAt, DateTime.parse('2026-07-23T10:15:00Z'));
    expect(record.toString(), isNot(contains('RAWFOLIO1234')));
    expect(record.toString(), isNot(contains('profile-internal-id')));
    expect(record.toString(), isNot(contains('opaque-token')));
  });

  test('rejects malformed safe-list payloads', () {
    expect(
      () => const InvestorFolioRequestListRecordDto({
        'request_id': 'request-public-id',
        'version': 1,
        'registrar_display': 'CAMS',
        'masked_folio': '••••1234',
        'status': 'not-a-status',
        'submitted_at': null,
      }).toDomain(),
      throwsArgumentError,
    );
  });
}
