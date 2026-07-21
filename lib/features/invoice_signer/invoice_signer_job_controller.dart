import 'dart:convert';
import 'dart:typed_data';

import '../../services/supabase_service.dart';
import 'models/invoice_document.dart';
import 'models/invoice_job.dart';
import 'processors/cams_processor.dart';
import 'processors/pdf_processor.dart';
import 'processors/signature_engine.dart';
import 'processors/zip_processor.dart';

class InvoiceSignerJobController {
  final PdfProcessor _pdfProcessor;
  final SignatureEngine _signatureEngine;
  final ZipProcessor _zipProcessor;
  final CamsProcessor _camsProcessor;

  InvoiceSignerJobController(SupabaseService supabaseService)
      : _pdfProcessor = const PdfProcessor(),
        _signatureEngine = SignatureEngine(supabaseService),
        _zipProcessor = ZipProcessor(supabaseService),
        _camsProcessor = CamsProcessor();

  Future<SigningJobResult> sign({
    required String sourceFileName,
    required String sourceBase64,
    required String signatureBase64,
    required String stampBase64,
    required SignaturePlacement placement,
  }) async {
    final isZip = sourceFileName.toLowerCase().endsWith('.zip');
    final originalDocuments = isZip
        ? await _zipProcessor.decrypt(sourceBase64)
        : [
            _pdfProcessor.createDocument(
              sourceFileName,
              base64Decode(sourceBase64),
            ),
          ];
    final outputDocuments = <InvoiceDocument>[];
    final signedNames = <String>{};

    for (final document in originalDocuments) {
      try {
        final signed = await _signatureEngine.sign(
          document: document,
          signatureBase64: signatureBase64,
          stampBase64: stampBase64,
          placement: placement,
        );
        outputDocuments.add(signed);
        signedNames.add(document.sourceFileName);
      } catch (_) {
        if (!isZip) rethrow;
        outputDocuments.add(document);
      }
    }

    if (isZip) {
      return SigningJobResult(
        outputBytes: _zipProcessor.package(
          documents: outputDocuments,
          signedFileNames: signedNames,
        ),
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
}
