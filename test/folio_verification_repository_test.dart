import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/folio_verification_datasource.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/folio_verification_dtos.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/data/supabase_folio_verification_repository.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/models/folio_verification_models.dart';

void main() {
  test('maps request DTO into a safe domain entity', () {
    final request = const FolioVerificationRequestDto(_request).toDomain();
    expect(request.id, 'request-public-id');
    expect(request.status, FolioVerificationStatus.pendingAdvisorReview);
    expect(request.version, 1);
  });

  test('maps event DTO without exposing evidence values', () {
    final event = const FolioVerificationEventDto(_event).toDomain();
    expect(event.type, 'folio_submitted');
    expect(event.reasonCode, isNull);
    expect(event.toString(), isNot(contains('ABCDE1234F')));
  });

  test('forwards opaque token and correlation ID only to submission RPC',
      () async {
    final source = _FakeDatasource([_rpcResponse]);
    final repository = SupabaseFolioVerificationRepository(source);

    await repository.submit(
      const FolioSubmissionToken('opaque-token'),
      FolioHolderRelationship.soleHolder,
      'command-1',
    );

    expect(source.calls.single.function, 'submit_folio_verification');
    expect(source.calls.single.params['p_folio_token'], 'opaque-token');
    expect(source.calls.single.params['p_idempotency_key'], 'command-1');
    expect(source.calls.single.params.values.join(),
        isNot(contains('ABCDE1234F')));
  });

  test('forwards pagination once to the safe list RPC and maps its page',
      () async {
    final source = _FakeDatasource([
      [
        {
          'request_id': 'request-page-two',
          'version': 3,
          'registrar_display': 'CAMS',
          'masked_folio': '••••5678',
          'status': 'pending_advisor_review',
          'submitted_at': '2026-07-23T10:15:00Z',
        },
      ],
    ]);
    final repository = SupabaseFolioVerificationRepository(source);

    final result =
        await repository.getMyFolioRequestList(page: 2, pageSize: 10);

    expect(source.calls, hasLength(1));
    expect(source.calls.single.function, 'get_my_folio_requests');
    expect(source.calls.single.params, {
      'p_page': 2,
      'p_page_size': 10,
    });
    expect(result.page, 2);
    expect(result.pageSize, 10);
    expect(result.items, hasLength(1));
    expect(result.items.single.requestId, 'request-page-two');
    expect(result.items.single.maskedFolio, '••••5678');
  });

  test('forwards Advisor queue filtering to the assignment-safe RPC', () async {
    final source = _FakeDatasource([
      [
        {
          'request_id': 'request-advisor',
          'version': 2,
          'investor_display_label': 'Investor request',
          'registrar_display': 'CAMS',
          'masked_folio': '••••4321',
          'holder_relationship': 'SOLE_HOLDER',
          'status': 'under_review',
          'submitted_at': '2026-07-23T10:15:00Z',
          'updated_at': '2026-07-23T10:16:00Z',
        }
      ]
    ]);
    final repository = SupabaseFolioVerificationRepository(source);

    final result = await repository.getAssignedFolioQueue(
      const FolioQueueFilter(
        page: 1,
        pageSize: 10,
        status: FolioVerificationStatus.underReview,
      ),
    );

    expect(source.calls.single.function, 'get_my_advisor_folio_requests');
    expect(source.calls.single.params, {
      'p_page': 1,
      'p_page_size': 10,
      'p_status': 'under_review',
    });
    expect(result.items.single.maskedFolio, '••••4321');
    expect(result.items.single.registrarDisplay, 'CAMS');
  });

  test('maps assignment-safe Advisor detail without calling generic history',
      () async {
    final source = _FakeDatasource([
      [
        {
          'request_id': 'request-advisor',
          'version': 2,
          'investor_display_label': 'Investor request',
          'registrar_display': 'CAMS',
          'masked_folio': '••••4321',
          'holder_relationship': 'SOLE_HOLDER',
          'status': 'under_review',
          'event_summary': const [],
        }
      ]
    ]);
    final repository = SupabaseFolioVerificationRepository(source);

    final detail =
        await repository.getAssignedFolioRequestDetail('request-advisor');

    expect(source.calls.single.function, 'get_my_advisor_folio_request_detail');
    expect(source.calls.single.params, {'p_request_id': 'request-advisor'});
    expect(detail.history, isEmpty);
  });

  test('uses the dedicated folio history RPC rather than generic history',
      () async {
    final source = _FakeDatasource([const []]);
    final repository = SupabaseFolioVerificationRepository(source);

    await repository.getHistory('request-public-id');

    expect(source.calls.single.function, 'get_folio_verification_events');
    expect(source.calls.single.params, {'p_request_id': 'request-public-id'});
  });

  test('preserves typed failures from the safe-list RPC', () async {
    const failure =
        FolioVerificationFailure(FolioVerificationFailureCode.permissionDenied);
    final repository =
        SupabaseFolioVerificationRepository(_ThrowingDatasource(failure));

    expect(
      () => repository.getMyFolioRequestList(),
      throwsA(
        isA<FolioVerificationFailure>().having(
          (value) => value.code,
          'code',
          FolioVerificationFailureCode.permissionDenied,
        ),
      ),
    );
  });

  test('maps RPC transition failures to typed errors', () async {
    final repository = SupabaseFolioVerificationRepository(
      _ThrowingDatasource(StateError('Invalid folio lifecycle transition')),
    );
    expect(
      () => repository.beginReview('request-public-id', 1, 'command-1'),
      throwsA(
        isA<FolioVerificationFailure>().having(
          (failure) => failure.code,
          'code',
          FolioVerificationFailureCode.invalidTransition,
        ),
      ),
    );
  });

  test('maps timeout to typed timeout failure', () async {
    final repository = SupabaseFolioVerificationRepository(
      _DelayedDatasource(),
      timeout: const Duration(milliseconds: 1),
    );
    expect(
      () => repository.getMyRequests(),
      throwsA(
        isA<FolioVerificationFailure>().having(
          (failure) => failure.code,
          'code',
          FolioVerificationFailureCode.timeout,
        ),
      ),
    );
  });
}

const _request = {
  'id': 'request-public-id',
  'method_code': 'folio',
  'status': 'pending_advisor_review',
  'created_at': '2026-01-01T00:00:00Z',
  'version': 1,
};
const _event = {
  'id': 'event-public-id',
  'event_type': 'folio_submitted',
  'created_at': '2026-01-01T00:00:00Z',
};
const _rpcResponse = [_request];

class _Call {
  _Call(this.function, this.params);

  final String function;
  final Map<String, dynamic> params;
}

class _FakeDatasource implements FolioVerificationDatasource {
  _FakeDatasource(this.responses);

  final List<dynamic> responses;
  final calls = <_Call>[];

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    calls.add(_Call(function, params ?? {}));
    return responses.removeAt(0);
  }
}

class _ThrowingDatasource implements FolioVerificationDatasource {
  _ThrowingDatasource(this.error);

  final Object error;

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) =>
      Future.error(error);
}

class _DelayedDatasource implements FolioVerificationDatasource {
  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) =>
      Completer<dynamic>().future;
}
