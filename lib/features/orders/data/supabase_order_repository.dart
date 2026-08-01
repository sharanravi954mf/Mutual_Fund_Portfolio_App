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
    throw const ConfigurationFailure(
        "Database Error: An unexpected error occurred while processing the request.");
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
            'initiated_by_role':
                ctx.initiationRole == 'admin' ? 'advisor' : ctx.initiationRole,
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
      // 1. Fetch active memberships
      final membershipsRes = await _client
          .from('workspace_memberships')
          .select('workspace_id, role')
          .eq('profile_id', advisorProfileId)
          .inFilter('role', ['advisor', 'admin'])
          .eq('status', 'active')
          .isFilter('ended_at', null);

      final membershipRows = (membershipsRes as List);
      if (membershipRows.isEmpty) return [];

      // Separate workspace IDs by role
      final advisorWorkspaceIds = <String>[];
      final adminWorkspaceIds = <String>[];
      for (var row in membershipRows) {
        final wsId = row['workspace_id'] as String;
        final role = row['role'] as String;
        if (role == 'advisor') {
          advisorWorkspaceIds.add(wsId);
        } else if (role == 'admin') {
          adminWorkspaceIds.add(wsId);
        }
      }

      final allowedWorkspaceIds = <String>{...advisorWorkspaceIds};

      // For admin memberships, verify ownership of the workspace
      if (adminWorkspaceIds.isNotEmpty) {
        final workspacesRes = await _client
            .from('workspaces')
            .select('id, owner_profile_id')
            .inFilter('id', adminWorkspaceIds);

        for (var ws in (workspacesRes as List)) {
          final wsId = ws['id'] as String;
          final ownerId = ws['owner_profile_id'] as String?;
          if (ownerId == advisorProfileId) {
            allowedWorkspaceIds.add(wsId);
          }
        }
      }

      if (allowedWorkspaceIds.isEmpty) return [];

      // 2. Fetch active investor memberships in those workspaces
      final investorMembershipsRes = await _client
          .from('workspace_memberships')
          .select('profile_id, workspace_id')
          .inFilter('workspace_id', allowedWorkspaceIds.toList())
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
          investorFullName:
              profile['full_name'] as String? ?? 'Unnamed Investor',
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
  Future<List<Map<String, dynamic>>> fetchInitialMutualFunds(
      {int limit = 20}) async {
    try {
      final response = await _client
          .from('mutual_funds')
          .select()
          .order('scheme_name', ascending: true)
          .limit(limit);
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
  Future<List<Map<String, dynamic>>> fetchHoldings(String investorProfileId,
      String workspaceId, String folioReferenceId) async {
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
    String? selectedWorkspaceId,
  }) async {
    if ((initiationRole == 'advisor' || initiationRole == 'admin') &&
        (selectedWorkspaceId == null || selectedWorkspaceId.isEmpty)) {
      throw const ConfigurationFailure(
          "Selected workspace ID is required for advisor/admin initiation.");
    }
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

      String resolvedWorkspaceId;

      if (selectedWorkspaceId != null) {
        // Enforce the selected workspace ID during beneficiary resolution.
        // Fail closed for mismatched or inactive mappings.
        final membershipRes = await _client
            .from('workspace_memberships')
            .select()
            .eq('workspace_id', selectedWorkspaceId)
            .eq('profile_id', investorProfileId)
            .eq('role', 'investor')
            .eq('status', 'active')
            .isFilter('ended_at', null)
            .maybeSingle();

        if (membershipRes == null) {
          throw const AccessDeniedFailure(
              "No active membership found for the investor in the selected workspace.");
        }
        resolvedWorkspaceId = selectedWorkspaceId;
      } else {
        // No selectedWorkspaceId provided (e.g. investor flow). Resolve it.
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
        resolvedWorkspaceId = memberships[0]['workspace_id'] as String;
      }

      // Check portfolio workspace mapping
      final portfolio = await _client
          .from('portfolios')
          .select('workspace_id')
          .eq('client_id', investorProfileId)
          .eq('workspace_id', resolvedWorkspaceId)
          .maybeSingle();

      if (portfolio == null) {
        throw const AccessDeniedFailure(
            "The investor has no portfolio in the selected workspace.");
      }

      // Correct role authorization:
      // - active advisor is permitted;
      // - admin is permitted only when owning the selected workspace;
      // - non-owner admin is rejected.
      if (initiationRole == 'advisor') {
        final advisorMembership = await _client
            .from('workspace_memberships')
            .select()
            .eq('workspace_id', resolvedWorkspaceId)
            .eq('profile_id', initiatorProfileId)
            .eq('role', 'advisor')
            .eq('status', 'active')
            .isFilter('ended_at', null)
            .maybeSingle();

        if (advisorMembership == null) {
          throw const AccessDeniedFailure(
              "Initiator is not an active advisor in the selected workspace.");
        }
      } else if (initiationRole == 'admin') {
        final adminMembership = await _client
            .from('workspace_memberships')
            .select()
            .eq('workspace_id', resolvedWorkspaceId)
            .eq('profile_id', initiatorProfileId)
            .eq('role', 'admin')
            .eq('status', 'active')
            .isFilter('ended_at', null)
            .maybeSingle();

        if (adminMembership == null) {
          throw const AccessDeniedFailure(
              "Initiator is not an active admin in the selected workspace.");
        }

        // Verify ownership of the workspace
        final workspaceRes = await _client
            .from('workspaces')
            .select('owner_profile_id')
            .eq('id', resolvedWorkspaceId)
            .maybeSingle();

        if (workspaceRes == null ||
            workspaceRes['owner_profile_id'] != initiatorProfileId) {
          throw const AccessDeniedFailure(
              "Access Denied: Admin does not own the selected workspace.");
        }
      } else if (initiationRole == 'investor') {
        if (initiatorProfileId != investorProfileId) {
          throw const AccessDeniedFailure(
              "Initiator is not authorized to act on behalf of this investor.");
        }
      } else {
        throw const AccessDeniedFailure(
            "Access Denied: Unsupported initiation role.");
      }

      return OrderContext(
        workspaceId: resolvedWorkspaceId,
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
      throw const ConfigurationFailure("Failed to resolve investor context.");
    }
  }
}
