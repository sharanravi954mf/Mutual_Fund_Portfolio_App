import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/order_models.dart';
import 'order_repository.dart';

class SupabaseOrderRepository implements OrderRepository {
  final SupabaseClient _client;

  SupabaseOrderRepository(this._client);

  @override
  Future<String> submitOrder(
    OrderDraft draft, {
    required String initiatedByProfileId,
    required String initiatedByRole,
    required String initiationChannel,
  }) async {
    final response = await _client
        .from('order_requests')
        .insert({
          'workspace_id': draft.workspaceId,
          'investor_profile_id': draft.investorProfileId,
          'scheme_code': draft.schemeCode,
          'type': draft.type.databaseValue,
          'amount': draft.amount,
          'units': draft.units,
          'status': 'pending_qualification',
          'initiated_by_profile_id': initiatedByProfileId,
          'initiated_by_role': initiatedByRole,
          'initiation_channel': initiationChannel,
        })
        .select('id')
        .single();

    return response['id'] as String;
  }

  @override
  Future<List<OrderFolio>> fetchFolios(String investorProfileId) async {
    try {
      final response = await _client
          .from('folio_grants')
          .select('*, folio_references(*)')
          .eq('profile_id', investorProfileId)
          .eq('status', 'active');

      final list = <OrderFolio>[];
      for (var row in (response as List)) {
        final ref = row['folio_references'] as Map<String, dynamic>?;
        if (ref != null) {
          list.add(OrderFolio(
            normalizedFolioNumber:
                ref['normalized_folio_number'] as String? ?? '',
            sourceFolioMasked: ref['source_folio_masked'] as String? ?? '',
            registrar: ref['registrar'] as String? ?? '',
          ));
        }
      }
      return list;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<OrderInvestor>> fetchAssignedInvestors(
      String advisorProfileId) async {
    try {
      // 1. Fetch active assignments
      final assignmentsRes = await _client
          .from('advisor_investor_assignments')
          .select('investor_id')
          .eq('advisor_id', advisorProfileId)
          .eq('status', 'active');

      final investorIds = (assignmentsRes as List)
          .map((row) => row['investor_id'] as String)
          .toList();

      if (investorIds.isEmpty) return [];

      // 2. Fetch profiles for those investor IDs
      final profilesRes = await _client
          .from('profiles')
          .select()
          .inFilter('id', investorIds)
          .eq('role',
              'client'); // wait, client is the investor role in the db profiles

      final list = <OrderInvestor>[];
      for (var row in (profilesRes as List)) {
        list.add(OrderInvestor(
          id: row['id'] as String,
          fullName: row['full_name'] as String? ?? 'Unnamed Investor',
          email: row['email'] as String?,
          phoneNumber: row['phone_number'] as String?,
        ));
      }
      return list;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMutualFunds() async {
    try {
      final response = await _client
          .from('mutual_funds')
          .select()
          .order('scheme_name', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }
}
