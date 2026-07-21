import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/services/invoice_pdf_discovery_service.dart';

void main() {
  Uint8List buildZip(Map<String, List<int>> entries) {
    final output = archive.Archive();
    for (final entry in entries.entries) {
      output.addFile(
          archive.ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    return Uint8List.fromList(archive.ZipEncoder().encode(output)!);
  }

  const discovery = InvoicePdfDiscoveryService();
  final pdf = Uint8List.fromList('%PDF-preview'.codeUnits);

  test('preview discovery returns the first PDF from a nested KFintech ZIP',
      () {
    final nested = buildZip({
      'tracker.xlsx': [1, 2, 3],
      'invoice.pdf': pdf,
    });
    final source = buildZip({
      'fund.zip': nested,
      'readme.txt': 'keep'.codeUnits,
    });

    final result = discovery.discoverFirst(
      sourceFileName: 'kfintech.zip',
      sourceBytes: source,
    );

    expect(result.sourceFileName, 'invoice.pdf');
    expect(result.pdfBytes, orderedEquals(pdf));
  });

  test('preview discovery returns a PDF from a flat CAMS ZIP', () {
    final source = buildZip({'cams.pdf': pdf});

    expect(
      discovery
          .discoverFirst(sourceFileName: 'cams.zip', sourceBytes: source)
          .sourceFileName,
      'cams.pdf',
    );
  });

  test('preview discovery returns a single PDF upload', () {
    expect(
      discovery
          .discoverFirst(sourceFileName: 'single.pdf', sourceBytes: pdf)
          .pdfBytes,
      orderedEquals(pdf),
    );
  });

  test('invalid or missing PDFs produce a friendly format error', () {
    final source = buildZip({
      'tracker.xlsx': [1, 2, 3]
    });

    expect(
      () => discovery.discoverFirst(
          sourceFileName: 'invalid.zip', sourceBytes: source),
      throwsA(isA<FormatException>()),
    );
  });
}
