import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;

import '../models/archive_manifest.dart';
import '../models/invoice_document.dart';

/// Finds eligible PDFs consistently for preview, detection, and processing.
class InvoicePdfDiscoveryService {
  const InvoicePdfDiscoveryService();

  InvoicePdfDiscoveryResult discoverAll({
    required String sourceFileName,
    required Uint8List sourceBytes,
  }) {
    if (_isPdf(sourceBytes)) {
      return InvoicePdfDiscoveryResult(
        documents: [
          InvoiceDocument(
            sourceFileName: sourceFileName,
            pdfBytes: sourceBytes,
          ),
        ],
      );
    }

    final manifest = ArchiveManifest.decode(sourceBytes);
    final entries = manifest.pdfEntries;
    return InvoicePdfDiscoveryResult(
      documents: entries
          .map(
            (entry) => InvoiceDocument(
              sourceFileName: entry.sourceFileName,
              pdfBytes: entry.pdfBytes,
            ),
          )
          .toList(),
      archiveManifest: manifest,
      archivePdfEntries: entries,
    );
  }

  /// Reads only the first eligible PDF for the visual preview.
  InvoiceDocument discoverFirst({
    required String sourceFileName,
    required Uint8List sourceBytes,
  }) {
    if (_isPdf(sourceBytes)) {
      return InvoiceDocument(
        sourceFileName: sourceFileName,
        pdfBytes: sourceBytes,
      );
    }
    return _discoverFirstInZip(sourceBytes);
  }

  InvoiceDocument _discoverFirstInZip(Uint8List zipBytes) {
    final decoded = archive.ZipDecoder().decodeBytes(zipBytes);
    for (final entry in decoded.files) {
      if (!entry.isFile || _isIgnored(entry.name)) continue;
      final bytes = Uint8List.fromList(entry.content as List<int>);
      if (entry.name.toLowerCase().endsWith('.pdf')) {
        return InvoiceDocument(
          sourceFileName: entry.name.split('/').last,
          pdfBytes: bytes,
        );
      }
      if (entry.name.toLowerCase().endsWith('.zip')) {
        try {
          return _discoverFirstInZip(bytes);
        } catch (_) {
          // Continue looking when a nested ZIP is unreadable.
        }
      }
    }
    throw const FormatException('No eligible PDF invoice was found.');
  }

  static bool _isPdf(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;

  static bool _isIgnored(String name) =>
      name.contains('__MACOSX') || name.split('/').last.startsWith('._');
}

class InvoicePdfDiscoveryResult {
  final List<InvoiceDocument> documents;
  final ArchiveManifest? archiveManifest;
  final List<ArchivePdfEntry>? archivePdfEntries;

  const InvoicePdfDiscoveryResult({
    required this.documents,
    this.archiveManifest,
    this.archivePdfEntries,
  });
}
