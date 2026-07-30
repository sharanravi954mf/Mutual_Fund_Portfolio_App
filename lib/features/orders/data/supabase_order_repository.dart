import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/order_models.dart';
import 'order_repository.dart';

class SupabaseOrderRepository implements OrderRepository {
  final SupabaseClient _client;

  SupabaseOrderRepository(this._client);

  void _handleError(Object error) {
    final str = error.toString().toLowerCase();
    if (str.contains('auth') ||
        str.contains('permission') ||
        str.contains('violates row-level security')) {
      throw const AccessDeniedFailure(
          "Access Denied: You are not authorized to perform this operation.");
    }
    if (str.contains('network') ||
        str.contains('connection') ||
        str.contains('socket')) {
      throw const NetworkFailure(
          "Network Error: Please check your internet connection.");
    }
    throw ConfigurationFailure("Database Error: $error");
  }

  @override
  Future<String> submitOrder(OrderDraft draft) async {
    final ctx = draft.context;
    if (ctx == null) {
      throw const ConfigurationFailure("Order context is missing.");
    }

    // Direct database submission must start strictly as: status = pending_qualification
    // Section 4 validation: When the existing order_requests schema cannot persist Sell/Switch intent
    if (draft.type == OrderType.sell || draft.type == OrderType.switchOrder) {
      throw const ConfigurationFailure(
          "Sell and Switch orders are temporarily unavailable while the secure folio-order contract is being completed.");
    }

    try {
      final response = await _client
          .from('order_requests')
          .insert({
            'workspace_id': ctx.workspaceId,
            'investor_profile_id': ctx.investorProfileId,
            'scheme_code': draft.schemeCode,
            'type': draft.type.databaseValue,
            'amount': draft.amount,
            'units': draft.units,
            'status': 'pending_qualification',
            'initiated_by_profile_id': ctx.initiatorProfileId,
            'initiated_by_role': ctx.initiationRole,
            'initiation_channel': ctx.initiationChannel,
          })
          .select('id')
          .single();

      return response['id'] as String;
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  @override
  Future<List<OrderFolio>> fetchFolios(
      String investorProfileId, String workspaceId) async {
    try {
      // 1. Fetch portfolios matching client and workspace context
      final portfoliosRes = await _client
          .from('portfolios')
          .select('id')
          .eq('client_id', investorProfileId)
          .eq('workspace_id', workspaceId);

      final portfolioIds =
          (portfoliosRes as List).map((p) => p['id'] as String).toList();

      if (portfolioIds.isEmpty) return [];

      // 2. Fetch portfolio folio references joining folio references
      final response = await _client
          .from('portfolio_folio_references')
          .select('portfolio_id, folio_references(*)')
          .inFilter('portfolio_id', portfolioIds);

      final list = <OrderFolio>[];
      for (var row in (response as List)) {
        final ref = row['folio_references'] as Map<String, dynamic>?;
        if (ref != null) {
          final folioNumber = ref['normalized_folio_number'] as String? ?? '';
          list.add(OrderFolio(
            folioReferenceId: ref['id'] as String,
            portfolioId: row['portfolio_id'] as String? ?? '',
            maskedFolioDisplay: ref['source_folio_masked'] as String? ??
                (folioNumber.length > 4
                    ? '••••${folioNumber.substring(folioNumber.length - 4)}'
                    : '••••••••••'),
            registrar: ref['registrar'] as String? ?? 'CAMS',
          ));
        }
      }
      return list;
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  @override
  Future<List<OrderInvestor>> fetchAssignedInvestors(
      String advisorProfileId) async {
    try {
      // 1. Fetch workspaces where the advisor/admin has an active membership
      final workspacesRes = await _client
          .from('workspace_memberships')
          .select('workspace_id')
          .eq('profile_id', advisorProfileId)
          .inFilter('role', ['advisor', 'admin'])
          .eq('status', 'active')
          .isFilter('ended_at', null);

      final workspaceIds = (workspacesRes as List)
          .map((row) => row['workspace_id'] as String)
          .toList();

      if (workspaceIds.isEmpty) return [];

      // 2. Fetch active investor memberships in those workspaces
      final investorMembershipsRes = await _client
          .from('workspace_memberships')
          .select('profile_id, workspace_id')
          .inFilter('workspace_id', workspaceIds)
          .eq('role', 'investor')
          .eq('status', 'active')
          .isFilter('ended_at', null);

      final relationshipTuples = <Map<String, String>>[];
      final investorProfileIds = <String>{};
      for (var row in (investorMembershipsRes as List)) {
        final profileId = row['profile_id'] as String;
        final wsId = row['workspace_id'] as String;
        relationshipTuples.add({'profile_id': profileId, 'workspace_id': wsId});
        investorProfileIds.add(profileId);
      }

      if (relationshipTuples.isEmpty) return [];

      // 3. Fetch profiles for those active investor IDs
      final profilesRes = await _client
          .from('profiles')
          .select()
          .inFilter('id', investorProfileIds.toList());

      final profilesMap = {
        for (var p in (profilesRes as List)) p['id'] as String: p
      };

      final list = <OrderInvestor>[];
      for (var tuple in relationshipTuples) {
        final pid = tuple['profile_id']!;
        final wsId = tuple['workspace_id']!;
        final profile = profilesMap[pid];
        if (profile == null) continue;
        list.add(OrderInvestor(
          investorProfileId: pid,
          workspaceId: wsId,
          investorFullName: profile['full_name'] as String? ?? 'Unnamed Investor',
          email: profile['email'] as String?,
          phoneNumber: profile['phone_number'] as String?,
        ));
      }
      return list;
    } catch (e) {
      _handleError(e);
      rethrow;
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
      _handleError(e);
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> searchMutualFunds(String query) async {
    try {
      final response = await _client
          .from('mutual_funds')
          .select()
          .or('scheme_name.ilike.%$query%,scheme_code.ilike.%$query%')
          .order('scheme_name', ascending: true)
          .limit(20);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchHoldings(
      String investorProfileId, String workspaceId, String folioReferenceId) async {
    try {
      // 1. Fetch portfolios for the investor & workspace context
      final portfoliosRes = await _client
          .from('portfolios')
          .select('id')
          .eq('client_id', investorProfileId)
          .eq('workspace_id', workspaceId);

      final portfolioIds =
          (portfoliosRes as List).map((p) => p['id'] as String).toList();

      if (portfolioIds.isEmpty) return [];

      // 2. Filter portfolio matching folioReferenceId
      final referencesRes = await _client
          .from('portfolio_folio_references')
          .select('portfolio_id')
          .inFilter('portfolio_id', portfolioIds)
          .eq('folio_reference_id', folioReferenceId);

      if ((referencesRes as List).isEmpty) return [];

      final portfolioId = referencesRes.first['portfolio_id'] as String;

      // 3. Fetch all transactions in this single portfolio with mutual fund details
      final txsRes = await _client
          .from('transactions')
          .select('*, mutual_funds(*)')
          .eq('portfolio_id', portfolioId);

      final holdingsMap = <String, Map<String, dynamic>>{};
      for (var tx in (txsRes as List)) {
        final fund = tx['mutual_funds'] as Map<String, dynamic>?;
        if (fund == null) continue;
        final code = fund['scheme_code'] as String;
        final type = tx['transaction_type'] as String;
        final units = (tx['units'] as num).toDouble();

        final current = holdingsMap.putIfAbsent(
            code,
            () => {
                  'scheme_code': code,
                  'scheme_name': fund['scheme_name'] as String,
                  'units': 0.0,
                });

        if (type == 'BUY') {
          current['units'] = (current['units'] as double) + units;
        } else if (type == 'SELL') {
          current['units'] = (current['units'] as double) - units;
        }
      }

      return holdingsMap.values
          .where((h) => (h['units'] as double) > 0)
          .toList();
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  @override
  Future<OrderContext> resolveInvestorContext({
    required String investorProfileId,
    required String initiatorProfileId,
    required String initiationRole,
    required String initiationChannel,
  }) async {
    try {
      final profileRes = await _client
          .from('profiles')
          .select()
          .eq('id', investorProfileId)
          .maybeSingle();

      if (profileRes == null) {
        throw const AccessDeniedFailure("Investor profile not found.");
      }

      final fullName = profileRes['full_name'] as String? ?? 'Unnamed Investor';
      final email = profileRes['email'] as String?;
      final phone = profileRes['phone_number'] as String?;

      final portfolio = await _client
          .from('portfolios')
          .select('workspace_id')
          .eq('client_id', investorProfileId)
          .maybeSingle();

      String? workspaceId = portfolio?['workspace_id'] as String?;

      if (workspaceId == null) {
        final memberships = await _client
            .from('workspace_memberships')
            .select('workspace_id')
            .eq('profile_id', investorProfileId)
            .eq('role', 'investor')
            .eq('status', 'active')
            .isFilter('ended_at', null);

        if (memberships.isEmpty) {
          throw const EmptyFailure(
              "No active workspace membership found for this investor.");
        }
        if (memberships.length > 1) {
          throw const ConfigurationFailure(
              "Multiple active workspaces found for this investor. Context is ambiguous.");
        }
        workspaceId = memberships[0]['workspace_id'] as String;
      }

      return OrderContext(
        workspaceId: workspaceId,
        investorProfileId: investorProfileId,
        investorFullName: fullName,
        investorEmail: email,
        investorPhone: phone,
        initiatorProfileId: initiatorProfileId,
        initiationRole: initiationRole,
        initiationChannel: initiationChannel,
      );
    } catch (e) {
      if (e is OrderFailure) rethrow;
      throw ConfigurationFailure("Failed to resolve investor context: $e");
    }
  }
}
