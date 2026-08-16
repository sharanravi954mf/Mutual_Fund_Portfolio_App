import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/supabase_service.dart';
import '../models/invoice_document.dart';
import '../models/invoice_job.dart';

class SignatureEngine {
  static const int _maxAttempts = 2;
  static const Set<int> _transientStatuses = {0, 503, 504, 546};

  final Future<FunctionResponse> Function(Map<String, dynamic> body) _invoke;
  final Future<void> Function(Duration delay) _delay;

  SignatureEngine(SupabaseService supabaseService)
      : this.withInvoker(
          invoke: (body) => supabaseService.client.functions.invoke(
            'sign-stamp-invoice',
            body: body,
          ),
        );

  @visibleForTesting
  SignatureEngine.withInvoker({
    required Future<FunctionResponse> Function(Map<String, dynamic> body)
        invoke,
    Future<void> Function(Duration delay)? delay,
  })  : _invoke = invoke,
        _delay = delay ?? Future<void>.delayed;

  Future<InvoiceDocument> sign({
    required InvoiceDocument document,
    required String signatureBase64,
    required String stampBase64,
    required SignaturePlacement placement,
  }) async {
    final body = <String, dynamic>{
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
    };

    late FunctionResponse response;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        response = await _invoke(body);
      } on FunctionException catch (error) {
        final reason = _functionFailureReason(error);
        if (_shouldRetry(error.status, attempt)) {
          await _waitBeforeRetry(document.sourceFileName, attempt, reason);
          continue;
        }
        throw Exception(
          'Invoice signing service failed (${error.status}): $reason',
        );
      } on http.ClientException catch (error) {
        if (attempt < _maxAttempts) {
          await _waitBeforeRetry(
            document.sourceFileName,
            attempt,
            'Temporary network failure.',
          );
          continue;
        }
        throw Exception(
          'Invoice signing service failed (network): ${error.message}',
        );
      } on TimeoutException {
        if (attempt < _maxAttempts) {
          await _waitBeforeRetry(
            document.sourceFileName,
            attempt,
            'Request timed out.',
          );
          continue;
        }
        throw Exception('Invoice signing service failed: request timed out.');
      }

      if (response.status == 200 && response.data != null) break;

      final reason = _responseFailureReason(response);
      if (_shouldRetry(response.status, attempt)) {
        await _waitBeforeRetry(document.sourceFileName, attempt, reason);
        continue;
      }
      throw Exception(
        'Invoice signing service failed (${response.status}): $reason',
      );
    }

    if (response.status != 200 || response.data == null) {
      throw Exception(
        'Invoice signing service failed (${response.status}): '
        '${_responseFailureReason(response)}',
      );
    }

    final data = response.data is String
        ? jsonDecode(response.data as String) as Map<String, dynamic>
        : Map<String, dynamic>.from(response.data as Map);
    return InvoiceDocument(
      sourceFileName: document.sourceFileName,
      pdfBytes: base64Decode(data['signedPdf'] as String),
    );
  }

  bool _shouldRetry(int status, int attempt) =>
      attempt < _maxAttempts && _transientStatuses.contains(status);

  Future<void> _waitBeforeRetry(
    String sourceFileName,
    int attempt,
    String reason,
  ) async {
    debugPrint(
      'Invoice Signer: transient failure for "$sourceFileName" '
      'on attempt $attempt; retrying once. $reason',
    );
    await _delay(Duration(milliseconds: 500 * attempt));
  }

  static String _functionFailureReason(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      final detailReason = details['error'] ?? details['message'];
      final code = details['code'];
      if (detailReason != null && code != null) {
        return '$code: $detailReason';
      }
      if (detailReason != null) return detailReason.toString();
    }
    return details?.toString() ?? error.reasonPhrase ?? 'Request failed.';
  }

  static String _responseFailureReason(FunctionResponse response) {
    final data = response.data;
    if (data is Map) {
      final detailReason = data['error'] ?? data['message'];
      final code = data['code'];
      if (detailReason != null && code != null) {
        return '$code: $detailReason';
      }
      if (detailReason != null) return detailReason.toString();
    }
    return data?.toString() ?? 'Request failed.';
  }
}
