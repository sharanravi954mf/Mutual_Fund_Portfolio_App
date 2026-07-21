import 'dart:typed_data';

class InvoiceDocument {
  final String sourceFileName;
  final Uint8List pdfBytes;

  const InvoiceDocument({
    required this.sourceFileName,
    required this.pdfBytes,
  });
}
