import 'dart:convert';
import 'dart:typed_data';

import '../../services/supabase_service.dart';
import 'models/archive_manifest.dart';
import 'models/invoice_document.dart';
import 'models/invoice_job.dart';
import 'processors/cams_processor.dart';
import 'processors/kfintech_processor.dart';
import 'processors/pdf_processor.dart';
import 'processors/registrar_processor.dart';
import 'processors/signature_engine.dart';
import 'processors/zip_processor.dart';

class InvoiceSignerJobController {
  final PdfProcessor _pdfProcessor;
  final SignatureEngine _signatureEngine;
  final ZipProcessor _zipProcessor;
  final CamsProcessor _camsProcessor;
  final KfintechProcessor _kfintechProcessor;

  InvoiceSignerJobController(SupabaseService supabaseService)
      : _pdfProcessor = const PdfProcessor(),
        _signatureEngine = SignatureEngine(supabaseService),
        _zipProcessor = ZipProcessor(supabaseService),
        _camsProcessor = CamsProcessor(),
        _kfintechProcessor = KfintechProcessor();

  Future<SigningJobResult> sign({
    required String sourceFileName,
    required String sourceBase64,
    required String signatureBase64,
    required String stampBase64,
    required SignaturePlacement placement,
  }) async {
    final isZip = sourceFileName.toLowerCase().endsWith('.zip');
    ArchiveManifest? archiveManifest;
    List<ArchivePdfEntry>? archivePdfEntries;
    final sourceBytes = base64Decode(sourceBase64);
    if (isZip) {
      try {
        archiveManifest = ArchiveManifest.decode(sourceBytes);
        archivePdfEntries = archiveManifest.pdfEntries;
      } catch (_) {
        // Retain the existing CAMS decrypt path for encrypted ZIP archives.
      }
    }
    final originalDocuments =
        archivePdfEntries != null && archivePdfEntries.isNotEmpty
            ? archivePdfEntries
                .map(
                  (entry) => InvoiceDocument(
                    sourceFileName: entry.sourceFileName,
                    pdfBytes: entry.pdfBytes,
                  ),
                )
                .toList()
            : isZip
                ? await _zipProcessor.decrypt(sourceBase64)
                : [
                    _pdfProcessor.createDocument(sourceFileName, sourceBytes),
                  ];
    final outputDocuments = <InvoiceDocument>[];
    final signedNames = <String>{};
    final signedIndexes = <int>{};

    for (var index = 0; index < originalDocuments.length; index++) {
      final document = originalDocuments[index];
      try {
        final signed = await _signatureEngine.sign(
          document: document,
          signatureBase64: signatureBase64,
          stampBase64: stampBase64,
          placement: placement,
        );
        outputDocuments.add(signed);
        signedNames.add(document.sourceFileName);
        signedIndexes.add(index);
      } catch (_) {
        if (!isZip) rethrow;
        outputDocuments.add(document);
      }
    }

    if (isZip) {
      final outputBytes = archiveManifest != null &&
              archivePdfEntries != null &&
              archivePdfEntries.isNotEmpty
          ? archiveManifest.rebuild({
              for (final index in signedIndexes)
                archivePdfEntries[index].archivePath:
                    outputDocuments[index].pdfBytes,
            })
          : _zipProcessor.package(
              documents: outputDocuments,
              signedFileNames: signedNames,
            );
      return SigningJobResult(
        outputBytes: outputBytes,
        outputFileName:
            '${sourceFileName.substring(0, sourceFileName.length - 4)}_SIGNED.zip',
        isZip: true,
        signedCount: signedNames.length,
        documents: originalDocuments,
      );
    }

    return SigningJobResult(
      outputBytes: outputDocuments.single.pdfBytes,
      outputFileName: sourceFileName.toLowerCase().endsWith('.pdf')
          ? '${sourceFileName.substring(0, sourceFileName.length - 4)}_SIGNED.pdf'
          : '${sourceFileName}_SIGNED.pdf',
      isZip: false,
      signedCount: 1,
      documents: originalDocuments,
    );
  }

  Future<ExcelUpdateResult> updateCamsTracker({
    required Uint8List trackerBytes,
    required String fileExtension,
    required List<InvoiceDocument> documents,
    required bool sourceWasZip,
  }) async {
    // The legacy direct-PDF path reports this exact fallback file name to the
    // Excel updater. Retain it while moving the flow behind the controller.
    final trackerDocuments = sourceWasZip
        ? documents
        : documents
            .map((document) => InvoiceDocument(
                  sourceFileName: 'Uploaded_Invoice.pdf',
                  pdfBytes: document.pdfBytes,
                ))
            .toList();
    final metadata = await _camsProcessor.extractMetadata(trackerDocuments);
    final result = await _camsProcessor.updateTracker(
      trackerBytes: trackerBytes,
      invoiceMetadata: metadata,
      fileExtension: fileExtension,
    );
    return result;
  }

  Future<ExcelUpdateResult> updateTracker({
    required RegistrarType registrar,
    required Uint8List trackerBytes,
    required String fileExtension,
    required List<InvoiceDocument> documents,
    required bool sourceWasZip,
  }) async {
    switch (registrar) {
      case RegistrarType.cams:
        return updateCamsTracker(
          trackerBytes: trackerBytes,
          fileExtension: fileExtension,
          documents: documents,
          sourceWasZip: sourceWasZip,
        );
      case RegistrarType.kfintech:
        final metadata = await _kfintechProcessor.extractMetadata(documents);
        return _kfintechProcessor.updateTracker(
          trackerBytes: trackerBytes,
          invoiceMetadata: metadata,
          fileExtension: fileExtension,
        );
    }
  }
}
