import 'package:flutter/foundation.dart';

import '../models/invoice_document.dart';
import '../models/invoice_job.dart';
import 'signature_engine.dart';

class BatchSigningResult {
  final List<InvoiceDocument> outputDocuments;
  final Set<String> signedNames;
  final Set<int> signedIndexes;
  final List<InvoiceSigningFailure> failures;

  const BatchSigningResult({
    required this.outputDocuments,
    required this.signedNames,
    required this.signedIndexes,
    required this.failures,
  });
}

class BatchSigningExecutor {
  final SignatureEngine _signatureEngine;

  const BatchSigningExecutor(this._signatureEngine);

  Future<BatchSigningResult> signSequentially({
    required List<InvoiceDocument> documents,
    required String signatureBase64,
    required String stampBase64,
    required SignaturePlacement placement,
    required bool isZip,
  }) async {
    final outputDocuments = <InvoiceDocument>[];
    final signedNames = <String>{};
    final signedIndexes = <int>{};
    final failures = <InvoiceSigningFailure>[];

    for (var index = 0; index < documents.length; index++) {
      final document = documents[index];
      try {
        final signed = await _signatureEngine.sign(
          document: document,
          signatureBase64: signatureBase64,
          stampBase64: stampBase64,
          placement: placement,
        );
        outputDocuments.add(signed);
        signedNames.add(document.sourceFileName);
        signedIndexes.add(index);
      } catch (error) {
        final reason = _failureReason(error);
        debugPrint(
          'Invoice Signer: failed to sign "${document.sourceFileName}": '
          '$reason',
        );
        failures.add(InvoiceSigningFailure(
          sourceFileName: document.sourceFileName,
          reason: reason,
        ));
        if (!isZip) {
          throw Exception(
            'Failed to sign ${document.sourceFileName}: $reason',
          );
        }
        outputDocuments.add(document);
      }
    }

    return BatchSigningResult(
      outputDocuments: outputDocuments,
      signedNames: signedNames,
      signedIndexes: signedIndexes,
      failures: failures,
    );
  }

  static String outputArchiveFileName(
    String sourceFileName, {
    required bool hasFailures,
  }) =>
      '${sourceFileName.substring(0, sourceFileName.length - 4)}'
      '${hasFailures ? '_PARTIAL.zip' : '_SIGNED.zip'}';

  static String _failureReason(Object error) {
    final reason = error.toString().replaceFirst('Exception: ', '').trim();
    return reason.isEmpty ? 'Unknown signing error.' : reason;
  }
}
