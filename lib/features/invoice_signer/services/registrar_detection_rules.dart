import '../models/registrar_detection_result.dart';
import '../processors/registrar_processor.dart';

/// Web-independent rules used by [RegistrarDetectionService]. Keeping these
/// rules free of browser APIs makes the progressive decision path testable.
class RegistrarDetectionRules {
  static const _camsHeaders = {'cams invoice number', 'file name'};
  static const _kfintechHeaders = {
    'invoice reference no',
    'invoice no',
    'invoice date',
    'file name',
  };

  static RegistrarDetectionResult detectTracker(
    List<TrackerSheetSummary> sheets,
  ) {
    final trackerRows = sheets.fold<int>(
      0,
      (count, sheet) => count + sheet.dataRowCount,
    );
    final allHeaders = <String>{
      for (final sheet in sheets) ...sheet.headers.map(_normalize),
    };

    if (_kfintechHeaders.every(allHeaders.contains)) {
      return RegistrarDetectionResult(
        registrar: RegistrarType.kfintech,
        status: RegistrarDetectionStatus.candidate,
        trackerRows: trackerRows,
        invoicesFound: 0,
        reason:
            'Tracker has the KFintech reference, invoice, date, and file headers.',
      );
    }
    if (_camsHeaders.every(allHeaders.contains)) {
      return RegistrarDetectionResult(
        registrar: RegistrarType.cams,
        status: RegistrarDetectionStatus.candidate,
        trackerRows: trackerRows,
        invoicesFound: 0,
        reason: 'Tracker has the CAMS invoice-number and file-name headers.',
      );
    }
    return RegistrarDetectionResult.unknown(
      trackerRows: trackerRows,
      reason: 'Tracker headers do not identify CAMS or KFintech.',
    );
  }

  static RegistrarDetectionResult validateArchive({
    required RegistrarDetectionResult trackerResult,
    required ArchiveStructureSummary archive,
  }) {
    final invoicesFound = archive.pdfArchivePaths.length;
    if (invoicesFound == 0) {
      return RegistrarDetectionResult.unknown(
        trackerRows: trackerResult.trackerRows,
        reason: 'Archive does not contain any PDF invoices.',
      );
    }

    final registrar = trackerResult.registrar;
    final hasNestedPdfs =
        archive.pdfArchivePaths.any((path) => path.contains('!/'));
    final allPdfsNested =
        archive.pdfArchivePaths.every((path) => path.contains('!/'));
    final isSingleDirectPdf = invoicesFound == 1 && !hasNestedPdfs;

    if (registrar == RegistrarType.kfintech &&
        ((allPdfsNested && archive.nestedInvoiceBundleCount == invoicesFound) ||
            isSingleDirectPdf)) {
      return RegistrarDetectionResult(
        registrar: registrar,
        status: RegistrarDetectionStatus.candidate,
        trackerRows: trackerResult.trackerRows,
        invoicesFound: invoicesFound,
        reason: allPdfsNested
            ? 'KFintech tracker matched nested PDF and companion-workbook bundles.'
            : 'KFintech tracker matched a single invoice PDF.',
      );
    }
    if (registrar == RegistrarType.cams && !hasNestedPdfs) {
      return RegistrarDetectionResult(
        registrar: registrar,
        status: RegistrarDetectionStatus.candidate,
        trackerRows: trackerResult.trackerRows,
        invoicesFound: invoicesFound,
        reason: 'CAMS tracker matched an archive with direct PDF invoices.',
      );
    }

    return RegistrarDetectionResult.unknown(
      trackerRows: trackerResult.trackerRows,
      invoicesFound: invoicesFound,
      reason: registrar == RegistrarType.kfintech
          ? 'KFintech tracker requires a single invoice PDF or nested PDF and companion-workbook bundles.'
          : 'CAMS tracker requires direct PDF invoices in the archive.',
    );
  }

  static RegistrarDetectionResult confirmPdf({
    required RegistrarDetectionResult archiveResult,
    required String samplePdfText,
  }) {
    final normalized = samplePdfText.toLowerCase();
    final registrar = archiveResult.registrar;
    final confirmed = switch (registrar) {
      RegistrarType.cams => normalized.contains('invoice no') ||
          normalized.contains('invoice number'),
      RegistrarType.kfintech => normalized.contains('reference number') &&
          normalized.contains('inv serial no'),
      null => false,
    };

    if (!confirmed) {
      return RegistrarDetectionResult.unknown(
        trackerRows: archiveResult.trackerRows,
        invoicesFound: archiveResult.invoicesFound,
        reason:
            'Sample invoice does not contain the expected $registrar labels.',
      );
    }
    return RegistrarDetectionResult(
      registrar: registrar,
      status: RegistrarDetectionStatus.confirmed,
      trackerRows: archiveResult.trackerRows,
      invoicesFound: archiveResult.invoicesFound,
      reason: 'Tracker, archive structure, and sample invoice labels agree.',
    );
  }

  static String _normalize(String value) => value.toLowerCase().trim();
}

class TrackerSheetSummary {
  final List<String> headers;
  final int dataRowCount;

  const TrackerSheetSummary({
    required this.headers,
    required this.dataRowCount,
  });
}

class ArchiveStructureSummary {
  final List<String> pdfArchivePaths;
  final int nestedInvoiceBundleCount;

  const ArchiveStructureSummary({
    required this.pdfArchivePaths,
    required this.nestedInvoiceBundleCount,
  });
}
