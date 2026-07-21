import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/models/processing_report.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/models/registrar_detection_result.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/processors/registrar_processor.dart';

void main() {
  test('uses a business-friendly source label from detection', () {
    const report = ProcessingReport(
      detection: RegistrarDetectionResult(
        registrar: RegistrarType.kfintech,
        status: RegistrarDetectionStatus.confirmed,
        trackerRows: 4,
        invoicesFound: 4,
        reason: 'internal',
      ),
      invoicesSigned: 4,
      trackerRowsUpdated: 3,
      unmatchedInvoices: 1,
    );

    expect(report.invoiceSourceLabel, 'KFintech');
    expect(report.unmatchedInvoices, 1);
  });
}
