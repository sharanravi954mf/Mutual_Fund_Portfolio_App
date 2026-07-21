import 'dart:typed_data';

import '../models/invoice_document.dart';
import '../models/invoice_job.dart';
import '../models/invoice_metadata.dart';

enum RegistrarType { cams, kfintech }

abstract interface class RegistrarProcessor {
  RegistrarType get registrarType;

  Future<List<InvoiceMetadata>> extractMetadata(
    List<InvoiceDocument> documents,
  );

  Future<ExcelUpdateResult> updateTracker({
    required Uint8List trackerBytes,
    required List<InvoiceMetadata> invoiceMetadata,
    required String fileExtension,
  });
}
