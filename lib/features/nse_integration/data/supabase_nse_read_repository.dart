import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/nse_models.dart';
import 'nse_read_repository.dart';

typedef NseRpcCall = Future<Object?> Function(
    String name, Map<String, dynamic> params);

class SupabaseNseReadRepository implements NseReadRepository {
  SupabaseNseReadRepository(SupabaseClient client)
      : _call =
            ((name, params) async => await client.rpc(name, params: params));
  SupabaseNseReadRepository.withRpc(this._call);
  final NseRpcCall _call;
  Future<T> _rpc<T>(String name, Map<String, dynamic> params,
      T Function(Map<String, dynamic>) parse) async {
    Object? response;
    try {
      response = await _call(name, params).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const NseFailure('NETWORK');
    }
    try {
      final envelope = nseObject(response);
      if (envelope['schema_version'] != 1) {
        throw const FormatException('Unsupported schema');
      }
      if (envelope['error'] != null) {
        final code = nseObject(envelope['error'])['code'];
        const known = {
          'NOT_AUTHORIZED',
          'TARGET_UNAVAILABLE',
          'INVALID_COMMAND',
          'BLOCKED_PREREQUISITE',
          'FEATURE_DISABLED',
          'REQUEST_CONFLICT',
          'OPERATION_IN_PROGRESS',
          'RATE_LIMITED',
          'TEMPORARILY_UNAVAILABLE'
        };
        throw NseFailure(
            known.contains(code) ? code as String : 'TEMPORARILY_UNAVAILABLE');
      }
      return parse(nseObject(envelope['data']));
    } on NseFailure {
      rethrow;
    } catch (_) {
      throw const NseFailure('INVALID_RESPONSE');
    }
  }

  @override
  Future<NsePage<NseTarget>> targets({String? after}) => _rpc(
      'list_nse_read_targets_v1',
      {'p_after': after},
      (data) => NsePage(
          (data['items'] as List)
              .map((x) => NseTarget.fromJson(nseObject(x)))
              .toList(),
          data['next_cursor']));
  @override
  Future<NseReadContext> context(String target) => _rpc(
      'get_nse_read_context_v1',
      {'p_target_ref': target},
      NseReadContext.fromJson);
  @override
  Future<NseAcceptance> submit(
      String target, String requestId, NseReadCommand command) async {
    final accepted = await _rpc(
        'submit_nse_read_v1',
        {
          'p_target_ref': target,
          'p_request_id': requestId,
          'p_command': command.toJson()
        },
        NseAcceptance.fromJson);
    if (accepted.requestId != requestId) {
      throw const NseFailure('INVALID_RESPONSE');
    }
    return accepted;
  }

  @override
  Future<NseOperation> operation(
      {String? operationId, String? requestId}) async {
    final result = await _rpc(
        'get_nse_read_operation_v1',
        {'p_operation_id': operationId, 'p_request_id': requestId},
        NseOperation.fromJson);
    if (operationId != null && result.id != operationId) {
      throw const NseFailure('INVALID_RESPONSE');
    }
    return result;
  }

  @override
  Future<NsePage<NseOperation>> history(String target, {Object? cursor}) =>
      _rpc(
          'list_nse_read_operations_v1',
          {
            'p_target_ref': target,
            if (cursor != null) ...{
              'p_before_time': nseObject(cursor)['before_time'],
              'p_before_id': nseObject(cursor)['before_id']
            }
          },
          (data) => NsePage(
              (data['items'] as List)
                  .map((x) => NseOperation.fromJson(nseObject(x)))
                  .toList(),
              data['next_cursor']));
  @override
  Future<NsePage<NseCandidate>> candidates(
          String target, NseReadKind kind, String source, {int after = -1}) =>
      _rpc(
          'list_nse_settlement_candidates_v1',
          {
            'p_target_ref': target,
            'p_kind': kind.wire,
            'p_source_operation_id': source,
            'p_after': after
          },
          (data) => NsePage(
              (data['items'] as List)
                  .map((x) => NseCandidate.fromJson(nseObject(x)))
                  .toList(),
              data['next_cursor']));
}
