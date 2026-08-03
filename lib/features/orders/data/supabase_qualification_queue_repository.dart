import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/order_models.dart';
import '../domain/qualification_queue_models.dart';
import 'qualification_queue_repository.dart';

class SupabaseQualificationQueueRepository
    implements QualificationQueueRepository {
  SupabaseQualificationQueueRepository(this._client);

  factory SupabaseQualificationQueueRepository.fromDefaultClient() =>
      SupabaseQualificationQueueRepository(Supabase.instance.client);

  final SupabaseClient _client;

  @override
  Duration get fallbackRefreshInterval => const Duration(seconds: 4);

  @override
  Future<QualificationQueueSnapshot> fetchQueue({
    required String reviewerProfileId,
  }) async {
    try {
      final allowedWorkspaceIds =
          await _resolveAllowedWorkspaceIds(reviewerProfileId);
      if (allowedWorkspaceIds.isEmpty) {
        throw const QualificationQueueFailure(
          QualificationFailureKind.accessDenied,
          'This queue is available only to authorised MFD users.',
        );
      }

      final orderRows = await _client
          .from('order_requests')
          .select(
            'id, workspace_id, investor_profile_id, initiated_by_profile_id, '
            'initiated_by_role, initiation_channel, scheme_code, '
            'destination_scheme_code, type, amount, units, status, created_at',
          )
          .eq('status', OrderStatus.pendingReview.databaseValue)
          .inFilter('workspace_id', allowedWorkspaceIds.toList())
          .order('created_at', ascending: true)
          .order('id', ascending: true);

      final rows = List<Map<String, dynamic>>.from(orderRows as List);
      if (rows.isEmpty) {
        return QualificationQueueSnapshot(
          items: const [],
          fetchedAt: DateTime.now(),
        );
      }

      final profileIds = <String>{
        for (final row in rows) row['investor_profile_id'] as String,
        for (final row in rows) row['initiated_by_profile_id'] as String,
      };
      final schemeCodes = <String>{
        for (final row in rows) row['scheme_code'] as String,
        for (final row in rows)
          if ((row['destination_scheme_code'] as String?) != null)
            row['destination_scheme_code'] as String,
      };

      final profiles = await _fetchProfiles(profileIds);
      final funds = await _fetchFunds(schemeCodes);

      return QualificationQueueSnapshot(
        items: rows
            .where((row) =>
                row['status'] == OrderStatus.pendingReview.databaseValue)
            .map((row) => _mapOrder(row, profiles, funds))
            .toList(growable: false),
        fetchedAt: DateTime.now(),
      );
    } on QualificationQueueFailure {
      rethrow;
    } catch (error) {
      throw _mapFailure(error,
          fallback: 'The qualification queue is unavailable.');
    }
  }

  @override
  Future<void> qualifyOrder({
    required String orderId,
    required QualificationDecision decision,
    String? rejectionReason,
  }) async {
    try {
      await _client.rpc(
        'qualify_order',
        params: {
          'p_order_id': orderId,
          'p_decision': decision.databaseValue,
          'p_rejection_reason': decision == QualificationDecision.rejected
              ? rejectionReason
              : null,
        },
      );
    } catch (error) {
      throw _mapFailure(
        error,
        fallback: 'The order could not be qualified.',
      );
    }
  }

  @override
  QualificationQueueSubscription subscribeToOrderChanges(
    void Function() onChanged,
  ) {
    try {
      final channel = _client.channel('mfd-qualification-queue');
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'order_requests',
            callback: (_) => onChanged(),
          )
          .subscribe();
      return _SupabaseQualificationQueueSubscription(_client, channel);
    } catch (_) {
      return const NoopQualificationQueueSubscription();
    }
  }

  Future<Set<String>> _resolveAllowedWorkspaceIds(
    String reviewerProfileId,
  ) async {
    final memberships = await _client
        .from('workspace_memberships')
        .select('workspace_id, role')
        .eq('profile_id', reviewerProfileId)
        .inFilter('role', ['advisor', 'admin'])
        .eq('status', 'active')
        .isFilter('ended_at', null);

    final advisorWorkspaceIds = <String>{};
    final adminWorkspaceIds = <String>{};
    for (final row in List<Map<String, dynamic>>.from(memberships as List)) {
      final workspaceId = row['workspace_id'] as String?;
      final role = row['role'] as String?;
      if (workspaceId == null) continue;
      if (role == 'advisor') {
        advisorWorkspaceIds.add(workspaceId);
      } else if (role == 'admin') {
        adminWorkspaceIds.add(workspaceId);
      }
    }

    final allowedWorkspaceIds = <String>{...advisorWorkspaceIds};
    if (adminWorkspaceIds.isNotEmpty) {
      final workspaces = await _client
          .from('workspaces')
          .select('id, owner_profile_id')
          .inFilter('id', adminWorkspaceIds.toList());
      for (final row in List<Map<String, dynamic>>.from(workspaces as List)) {
        if (row['owner_profile_id'] == reviewerProfileId) {
          final workspaceId = row['id'] as String?;
          if (workspaceId != null) allowedWorkspaceIds.add(workspaceId);
        }
      }
    }
    return allowedWorkspaceIds;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfiles(
    Set<String> profileIds,
  ) async {
    if (profileIds.isEmpty) return const {};
    final rows = await _client
        .from('profiles')
        .select('id, full_name, email, phone_number')
        .inFilter('id', profileIds.toList());
    return {
      for (final row in List<Map<String, dynamic>>.from(rows as List))
        row['id'] as String: row,
    };
  }

  Future<Map<String, String>> _fetchFunds(Set<String> schemeCodes) async {
    if (schemeCodes.isEmpty) return const {};
    final rows = await _client
        .from('mutual_funds')
        .select('scheme_code, scheme_name')
        .inFilter('scheme_code', schemeCodes.toList());
    return {
      for (final row in List<Map<String, dynamic>>.from(rows as List))
        row['scheme_code'] as String: row['scheme_name'] as String,
    };
  }

  QualificationQueueItem _mapOrder(
    Map<String, dynamic> row,
    Map<String, Map<String, dynamic>> profiles,
    Map<String, String> funds,
  ) {
    final investorProfileId = row['investor_profile_id'] as String;
    final initiatorProfileId = row['initiated_by_profile_id'] as String;
    final investor = profiles[investorProfileId] ?? const {};
    final initiator = profiles[initiatorProfileId] ?? const {};
    final schemeCode = row['scheme_code'] as String;
    final destinationCode = row['destination_scheme_code'] as String?;

    return QualificationQueueItem(
      id: row['id'] as String,
      workspaceId: row['workspace_id'] as String,
      investorProfileId: investorProfileId,
      investorName: (investor['full_name'] as String?) ?? 'Unnamed investor',
      investorEmail: investor['email'] as String?,
      investorPhone: investor['phone_number'] as String?,
      initiatedByProfileId: initiatorProfileId,
      initiatorName: (initiator['full_name'] as String?) ?? 'Unknown initiator',
      initiatedByRole: (row['initiated_by_role'] as String?) ?? 'advisor',
      initiationChannel:
          (row['initiation_channel'] as String?) ?? 'advisor_console',
      status: OrderStatus.fromDatabase(row['status'] as String),
      type: OrderType.fromDatabase(row['type'] as String),
      schemeCode: schemeCode,
      schemeName: funds[schemeCode],
      destinationSchemeCode: destinationCode,
      destinationSchemeName:
          destinationCode == null ? null : funds[destinationCode],
      amount: _asDouble(row['amount']),
      units: _asDouble(row['units']),
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }

  static double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  QualificationQueueFailure _mapFailure(
    Object error, {
    required String fallback,
  }) {
    final text = '$error'.toLowerCase();
    if (text.contains('invalid_qualification_state') ||
        text.contains('already resolved') ||
        text.contains('pending_review') ||
        text.contains('not pending')) {
      return const QualificationQueueFailure(
        QualificationFailureKind.stale,
        'This order was already resolved. The queue was refreshed.',
      );
    }
    if (text.contains('not_authorized') ||
        text.contains('not authorized') ||
        text.contains('access denied') ||
        text.contains('permission') ||
        text.contains('row-level security') ||
        text.contains('order not found')) {
      return const QualificationQueueFailure(
        QualificationFailureKind.accessDenied,
        'You are not authorised to qualify this order.',
      );
    }
    if (text.contains('network') ||
        text.contains('connection') ||
        text.contains('socket') ||
        text.contains('timeout')) {
      return const QualificationQueueFailure(
        QualificationFailureKind.network,
        'The network connection is unavailable. Please try again.',
      );
    }
    return QualificationQueueFailure(
        QualificationFailureKind.unknown, fallback);
  }
}

class _SupabaseQualificationQueueSubscription
    implements QualificationQueueSubscription {
  const _SupabaseQualificationQueueSubscription(this._client, this._channel);

  final SupabaseClient _client;
  final RealtimeChannel _channel;

  @override
  Future<void> cancel() => _client.removeChannel(_channel);
}
