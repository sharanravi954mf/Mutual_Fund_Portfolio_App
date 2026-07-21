import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/models/invoice_metadata.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/processors/kfintech_rules.dart';

void main() {
  const pdfText = '''
Date : 06/07/2026
Inv serial No. : AXTI/2026-27/003
Taxable Value
997152 11303.37 0.00% 0.00 0.00% 0.00 18.00% 2034.61
Reference Number: 128260601023443
''';

  test('extracts KFintech invoice fields', () {
    final metadata = KfintechInvoiceParser.parse('axis.pdf', pdfText);

    expect(metadata.sourceFileName, 'axis.pdf');
    expect(metadata.invoiceNumber, 'AXTI/2026-27/003');
    expect(metadata.invoiceReferenceNumber, '128260601023443');
    expect(metadata.invoiceDate, '06/07/2026');
    expect(metadata.taxableValue, '11303.37');
    expect(metadata.igst, '2034.61');
  });

  test('matches tracker rows by exact reference number', () {
    const metadata = InvoiceMetadata(
      sourceFileName: 'AXIS_ARN-153316_Jun26_ExclusiveGST.pdf',
      invoiceNumber: 'AXTI/2026-27/003',
      invoiceReferenceNumber: '128260601023443',
      invoiceDate: '06/07/2026',
    );
    final matches = KfintechTrackerMatcher.match(
      headers: const [
        'Invoice Reference No',
        'Invoice No',
        'Invoice Date',
        'File Name',
      ],
      rows: const [
        ['128260601023443', '', '', ''],
        ['128260601023444', '', '', ''],
      ],
      invoiceMetadata: const [metadata],
    );

    expect(matches, hasLength(1));
    expect(matches.single.rowIndex, 0);
    expect(matches.single.invoice, same(metadata));
  });

  test('reports incomplete KFintech tracker headers', () {
    expect(
      () => KfintechTrackerMatcher.match(
        headers: const ['Invoice Reference No', 'Invoice No'],
        rows: const [],
        invoiceMetadata: const [],
      ),
      throwsFormatException,
    );
  });
}
