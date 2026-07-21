import 'package:flutter/foundation.dart';

import '../../../utils/excel_updater.dart';
import '../models/invoice_document.dart';
import '../models/invoice_job.dart';
import '../models/invoice_metadata.dart';
import 'registrar_processor.dart';

class CamsProcessor implements RegistrarProcessor {
  final Map<String, String> _extractedTextByFileName = {};

  @override
  RegistrarType get registrarType => RegistrarType.cams;

  @override
  Future<List<InvoiceMetadata>> extractMetadata(
    List<InvoiceDocument> documents,
  ) async {
    _extractedTextByFileName.clear();

    final metadata = <InvoiceMetadata>[];
    for (var index = 0; index < documents.length; index++) {
      metadata.add(
        await _extractDocumentMetadata(
          documents[index],
        ),
      );
    }
    return metadata;
  }

  Future<InvoiceMetadata> _extractDocumentMetadata(
      InvoiceDocument document) async {
    String text = '';
    try {
      text = await ExcelMetadataUpdater.extractPdfText(document.pdfBytes);
      _extractedTextByFileName[document.sourceFileName] = text;
    } catch (_) {
      // The existing Excel processor skips PDFs whose text cannot be extracted.
    }

    String? find(String pattern) => RegExp(pattern, caseSensitive: false)
        .firstMatch(text)
        ?.group(1)
        ?.trim();

    return InvoiceMetadata(
      sourceFileName: document.sourceFileName,
      invoiceNumber: find(
          r'(?:invoice|inv|bill)\s*(?:serial\s*)?(?:no|number|ref\s*no)?\.?\s*[:\-\s]\s*([a-zA-Z0-9/\-_]+)'),
      invoiceReferenceNumber: find(
          r'(?:reference|ref)\s*(?:number|no)?\.?\s*[:\-\s]\s*([a-zA-Z0-9/\-_]+)'),
      invoiceDate: find(
          r'(?:invoice|inv|bill)?\s*date\s*[:\-\s]\s*([0-9]{2}[/\.\-\s][0-9]{2}[/\.\-\s][0-9]{4}|[0-9]{2}[/\.\-\s][a-zA-Z]{3}[/\.\-\s][0-9]{4})'),
      taxableValue: find(
          r'taxable(?:\s+income|\s+value|\s+amount)?\s*[:\-\s]\s*([0-9,]+(?:\.[0-9]{1,2})?)'),
      igst: find(r'igst\s*[:\-\s]\s*([0-9,]+(?:\.[0-9]{1,2})?)'),
      cgst: find(r'cgst\s*[:\-\s]\s*([0-9,]+(?:\.[0-9]{1,2})?)'),
      sgst: find(r'sgst\s*[:\-\s]\s*([0-9,]+(?:\.[0-9]{1,2})?)'),
    );
  }

  @override
  Future<ExcelUpdateResult> updateTracker({
    required Uint8List trackerBytes,
    required List<InvoiceMetadata> invoiceMetadata,
    required String fileExtension,
  }) async {
    final extractedPdfText = invoiceMetadata
        .map((metadata) {
          final text = _extractedTextByFileName[metadata.sourceFileName];
          return text == null
              ? null
              : <String, String>{
                  'filename': metadata.sourceFileName,
                  'text': text,
                };
        })
        .whereType<Map<String, String>>()
        .toList();
    final result = await ExcelMetadataUpdater.updateExcelMetadata(
      excelBytes: trackerBytes,
      zipBytes: Uint8List(0),
      fileExtension: fileExtension,
      preExtractedPdfText: extractedPdfText,
    );
    return ExcelUpdateResult(
      updatedBytes: result['updatedExcel'] as Uint8List,
      updatedCount: result['updatedCount'] as int,
    );
  }
}
