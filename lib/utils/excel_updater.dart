// ignore_for_file: uri_does_not_exist
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:typed_data';
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'package:excel/excel.dart';
import 'package:archive/archive.dart' as archive;

class ExcelMetadataUpdater {
  static Future<String> extractPdfText(Uint8List pdfBytes) async {
    final promise = js.context.callMethod('extractPdfText', [pdfBytes]);
    final result = await js_util.promiseToFuture(promise);
    return result as String;
  }

  static Future<Map<String, dynamic>> updateExcelMetadata({
    required Uint8List excelBytes,
    required Uint8List zipBytes,
  }) async {
    // 1. Extract PDFs from ZIP or single PDF
    final pdfFiles = <Map<String, String>>[];
    final isZip = zipBytes.length > 4 &&
        zipBytes[0] == 0x50 &&
        zipBytes[1] == 0x4B &&
        zipBytes[2] == 0x03 &&
        zipBytes[3] == 0x04;

    if (isZip) {
      final dec = archive.ZipDecoder();
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
    } else {
      final text = await extractPdfText(zipBytes);
      pdfFiles.add({
        'filename': 'Uploaded_Invoice.pdf',
        'text': text,
      });
    }

    // 2. Load Excel workbook
    final excel = Excel.decodeBytes(excelBytes);
    int updatedCount = 0;

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

      final invoiceNoIndex = _findHeaderIndex(headers, ["invoice no", "invoiceno", "invoice number"]);
      final invoiceDateIndex = _findHeaderIndex(headers, ["invoice date", "invoicedate"]);
      final fileNameIndex = _findHeaderIndex(headers, ["file name", "filename"]);

      // If we don't have place to write output, skip
      if (invoiceNoIndex == -1 || invoiceDateIndex == -1) continue;

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
          final invNoRegex = RegExp(r'(?:invoice|inv|bill)\s*(?:no|number|ref\s*no)?\.?\s*[:\-\s]\s*([a-zA-Z0-9/\-_]+)', caseSensitive: false);
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
  }

  static int _findHeaderIndex(List<String> headers, List<String> targets) {
    for (final target in targets) {
      final idx = headers.indexOf(target);
      if (idx != -1) return idx;
    }
    return -1;
  }

  static void _updateCell(Sheet sheet, int row, int col, String value) {
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      TextCellValue(value),
    );
  }
}
