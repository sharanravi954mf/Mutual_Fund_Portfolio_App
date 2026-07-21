import 'dart:typed_data';

import '../models/invoice_document.dart';

class PdfProcessor {
  const PdfProcessor();

  InvoiceDocument createDocument(String sourceFileName, Uint8List pdfBytes) {
    return InvoiceDocument(sourceFileName: sourceFileName, pdfBytes: pdfBytes);
  }
}
