import 'package:supabase_flutter/supabase_flutter.dart';

import '../../investor_identity/models/user_account.dart';
import 'portfolio_repository.dart';

class SupabasePortfolioRepository implements PortfolioRepository {
  SupabasePortfolioRepository(
    this._client, {
    PortfolioAccessPolicy? accessPolicy,
    InvestorOwnershipResolver? ownershipResolver,
  })  : _accessPolicy = accessPolicy ?? const PortfolioAccessPolicy(),
        _ownershipResolver =
            ownershipResolver ?? const InvestorOwnershipResolver();

  final SupabaseClient _client;
  final PortfolioAccessPolicy _accessPolicy;
  final InvestorOwnershipResolver _ownershipResolver;

  @override
  Future<InvestorPortfolioData> loadCurrentInvestorPortfolio() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const PortfolioAccessDeniedException();
    }

    final account = await _client
        .from('user_accounts')
        .select('account_state')
        .eq('user_id', userId)
        .maybeSingle();
    final accountState = account?['account_state'] as String?;
    if (accountState == null ||
        !_accessPolicy.canLoadInvestorPortfolio(
          AccountState.fromDatabase(accountState),
        )) {
      throw const PortfolioAccessDeniedException();
    }

    final links = await _client
        .from('investor_account_links')
        .select('profile_id')
        .eq('user_id', userId)
        .eq('link_status', 'active');
    final profileId = _ownershipResolver.resolveActiveProfileId(
      accountState: AccountState.fromDatabase(accountState),
      links: List<Map<String, dynamic>>.from(links),
    );

    final portfolio = await _client
        .from('portfolios')
        .select()
        .eq('client_id', profileId)
        .maybeSingle();
    final allFunds = await _client
        .from('mutual_funds')
        .select()
        .order('scheme_name', ascending: true);
    final profile = await _client
        .from('profiles')
        .select()
        .eq('id', profileId)
        .maybeSingle();

    if (portfolio == null) {
      return InvestorPortfolioData(
        portfolio: null,
        transactions: const [],
        allFunds: List<Map<String, dynamic>>.from(allFunds),
        profile: profile,
      );
    }

    final transactions = await _client
        .from('transactions')
        .select('*, mutual_funds(*)')
        .eq('portfolio_id', portfolio['id'])
        .order('execution_date', ascending: false);
    return InvestorPortfolioData(
      portfolio: Map<String, dynamic>.from(portfolio),
      transactions: List<Map<String, dynamic>>.from(transactions),
      allFunds: List<Map<String, dynamic>>.from(allFunds),
      profile: profile,
    );
  }
}
