import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;

import '../../../services/supabase_service.dart';
import '../models/invoice_document.dart';

class ZipProcessor {
  final SupabaseService _supabaseService;

  const ZipProcessor(this._supabaseService);

  Future<List<InvoiceDocument>> decrypt(String sourceBase64) async {
    final response = await _supabaseService.client.functions.invoke(
      'sign-stamp-invoice',
      body: {'invoiceFile': sourceBase64, 'action': 'decrypt'},
    );
    if (response.status != 200 || response.data == null) {
      throw Exception(response.data?['error'] ??
          'Failed to decrypt CAMS zip. Status: ${response.status}');
    }
    final data = response.data is String
        ? jsonDecode(response.data as String) as Map<String, dynamic>
        : Map<String, dynamic>.from(response.data as Map);
    final files = data['files'] as List<dynamic>? ?? [];
    if (files.isEmpty) {
      throw Exception('No valid PDF invoices found inside the ZIP archive.');
    }
    return files.map((file) {
      final map = Map<String, dynamic>.from(file as Map);
      return InvoiceDocument(
        sourceFileName: map['name'] as String,
        pdfBytes: base64Decode(map['content'] as String),
      );
    }).toList();
  }

  Uint8List package({
    required List<InvoiceDocument> documents,
    required Set<String> signedFileNames,
  }) {
    final output = archive.Archive();
    for (final document in documents) {
      output.addFile(archive.ArchiveFile(
        document.sourceFileName,
        document.pdfBytes.length,
        document.pdfBytes,
      )..compress = signedFileNames.contains(document.sourceFileName));
    }
    final bytes = archive.ZipEncoder().encode(
      output,
      level: archive.Deflate.BEST_COMPRESSION,
    );
    if (bytes == null) {
      throw Exception('Failed to package signed files into output ZIP.');
    }
    return Uint8List.fromList(bytes);
  }
}
