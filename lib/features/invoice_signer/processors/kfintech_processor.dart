import 'dart:typed_data';

import '../../../utils/excel_updater.dart';
import '../models/invoice_document.dart';
import '../models/invoice_job.dart';
import '../models/invoice_metadata.dart';
import 'kfintech_rules.dart';
import 'registrar_processor.dart';

class KfintechProcessor implements RegistrarProcessor {
  @override
  RegistrarType get registrarType => RegistrarType.kfintech;

  @override
  Future<List<InvoiceMetadata>> extractMetadata(
    List<InvoiceDocument> documents,
  ) async {
    final metadata = <InvoiceMetadata>[];
    for (final document in documents) {
      final text = await ExcelMetadataUpdater.extractPdfText(document.pdfBytes);
      metadata.add(parseMetadata(document.sourceFileName, text));
    }
    return metadata;
  }

  static InvoiceMetadata parseMetadata(String sourceFileName, String text) {
    return KfintechInvoiceParser.parse(sourceFileName, text);
  }

  @override
  Future<ExcelUpdateResult> updateTracker({
    required Uint8List trackerBytes,
    required List<InvoiceMetadata> invoiceMetadata,
    required String fileExtension,
  }) async {
    final result = await ExcelMetadataUpdater.updateKfintechMetadata(
      excelBytes: trackerBytes,
      invoiceMetadata: invoiceMetadata,
      fileExtension: fileExtension,
    );
    return ExcelUpdateResult(
      updatedBytes: result['updatedExcel'] as Uint8List,
      updatedCount: result['updatedCount'] as int,
    );
  }
}
