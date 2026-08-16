import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mutual_fund_portfolio_app/features/invoice_signer/models/invoice_document.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/models/invoice_job.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/processors/batch_signing_executor.dart';
import 'package:mutual_fund_portfolio_app/features/invoice_signer/processors/signature_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const placement = SignaturePlacement(
  stampX: 400,
  stampY: 102,
  signatureX: 420,
  signatureY: 72,
  stampWidth: 120,
  stampHeight: 60,
  signatureWidth: 120,
  signatureHeight: 50,
);

FunctionResponse signedResponse(Map<String, dynamic> body) {
  final source = base64Decode(body['invoiceFile'] as String);
  return FunctionResponse(
    status: 200,
    data: {
      'signedPdf': base64Encode(<int>[...source, 0x53]),
    },
  );
}

Future<InvoiceDocument> sign(
  SignatureEngine engine, {
  String filename = 'invoice.pdf',
}) {
  return engine.sign(
    document: InvoiceDocument(
      sourceFileName: filename,
      pdfBytes: Uint8List.fromList('%PDF-source'.codeUnits),
    ),
    signatureBase64: base64Encode('signature'.codeUnits),
    stampBase64: base64Encode('stamp'.codeUnits),
    placement: placement,
  );
}

void main() {
  test('11-document batch admits only one Edge invocation at a time', () async {
    var activeInvocations = 0;
    var maximumActiveInvocations = 0;
    var invocationCount = 0;
    final engine = SignatureEngine.withInvoker(
      invoke: (body) async {
        invocationCount++;
        activeInvocations++;
        maximumActiveInvocations = maximumActiveInvocations < activeInvocations
            ? activeInvocations
            : maximumActiveInvocations;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        activeInvocations--;
        return signedResponse(body);
      },
      delay: (_) async {},
    );
    final documents = List<InvoiceDocument>.generate(
      11,
      (index) => InvoiceDocument(
        sourceFileName: 'invoice-${index + 1}.pdf',
        pdfBytes: Uint8List.fromList('%PDF-${index + 1}'.codeUnits),
      ),
    );

    final result = await BatchSigningExecutor(engine).signSequentially(
      documents: documents,
      signatureBase64: base64Encode('signature'.codeUnits),
      stampBase64: base64Encode('stamp'.codeUnits),
      placement: placement,
      isZip: true,
    );

    expect(invocationCount, 11);
    expect(maximumActiveInvocations, 1);
    expect(result.signedIndexes.length, 11);
    expect(result.failures, isEmpty);
    for (var index = 0; index < documents.length; index++) {
      expect(result.outputDocuments[index].pdfBytes,
          isNot(documents[index].pdfBytes));
    }
  });

  test('546 worker limit is retried once after bounded backoff', () async {
    var invocationCount = 0;
    final delays = <Duration>[];
    final engine = SignatureEngine.withInvoker(
      invoke: (body) async {
        invocationCount++;
        if (invocationCount == 1) {
          throw const FunctionException(
            status: 546,
            details: {
              'code': 'WORKER_LIMIT',
              'message': 'Worker resource limit reached.',
            },
          );
        }
        return signedResponse(body);
      },
      delay: (delay) async => delays.add(delay),
    );

    final result = await sign(engine);

    expect(invocationCount, 2);
    expect(delays, const [Duration(milliseconds: 500)]);
    expect(utf8.decode(result.pdfBytes), endsWith('S'));
  });

  test('temporary network failure is retried once', () async {
    var invocationCount = 0;
    final engine = SignatureEngine.withInvoker(
      invoke: (body) async {
        invocationCount++;
        if (invocationCount == 1) {
          throw http.ClientException('connection reset');
        }
        return signedResponse(body);
      },
      delay: (_) async {},
    );

    await sign(engine);

    expect(invocationCount, 2);
  });

  test('permanent input failure is not retried', () async {
    var invocationCount = 0;
    final engine = SignatureEngine.withInvoker(
      invoke: (_) async {
        invocationCount++;
        throw const FunctionException(
          status: 400,
          details: {'error': 'Invalid PDF input.'},
        );
      },
      delay: (_) async {},
    );

    await expectLater(
      sign(engine),
      throwsA(
        predicate(
          (error) => error.toString().contains(
                'Invoice signing service failed (400): Invalid PDF input.',
              ),
        ),
      ),
    );
    expect(invocationCount, 1);
  });

  test('transient failures stop after one retry', () async {
    var invocationCount = 0;
    final engine = SignatureEngine.withInvoker(
      invoke: (_) async {
        invocationCount++;
        throw const FunctionException(
          status: 503,
          details: {'error': 'Worker failed to start.'},
        );
      },
      delay: (_) async {},
    );

    await expectLater(sign(engine), throwsException);
    expect(invocationCount, 2);
  });

  test('failed PDF remains diagnosed and partial archive is clearly named',
      () async {
    final engine = SignatureEngine.withInvoker(
      invoke: (body) async {
        final source = utf8.decode(base64Decode(body['invoiceFile'] as String));
        if (source.contains('failed')) {
          throw const FunctionException(
            status: 400,
            details: {'error': 'Malformed PDF.'},
          );
        }
        return signedResponse(body);
      },
      delay: (_) async {},
    );
    final failedBytes = Uint8List.fromList('%PDF-failed'.codeUnits);
    final documents = [
      InvoiceDocument(
        sourceFileName: 'valid.pdf',
        pdfBytes: Uint8List.fromList('%PDF-valid'.codeUnits),
      ),
      InvoiceDocument(
        sourceFileName: 'failed.pdf',
        pdfBytes: failedBytes,
      ),
    ];

    final result = await BatchSigningExecutor(engine).signSequentially(
      documents: documents,
      signatureBase64: base64Encode('signature'.codeUnits),
      stampBase64: base64Encode('stamp'.codeUnits),
      placement: placement,
      isZip: true,
    );

    expect(result.signedIndexes, {0});
    expect(result.outputDocuments[1].pdfBytes, same(failedBytes));
    expect(result.failures.single.sourceFileName, 'failed.pdf');
    expect(result.failures.single.reason, contains('Malformed PDF.'));
    expect(
      BatchSigningExecutor.outputArchiveFileName(
        'invoices.zip',
        hasFailures: true,
      ),
      'invoices_PARTIAL.zip',
    );
  });
}
