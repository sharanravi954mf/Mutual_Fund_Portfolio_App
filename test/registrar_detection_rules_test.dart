import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/models/registrar_detection_result.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/processors/registrar_processor.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/services/registrar_detection_rules.dart';

void main() {
  group('RegistrarDetectionRules', () {
    test('identifies a KFintech tracker from all required headers', () {
      final result = RegistrarDetectionRules.detectTracker([
        const TrackerSheetSummary(
          headers: [
            'Invoice Reference No',
            'Invoice No',
            'Invoice Date',
            'FILE NAME',
          ],
          dataRowCount: 8,
        ),
      ]);

      expect(result.registrar, RegistrarType.kfintech);
      expect(result.status, RegistrarDetectionStatus.candidate);
      expect(result.trackerRows, 8);
    });

    test('identifies a CAMS tracker from multiple CAMS headers', () {
      final result = RegistrarDetectionRules.detectTracker([
        const TrackerSheetSummary(
          headers: ['CAMS INVOICE NUMBER', 'FILE NAME'],
          dataRowCount: 11,
        ),
      ]);

      expect(result.registrar, RegistrarType.cams);
      expect(result.status, RegistrarDetectionStatus.candidate);
      expect(result.trackerRows, 11);
    });

    test('stops at stage 1 for an unknown tracker', () {
      final result = RegistrarDetectionRules.detectTracker([
        const TrackerSheetSummary(
          headers: ['Fund', 'Amount'],
          dataRowCount: 3,
        ),
      ]);

      expect(result.status, RegistrarDetectionStatus.unknown);
      expect(result.registrar, isNull);
      expect(result.trackerRows, 3);
    });

    test('rejects a KFintech tracker paired with a flat multi-invoice archive',
        () {
      final tracker = RegistrarDetectionRules.detectTracker([
        const TrackerSheetSummary(
          headers: [
            'Invoice Reference No',
            'Invoice No',
            'Invoice Date',
            'FILE NAME',
          ],
          dataRowCount: 1,
        ),
      ]);
      final result = RegistrarDetectionRules.validateArchive(
        trackerResult: tracker,
        archive: const ArchiveStructureSummary(
          pdfArchivePaths: ['invoice-one.pdf', 'invoice-two.pdf'],
          nestedInvoiceBundleCount: 0,
        ),
      );

      expect(result.status, RegistrarDetectionStatus.unknown);
      expect(result.invoicesFound, 2);
    });

    test('rejects a KFintech nested PDF without its companion workbook', () {
      const tracker = RegistrarDetectionResult(
        registrar: RegistrarType.kfintech,
        status: RegistrarDetectionStatus.candidate,
        trackerRows: 1,
        invoicesFound: 0,
        reason: 'test',
      );
      final result = RegistrarDetectionRules.validateArchive(
        trackerResult: tracker,
        archive: const ArchiveStructureSummary(
          pdfArchivePaths: ['fund/invoice.zip!/invoice.pdf'],
          nestedInvoiceBundleCount: 0,
        ),
      );

      expect(result.status, RegistrarDetectionStatus.unknown);
    });

    test('confirms KFintech using the minimum invoice labels', () {
      final archive = RegistrarDetectionRules.validateArchive(
        trackerResult: const RegistrarDetectionResult(
          registrar: RegistrarType.kfintech,
          status: RegistrarDetectionStatus.candidate,
          trackerRows: 2,
          invoicesFound: 0,
          reason: 'test',
        ),
        archive: const ArchiveStructureSummary(
          pdfArchivePaths: ['fund/invoice.zip!/invoice.pdf'],
          nestedInvoiceBundleCount: 1,
        ),
      );
      final result = RegistrarDetectionRules.confirmPdf(
        archiveResult: archive,
        samplePdfText: 'Inv serial No: INV-1\nReference Number: REF-1',
      );

      expect(result.status, RegistrarDetectionStatus.confirmed);
      expect(result.registrar, RegistrarType.kfintech);
      expect(result.invoicesFound, 1);
    });

    test('accepts a single CAMS PDF before label confirmation', () {
      const tracker = RegistrarDetectionResult(
        registrar: RegistrarType.cams,
        status: RegistrarDetectionStatus.candidate,
        trackerRows: 1,
        invoicesFound: 0,
        reason: 'test',
      );
      final archive = RegistrarDetectionRules.validateArchive(
        trackerResult: tracker,
        archive: const ArchiveStructureSummary(
          pdfArchivePaths: ['Uploaded_Invoice.pdf'],
          nestedInvoiceBundleCount: 0,
        ),
      );
      final result = RegistrarDetectionRules.confirmPdf(
        archiveResult: archive,
        samplePdfText: 'Invoice No: CAMS-1',
      );

      expect(result.status, RegistrarDetectionStatus.confirmed);
      expect(result.registrar, RegistrarType.cams);
    });

    test('rejects an invoice whose labels disagree with the candidate', () {
      final archive = RegistrarDetectionRules.validateArchive(
        trackerResult: const RegistrarDetectionResult(
          registrar: RegistrarType.cams,
          status: RegistrarDetectionStatus.candidate,
          trackerRows: 1,
          invoicesFound: 0,
          reason: 'test',
        ),
        archive: const ArchiveStructureSummary(
          pdfArchivePaths: ['invoice.pdf'],
          nestedInvoiceBundleCount: 0,
        ),
      );
      final result = RegistrarDetectionRules.confirmPdf(
        archiveResult: archive,
        samplePdfText: 'Reference Number: REF-1',
      );

      expect(result.status, RegistrarDetectionStatus.unknown);
      expect(result.registrar, isNull);
    });
  });
}
