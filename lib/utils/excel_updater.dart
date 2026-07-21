// ignore_for_file: uri_does_not_exist
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:js' as js;
import 'package:excel/excel.dart';
import 'package:archive/archive.dart' as archive;

class ExcelMetadataUpdater {
  static Future<String> extractPdfText(Uint8List pdfBytes) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    js.context.callMethod('extractPdfText', [pdfBytes, id]);

    final key = 'pdf_result_$id';
    while (true) {
      final res = js.context[key];
      if (res != null) {
        final error = res['error'];
        final text = res['text'];
        
        js.context[key] = null; // Clean up window object reference

        if (error != null) {
          throw Exception(error);
        }
        return text as String;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  static Future<Map<String, dynamic>> updateExcelMetadata({
    required Uint8List excelBytes,
    required Uint8List zipBytes,
    required String fileExtension,
    List<Map<String, dynamic>>? preDecryptedPdfs,
  }) async {
    // 1. Extract PDFs from ZIP or single PDF
    final pdfFiles = <Map<String, String>>[];
    
    if (preDecryptedPdfs != null && preDecryptedPdfs.isNotEmpty) {
      for (final pdfFile in preDecryptedPdfs) {
        final filename = (pdfFile['name'] ?? pdfFile['filename'] ?? '').split('/').last;
        final base64Content = pdfFile['content'] ?? pdfFile['base64'];
        if (base64Content != null) {
           final bytes = base64Decode(base64Content);
           try {
             final text = await extractPdfText(bytes);
             pdfFiles.add({'filename': filename, 'text': text});
           } catch (e) {
             // Skip if pdf.js fails on a specific file
           }
        }
      }
    } else {
      final isZip = zipBytes.length > 4 &&
          zipBytes[0] == 0x50 &&
          zipBytes[1] == 0x4B &&
          zipBytes[2] == 0x03 &&
          zipBytes[3] == 0x04;

      if (isZip) {
        final dec = archive.ZipDecoder();
        try {
          final archiveFile = dec.decodeBytes(zipBytes);
          for (final entry in archiveFile.files) {
            if (entry.isFile && entry.name.toLowerCase().endsWith('.pdf')) {
              if (entry.name.contains('__MACOSX') || entry.name.split('/').last.startsWith('._')) {
                continue;
              }
              final text = await extractPdfText(Uint8List.fromList(entry.content as List<int>));
              pdfFiles.add({
                'filename': entry.name.split('/').last,
                'text': text,
              });
            }
          }
        } catch (_) {
          // Fails if password protected and we didn't have preDecryptedPdfs
        }
      } else {
        final text = await extractPdfText(zipBytes);
        pdfFiles.add({
          'filename': 'Uploaded_Invoice.pdf',
          'text': text,
        });
      }
    }

    try {
      // 2. Try SheetJS (web runtime)
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final pdfFilesJson = jsonEncode(pdfFiles);
      js.context.callMethod('updateExcelMetadataJS', [excelBytes, pdfFilesJson, fileExtension, id]);

      final key = 'excel_result_$id';
      while (true) {
        final res = js.context[key];
        if (res != null) {
          final error = res['error'];
          final bytes = res['bytes'] as List<dynamic>?;
          final count = res['count'] as int? ?? 0;
          
          js.context[key] = null; // Clean up window object reference

          if (error != null) {
            throw Exception(error);
          }
          return {
            'updatedExcel': bytes != null ? Uint8List.fromList(bytes.cast<int>()) : excelBytes,
            'updatedCount': count,
          };
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
    } catch (e) {
      // 3. Fallback to standard Dart Excel parser (for mobile/unit tests)
      Excel? excel;
      try {
        excel = Excel.decodeBytes(excelBytes);
      } catch (_) {
        excel = null;
      }

      int updatedCount = 0;

      if (excel != null) {
        for (final table in excel.tables.keys) {
          final sheet = excel.tables[table]!;
          if (sheet.maxRows == 0) continue;

          // Identify headers
          final headers = <String>[];
          final firstRow = sheet.rows[0];
          for (final cell in firstRow) {
            headers.add((cell?.value?.toString() ?? '').toLowerCase().trim());
          }

          // Map header columns
          final gstrIndex = _findHeaderIndex(headers, ["amc gstr number", "gstr number", "gstin", "amcgstrnumber"]);
          final refNoIndex = _findHeaderIndex(headers, ["invoice reference no", "invoice ref no", "ref no", "invoicereferenceno"]);
          final amcIndex = _findHeaderIndex(headers, ["amc", "amc name", "fund house"]);
          final fundCodeIndex = _findHeaderIndex(headers, ["fund code", "fundcode"]);
          final taxableIndex = _findHeaderIndex(headers, ["taxable income", "taxable income amt", "taxable amt"]);
          final gstAmtIndex = _findHeaderIndex(headers, ["gst amt", "gst amount", "gstamt"]);

          final invoiceNoIndex = _findHeaderIndex(headers, ["invoice no", "invoiceno", "invoice number", "cams invoice no", "broker invoice no", "invoice"]);
          final invoiceDateIndex = _findHeaderIndex(headers, ["invoice date", "invoicedate", "payment month", "month", "date"]);
          final fileNameIndex = _findHeaderIndex(headers, ["file name", "filename", "file_name"]);

          // If we don't have place to write output, skip
          if (invoiceNoIndex == -1 && invoiceDateIndex == -1 && fileNameIndex == -1) continue;

          // Match each PDF
          for (final pdfFile in pdfFiles) {
            final text = pdfFile['text']!;
            final textLower = text.toLowerCase();
            final filename = pdfFile['filename']!;

            int bestRowIndex = -1;
            double highestScore = 0;

            for (int r = 1; r < sheet.maxRows; r++) {
              final row = sheet.rows[r];
              double score = 0;

              // GSTR Match
              if (gstrIndex != -1 && gstrIndex < row.length) {
                final val = row[gstrIndex]?.value?.toString().toLowerCase().trim() ?? '';
                if (val.isNotEmpty && textLower.contains(val)) score += 100;
              }

              // Invoice Ref No Match
              if (refNoIndex != -1 && refNoIndex < row.length) {
                final val = row[refNoIndex]?.value?.toString().toLowerCase().trim() ?? '';
                if (val.isNotEmpty && textLower.contains(val)) score += 100;
              }

              // AMC Name Match
              if (amcIndex != -1 && amcIndex < row.length) {
                final val = row[amcIndex]?.value?.toString().toLowerCase().trim() ?? '';
                if (val.isNotEmpty) {
                  final parts = val.split(RegExp(r'\s+')).where((p) => p.length > 2);
                  double amcMatchCount = 0;
                  for (final part in parts) {
                    if (textLower.contains(part)) amcMatchCount++;
                  }
                  if (amcMatchCount > 0) score += amcMatchCount * 15;
                  if (filename.toLowerCase().contains(val)) score += 40;
                }
              }

              // Fund Code Match
              if (fundCodeIndex != -1 && fundCodeIndex < row.length) {
                final val = row[fundCodeIndex]?.value?.toString().toLowerCase().trim() ?? '';
                if (val.isNotEmpty && textLower.contains(val)) score += 30;
              }

              // Taxable Match
              if (taxableIndex != -1 && taxableIndex < row.length) {
                final val = row[taxableIndex]?.value?.toString().toLowerCase().trim() ?? '';
                if (val.isNotEmpty && textLower.contains(val)) score += 15;
              }

              // GST Match
              if (gstAmtIndex != -1 && gstAmtIndex < row.length) {
                final val = row[gstAmtIndex]?.value?.toString().toLowerCase().trim() ?? '';
                if (val.isNotEmpty && textLower.contains(val)) score += 15;
              }

              if (score > highestScore) {
                highestScore = score;
                bestRowIndex = r;
              }
            }

            if (bestRowIndex != -1 && highestScore >= 25) {
              // Extract Invoice No (Standard CAMS format regex)
              final invNoRegex = RegExp(r'(?:invoice|inv|bill)\s*(?:serial\s*)?(?:no|number|ref\s*no)?\.?\s*[:\-\s]\s*([a-zA-Z0-9/\-_]+)', caseSensitive: false);
              final invNoMatch = invNoRegex.firstMatch(text);
              final invoiceNo = invNoMatch != null ? invNoMatch.group(1)?.trim() ?? '' : '';

              // Extract Invoice Date
              final dateRegex = RegExp(r'(?:invoice|inv|bill)?\s*date\s*[:\-\s]\s*([0-9]{2}[/\.\-\s][0-9]{2}[/\.\-\s][0-9]{4}|[0-9]{2}[/\.\-\s][a-zA-Z]{3}[/\.\-\s][0-9]{4})', caseSensitive: false);
              final dateMatch = dateRegex.firstMatch(text);
              final invoiceDate = dateMatch != null ? dateMatch.group(1)?.trim() ?? '' : '';

              // Update cells
              _updateCell(sheet, bestRowIndex, invoiceNoIndex, invoiceNo);
              _updateCell(sheet, bestRowIndex, invoiceDateIndex, invoiceDate);
              if (fileNameIndex != -1) {
                _updateCell(sheet, bestRowIndex, fileNameIndex, filename);
              }
              updatedCount++;
            }
          }
        }

        final updatedExcelBytes = excel.encode();
        return {
          'updatedExcel': updatedExcelBytes != null ? Uint8List.fromList(updatedExcelBytes) : excelBytes,
          'updatedCount': updatedCount,
        };
      } else {
        throw Exception("Unsupported Excel format (likely .xls). Please save it as .xlsx and try again, or run the app in a web browser for SheetJS support.");
      }
    }
  }

  static int _findHeaderIndex(List<String> headers, List<String> targets) {
    for (final target in targets) {
      final idx = headers.indexOf(target);
      if (idx != -1) return idx;
    }
    return -1;
  }

  static void _updateCell(Sheet sheet, int row, int col, String value) {
    if (col == -1) return;
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      TextCellValue(value),
    );
  }
}
