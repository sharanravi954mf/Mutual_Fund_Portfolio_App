import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/models/invoice_document.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/models/invoice_job.dart';

void main() {
  const failure = InvoiceSigningFailure(
    sourceFileName: 'invoice-11.pdf',
    reason: 'PDF could not be loaded.',
  );

  test('failed PDF diagnostic includes the file name and reason', () {
    expect(failure.diagnostic, 'invoice-11.pdf: PDF could not be loaded.');
  });

  test('signing result exposes batch failures without changing signed count',
      () {
    final result = SigningJobResult(
      outputBytes: Uint8List.fromList([1, 2, 3]),
      outputFileName: 'invoices_SIGNED.zip',
      isZip: true,
      signedCount: 1,
      documents: [
        InvoiceDocument(
          sourceFileName: 'invoice-10.pdf',
          pdfBytes: Uint8List(0),
        ),
        InvoiceDocument(
          sourceFileName: 'invoice-11.pdf',
          pdfBytes: Uint8List(0),
        ),
      ],
      failures: const [failure],
    );

    expect(result.hasFailures, isTrue);
    expect(result.signedCount, 1);
    expect(result.failureSummary, failure.diagnostic);
  });
}
