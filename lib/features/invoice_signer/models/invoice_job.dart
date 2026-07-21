import 'dart:typed_data';

import 'invoice_document.dart';

class SignaturePlacement {
  final double stampX;
  final double stampY;
  final double signatureX;
  final double signatureY;
  final double stampWidth;
  final double stampHeight;
  final double signatureWidth;
  final double signatureHeight;

  const SignaturePlacement({
    required this.stampX,
    required this.stampY,
    required this.signatureX,
    required this.signatureY,
    required this.stampWidth,
    required this.stampHeight,
    required this.signatureWidth,
    required this.signatureHeight,
  });
}

class SigningJobResult {
  final Uint8List outputBytes;
  final String outputFileName;
  final bool isZip;
  final int signedCount;
  final List<InvoiceDocument> documents;

  const SigningJobResult({
    required this.outputBytes,
    required this.outputFileName,
    required this.isZip,
    required this.signedCount,
    required this.documents,
  });
}

class ExcelUpdateResult {
  final Uint8List updatedBytes;
  final int updatedCount;

  const ExcelUpdateResult({
    required this.updatedBytes,
    required this.updatedCount,
  });
}
