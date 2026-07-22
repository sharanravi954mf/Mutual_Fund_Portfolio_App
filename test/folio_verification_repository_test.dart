import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/folio_verification_datasource.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/folio_verification_dtos.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/supabase_folio_verification_repository.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/folio_verification_models.dart';

void main() {
  test('maps request DTO into a safe domain entity', () {
    final request = FolioVerificationRequestDto(_request).toDomain();
    expect(request.id, 'request-public-id');
    expect(request.status, FolioVerificationStatus.pendingAdvisorReview);
    expect(request.version, 1);
  });

  test('maps event DTO without exposing evidence values', () {
    final event = FolioVerificationEventDto(_event).toDomain();
    expect(event.type, 'folio_submitted');
    expect(event.reasonCode, isNull);
    expect(event.toString(), isNot(contains('ABCDE1234F')));
  });

  test('forwards opaque token and correlation ID only to submission RPC', () async {
    final source = _FakeDatasource([List<Map<String, Object?>>.from(_rpcResponse)]);
    final repository = SupabaseFolioVerificationRepository(source);
    await repository.submit(const FolioSubmissionToken('opaque-token'), FolioHolderRelationship.soleHolder, 'command-1');
    expect(source.calls.single.function, 'submit_folio_verification');
    expect(source.calls.single.params['p_folio_token'], 'opaque-token');
    expect(source.calls.single.params['p_idempotency_key'], 'command-1');
    expect(source.calls.single.params.values.join(), isNot(contains('ABCDE1234F')));
  });

  test('maps RPC transition failures to typed errors', () async {
    final repository = SupabaseFolioVerificationRepository(_ThrowingDatasource(StateError('Invalid folio lifecycle transition')));
    expect(() => repository.beginReview('request-public-id', 1, 'command-1'), throwsA(isA<FolioVerificationFailure>().having((failure) => failure.code, 'code', FolioVerificationFailureCode.invalidTransition)));
  });

  test('maps timeout to typed timeout failure', () async {
    final repository = SupabaseFolioVerificationRepository(_DelayedDatasource(), timeout: const Duration(milliseconds: 1));
    expect(() => repository.getMyRequests(), throwsA(isA<FolioVerificationFailure>().having((failure) => failure.code, 'code', FolioVerificationFailureCode.timeout)));
  });
}

const _request = {'id': 'request-public-id', 'method_code': 'folio', 'status': 'pending_advisor_review', 'created_at': '2026-01-01T00:00:00Z', 'version': 1};
const _event = {'id': 'event-public-id', 'event_type': 'folio_submitted', 'created_at': '2026-01-01T00:00:00Z'};
const _rpcResponse = [_request];
class _Call { _Call(this.function, this.params); final String function; final Map<String, dynamic> params; }
class _FakeDatasource implements FolioVerificationDatasource { _FakeDatasource(this.responses); final List<dynamic> responses; final calls = <_Call>[]; @override Future<dynamic> rpc(String function,{Map<String,dynamic>? params}) async { calls.add(_Call(function, params ?? {})); return responses.removeAt(0); } }
class _ThrowingDatasource implements FolioVerificationDatasource { _ThrowingDatasource(this.error); final Object error; @override Future<dynamic> rpc(String function,{Map<String,dynamic>? params}) => Future.error(error); }
class _DelayedDatasource implements FolioVerificationDatasource { @override Future<dynamic> rpc(String function,{Map<String,dynamic>? params}) => Completer<dynamic>().future; }
