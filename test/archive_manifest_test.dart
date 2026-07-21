import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:flutter_test/flutter_test.dart';

import 'package:mutual_fund_portfolio_app/features/invoice_signer/models/archive_manifest.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/models/invoice_document.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/processors/zip_processor.dart';

void main() {
  Uint8List buildZip(Map<String, List<int>> entries) {
    final output = archive.Archive();
    for (final entry in entries.entries) {
      output.addFile(
        archive.ArchiveFile(entry.key, entry.value.length, entry.value),
      );
    }
    return Uint8List.fromList(archive.ZipEncoder().encode(output)!);
  }

  Map<String, Uint8List> readZip(Uint8List bytes) {
    final decoded = archive.ZipDecoder().decodeBytes(bytes);
    return {
      for (final entry in decoded.files.where((entry) => entry.isFile))
        entry.name: Uint8List.fromList(entry.content as List<int>),
    };
  }

  test('rebuild replaces a flat PDF and preserves non-PDF entries', () {
    final source = buildZip({
      'invoice.pdf': '%PDF-original'.codeUnits,
      'notes.txt': 'keep me'.codeUnits,
    });
    final manifest = ArchiveManifest.decode(source);

    expect(manifest.pdfEntries, hasLength(1));
    expect(manifest.pdfEntries.single.archivePath, 'invoice.pdf');

    final rebuilt = manifest.rebuild({
      'invoice.pdf': Uint8List.fromList('%PDF-signed'.codeUnits),
    });
    final entries = readZip(rebuilt);

    expect(entries['invoice.pdf'], orderedEquals('%PDF-signed'.codeUnits));
    expect(entries['notes.txt'], orderedEquals('keep me'.codeUnits));
  });

  test('rebuild preserves nested ZIP hierarchy and companion XLSX bytes', () {
    final nested = buildZip({
      'invoice.pdf': '%PDF-original'.codeUnits,
      'invoice.xlsx': [0x50, 0x4B, 0x03, 0x04],
    });
    final source = buildZip({
      'fund/invoices.zip': nested,
      'outer-readme.txt': 'preserve outer file'.codeUnits,
    });
    final manifest = ArchiveManifest.decode(source);

    expect(manifest.pdfEntries, hasLength(1));
    expect(manifest.pdfEntries.single.archivePath,
        'fund/invoices.zip!/invoice.pdf');

    final rebuilt = manifest.rebuild({
      'fund/invoices.zip!/invoice.pdf':
          Uint8List.fromList('%PDF-signed'.codeUnits),
    });
    final outerEntries = readZip(rebuilt);
    final nestedEntries = readZip(outerEntries['fund/invoices.zip']!);

    expect(
        nestedEntries['invoice.pdf'], orderedEquals('%PDF-signed'.codeUnits));
    expect(
        nestedEntries['invoice.xlsx'], orderedEquals([0x50, 0x4B, 0x03, 0x04]));
    expect(
      outerEntries['outer-readme.txt'],
      orderedEquals('preserve outer file'.codeUnits),
    );
  });

  test('rebuild preserves ZIP entry order', () {
    final source = buildZip({
      'first.txt': 'first'.codeUnits,
      'invoice.pdf': '%PDF-original'.codeUnits,
      'last.txt': 'last'.codeUnits,
    });
    final manifest = ArchiveManifest.decode(source);
    final rebuilt = manifest.rebuild({
      'invoice.pdf': Uint8List.fromList('%PDF-signed'.codeUnits),
    });

    final names = archive.ZipDecoder()
        .decodeBytes(rebuilt)
        .files
        .where((entry) => entry.isFile)
        .map((entry) => entry.name)
        .toList();

    expect(names, orderedEquals(['first.txt', 'invoice.pdf', 'last.txt']));
  });

  test('flat KFintech output contains only signed PDFs with unique names', () {
    final flattened = ZipProcessor.packageFlatSignedPdfs([
      InvoiceDocument(
        sourceFileName: 'invoice.pdf',
        pdfBytes: Uint8List.fromList('%PDF-one'.codeUnits),
      ),
      InvoiceDocument(
        sourceFileName: 'invoice.pdf',
        pdfBytes: Uint8List.fromList('%PDF-two'.codeUnits),
      ),
    ]);
    final outputNames = archive.ZipDecoder()
        .decodeBytes(flattened)
        .files
        .where((entry) => entry.isFile)
        .map((entry) => entry.name)
        .toList();

    expect(outputNames, orderedEquals(['invoice.pdf', 'invoice_2.pdf']));
  });
}
