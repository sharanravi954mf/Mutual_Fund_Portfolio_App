import 'dart:convert';

import '../../../services/supabase_service.dart';
import '../models/invoice_document.dart';
import '../models/invoice_job.dart';

class SignatureEngine {
  final SupabaseService _supabaseService;

  const SignatureEngine(this._supabaseService);

  Future<InvoiceDocument> sign({
    required InvoiceDocument document,
    required String signatureBase64,
    required String stampBase64,
    required SignaturePlacement placement,
  }) async {
    final response = await _supabaseService.client.functions.invoke(
      'sign-stamp-invoice',
      body: {
        'invoiceFile': base64Encode(document.pdfBytes),
        'signaturePng': signatureBase64,
        'stampPng': stampBase64,
        'stampX': placement.stampX.round(),
        'stampY': placement.stampY.round(),
        'sigX': placement.signatureX.round(),
        'sigY': placement.signatureY.round(),
        'stampW': placement.stampWidth.round(),
        'stampH': placement.stampHeight.round(),
        'sigW': placement.signatureWidth.round(),
        'sigH': placement.signatureHeight.round(),
      },
    );

    if (response.status != 200 || response.data == null) {
      throw Exception(response.data?['error'] ??
          'Failed to sign invoice. Server returned status code ${response.status}');
    }

    final data = response.data is String
        ? jsonDecode(response.data as String) as Map<String, dynamic>
        : Map<String, dynamic>.from(response.data as Map);
    return InvoiceDocument(
      sourceFileName: document.sourceFileName,
      pdfBytes: base64Decode(data['signedPdf'] as String),
    );
  }
}
