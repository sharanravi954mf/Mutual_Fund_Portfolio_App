import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;

import '../../../utils/excel_updater.dart';
import '../models/archive_manifest.dart';
import '../models/registrar_detection_result.dart';
import 'registrar_detection_rules.dart';

typedef TrackerSummaryReader = Future<List<TrackerSheetSummary>> Function(
  Uint8List trackerBytes,
);
typedef PdfTextExtractor = Future<String> Function(Uint8List pdfBytes);

/// Performs progressive registrar detection without invoking a processor.
///
/// It reads the tracker first, then validates the archive shape, and extracts
/// text from one PDF only after those stages agree.
class RegistrarDetectionService {
  final TrackerSummaryReader _readTracker;
  final PdfTextExtractor _extractPdfText;

  RegistrarDetectionService({
    TrackerSummaryReader? readTracker,
    PdfTextExtractor? extractPdfText,
  })  : _readTracker = readTracker ?? _readTrackerSummary,
        _extractPdfText = extractPdfText ?? ExcelMetadataUpdater.extractPdfText;

  static Future<List<TrackerSheetSummary>> _readTrackerSummary(
    Uint8List trackerBytes,
  ) async {
    final summaries = await ExcelMetadataUpdater.readTrackerSummary(
      trackerBytes,
    );
    return summaries
        .map(
          (summary) => TrackerSheetSummary(
            headers: List<String>.from(summary['headers'] as List),
            dataRowCount: summary['dataRowCount'] as int,
          ),
        )
        .toList();
  }

  Future<RegistrarDetectionResult> detect({
    required Uint8List trackerBytes,
    required Uint8List archiveBytes,
  }) async {
    // Stage 1: recognize the tracker before reading the archive.
    final tracker = RegistrarDetectionRules.detectTracker(
      await _readTracker(trackerBytes),
    );
    if (tracker.status == RegistrarDetectionStatus.unknown) return tracker;

    // Stage 2: validate the expected archive shape before PDF.js work.
    ArchiveManifest? manifest;
    List<ArchivePdfEntry> pdfEntries;
    ArchiveStructureSummary archiveStructure;
    if (_isPdf(archiveBytes)) {
      pdfEntries = [
        ArchivePdfEntry(
          archivePath: 'Uploaded_Invoice.pdf',
          sourceFileName: 'Uploaded_Invoice.pdf',
          pdfBytes: archiveBytes,
        ),
      ];
      archiveStructure = const ArchiveStructureSummary(
        pdfArchivePaths: ['Uploaded_Invoice.pdf'],
        nestedInvoiceBundleCount: 0,
      );
    } else {
      try {
        manifest = ArchiveManifest.decode(archiveBytes);
      } catch (error) {
        return RegistrarDetectionResult.unknown(
          trackerRows: tracker.trackerRows,
          reason: 'Unable to read the invoice archive: $error',
        );
      }
      pdfEntries = manifest.pdfEntries;
      archiveStructure = _inspectArchiveStructure(manifest, archiveBytes);
    }
    final archive = RegistrarDetectionRules.validateArchive(
      trackerResult: tracker,
      archive: archiveStructure,
    );
    if (archive.status == RegistrarDetectionStatus.unknown) return archive;

    // Stage 3: one invoice is sufficient because the first two stages already
    // supplied multiple registrar-specific indicators.
    final sample = pdfEntries.first;
    try {
      return RegistrarDetectionRules.confirmPdf(
        archiveResult: archive,
        samplePdfText: await _extractPdfText(sample.pdfBytes),
      );
    } catch (error) {
      return RegistrarDetectionResult.unknown(
        trackerRows: archive.trackerRows,
        invoicesFound: archive.invoicesFound,
        reason: 'Unable to read the sample invoice: $error',
      );
    }
  }

  static bool _isPdf(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;

  static ArchiveStructureSummary _inspectArchiveStructure(
    ArchiveManifest manifest,
    Uint8List archiveBytes,
  ) {
    var nestedInvoiceBundleCount = 0;
    final outer = archive.ZipDecoder().decodeBytes(archiveBytes);
    for (final entry in outer.files) {
      if (!entry.isFile || !entry.name.toLowerCase().endsWith('.zip')) {
        continue;
      }
      try {
        final nested = archive.ZipDecoder().decodeBytes(
          Uint8List.fromList(entry.content as List<int>),
        );
        final files = nested.files.where((child) => child.isFile).toList();
        final hasPdf = files.any(
          (child) => child.name.toLowerCase().endsWith('.pdf'),
        );
        final hasCompanionWorkbook = files.any(
          (child) =>
              child.name.toLowerCase().endsWith('.xls') ||
              child.name.toLowerCase().endsWith('.xlsx'),
        );
        if (hasPdf && hasCompanionWorkbook) nestedInvoiceBundleCount++;
      } catch (_) {
        // An unreadable nested archive simply does not validate as KFintech.
      }
    }
    return ArchiveStructureSummary(
      pdfArchivePaths:
          manifest.pdfEntries.map((entry) => entry.archivePath).toList(),
      nestedInvoiceBundleCount: nestedInvoiceBundleCount,
    );
  }
}
