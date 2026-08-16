import 'dart:convert';
import 'dart:typed_data';

import '../../services/supabase_service.dart';
import 'models/invoice_document.dart';
import 'models/invoice_job.dart';
import 'processors/batch_signing_executor.dart';
import 'processors/cams_processor.dart';
import 'processors/kfintech_processor.dart';
import 'processors/overlay_image_optimizer.dart';
import 'processors/registrar_processor.dart';
import 'processors/signature_engine.dart';
import 'processors/zip_processor.dart';
import 'services/invoice_pdf_discovery_service.dart';

class InvoiceSignerJobController {
  final SignatureEngine _signatureEngine;
  final ZipProcessor _zipProcessor;
  final CamsProcessor _camsProcessor;
  final KfintechProcessor _kfintechProcessor;
  final OverlayImageOptimizer _overlayImageOptimizer;
  final InvoicePdfDiscoveryService _pdfDiscoveryService;

  InvoiceSignerJobController(SupabaseService supabaseService)
      : _signatureEngine = SignatureEngine(supabaseService),
        _zipProcessor = ZipProcessor(supabaseService),
        _camsProcessor = CamsProcessor(),
        _kfintechProcessor = KfintechProcessor(),
        _overlayImageOptimizer = const OverlayImageOptimizer(),
        _pdfDiscoveryService = const InvoicePdfDiscoveryService();

  Future<SigningJobResult> sign({
    required String sourceFileName,
    required String sourceBase64,
    required String signatureBase64,
    required String stampBase64,
    required SignaturePlacement placement,
    RegistrarType? registrar,
  }) async {
    final isZip = sourceFileName.toLowerCase().endsWith('.zip');
    final sourceBytes = base64Decode(sourceBase64);
    InvoicePdfDiscoveryResult? discovered;
    try {
      discovered = _pdfDiscoveryService.discoverAll(
        sourceFileName: sourceFileName,
        sourceBytes: sourceBytes,
      );
    } catch (_) {
      if (!isZip) rethrow;
      // Retain the existing CAMS decrypt path for encrypted ZIP archives.
    }
    final originalDocuments =
        discovered != null && discovered.documents.isNotEmpty
            ? discovered.documents
            : isZip
                ? await _zipProcessor.decrypt(sourceBase64)
                : <InvoiceDocument>[];
    if (originalDocuments.isEmpty) {
      throw Exception('No eligible PDF invoices found.');
    }
    // Large transparent uploads can exhaust the Edge worker while pdf-lib
    // decodes them for every invoice. Resize them once per batch; their PDF
    // draw sizes and placement coordinates remain unchanged.
    final optimizedSignature =
        await _overlayImageOptimizer.optimizePngBase64(signatureBase64);
    final optimizedStamp =
        await _overlayImageOptimizer.optimizePngBase64(stampBase64);
    final batch = await BatchSigningExecutor(_signatureEngine).signSequentially(
      documents: originalDocuments,
      signatureBase64: optimizedSignature,
      stampBase64: optimizedStamp,
      placement: placement,
      isZip: isZip,
    );
    final outputDocuments = batch.outputDocuments;
    final signedNames = batch.signedNames;
    final signedIndexes = batch.signedIndexes;
    final failures = batch.failures;

    if (isZip) {
      final outputBytes = registrar == RegistrarType.kfintech
          ? ZipProcessor.packageFlatSignedPdfs([
              for (final index in signedIndexes) outputDocuments[index],
            ])
          : discovered?.archiveManifest != null &&
                  discovered?.archivePdfEntries != null &&
                  discovered!.archivePdfEntries!.isNotEmpty
              ? discovered.archiveManifest!.rebuild({
                  for (final index in signedIndexes)
                    discovered.archivePdfEntries![index].archivePath:
                        outputDocuments[index].pdfBytes,
                })
              : _zipProcessor.package(
                  documents: outputDocuments,
                  signedFileNames: signedNames,
                );
      return SigningJobResult(
        outputBytes: outputBytes,
        outputFileName: BatchSigningExecutor.outputArchiveFileName(
          sourceFileName,
          hasFailures: failures.isNotEmpty,
        ),
        isZip: true,
        signedCount: signedNames.length,
        documents: originalDocuments,
        failures: failures,
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
      failures: failures,
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
