import '../models/invoice_metadata.dart';

class KfintechInvoiceParser {
  static InvoiceMetadata parse(String sourceFileName, String text) {
    String? find(String pattern) => RegExp(pattern, caseSensitive: false)
        .firstMatch(text)
        ?.group(1)
        ?.trim();

    return InvoiceMetadata(
      sourceFileName: sourceFileName,
      invoiceNumber: find(r'Inv\s*serial\s*No\.?\s*:\s*([^\s]+)'),
      invoiceReferenceNumber: find(r'Reference\s*Number\s*:\s*([^\s]+)'),
      invoiceDate: find(r'\bDate\s*:\s*([0-9]{2}[/.-][0-9]{2}[/.-][0-9]{4})'),
      taxableValue: find(r'\b9971\d*\s+([0-9,]+(?:\.\d{1,2})?)'),
      igst: find(r'18\.00%\s+([0-9,]+(?:\.\d{1,2})?)'),
      cgst: find(r'CGST\s+SGST\s+IGST\s+.*?0\.00%\s+([0-9,]+(?:\.\d{1,2})?)'),
      sgst: find(r'0\.00%\s+([0-9,]+(?:\.\d{1,2})?)\s+18\.00%'),
    );
  }
}

class KfintechTrackerMatch {
  final int rowIndex;
  final InvoiceMetadata invoice;

  const KfintechTrackerMatch({
    required this.rowIndex,
    required this.invoice,
  });
}

class KfintechTrackerMatcher {
  static const _referenceHeader = 'invoice reference no';
  static const _invoiceNumberHeader = 'invoice no';
  static const _invoiceDateHeader = 'invoice date';
  static const _fileNameHeader = 'file name';

  static List<KfintechTrackerMatch> match({
    required List<String> headers,
    required List<List<String>> rows,
    required List<InvoiceMetadata> invoiceMetadata,
  }) {
    final normalizedHeaders = headers.map(_normalizeHeader).toList();
    final referenceIndex = normalizedHeaders.indexOf(_referenceHeader);
    final invoiceNumberIndex = normalizedHeaders.indexOf(_invoiceNumberHeader);
    final invoiceDateIndex = normalizedHeaders.indexOf(_invoiceDateHeader);
    final fileNameIndex = normalizedHeaders.indexOf(_fileNameHeader);
    if (referenceIndex == -1 ||
        invoiceNumberIndex == -1 ||
        invoiceDateIndex == -1 ||
        fileNameIndex == -1) {
      throw const FormatException('KFintech tracker headers are incomplete.');
    }

    final byReference = <String, InvoiceMetadata>{};
    for (final metadata in invoiceMetadata) {
      final reference = _normalizeReference(metadata.invoiceReferenceNumber);
      if (reference.isNotEmpty) {
        byReference.putIfAbsent(reference, () => metadata);
      }
    }

    final matches = <KfintechTrackerMatch>[];
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (referenceIndex >= row.length) continue;
      final metadata = byReference[_normalizeReference(row[referenceIndex])];
      if (metadata != null) {
        matches.add(KfintechTrackerMatch(
          rowIndex: rowIndex,
          invoice: metadata,
        ));
      }
    }
    return matches;
  }

  static String _normalizeHeader(String value) => value.toLowerCase().trim();

  static String _normalizeReference(String? value) =>
      (value ?? '').trim().toUpperCase();
}
