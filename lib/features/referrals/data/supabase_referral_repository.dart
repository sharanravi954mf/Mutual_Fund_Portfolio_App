import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/investor_referral.dart';
import 'referral_repository.dart';

abstract class ReferralRpcClient {
  Future<dynamic> call(String functionName);
}

class SupabaseReferralRpcClient implements ReferralRpcClient {
  const SupabaseReferralRpcClient(this.client);

  final SupabaseClient client;

  @override
  Future<dynamic> call(String functionName) => client.rpc(functionName);
}

class SupabaseReferralRepository implements ReferralRepository {
  const SupabaseReferralRepository(this._client);

  factory SupabaseReferralRepository.fromClient(SupabaseClient client) =>
      SupabaseReferralRepository(SupabaseReferralRpcClient(client));

  final ReferralRpcClient _client;

  @override
  Future<InvestorReferral> getOrCreateCurrentInvestorReferral() async {
    try {
      final response = await _client.call('get_or_create_investor_referral');
      final rows = response is List ? response : <dynamic>[response];
      if (rows.length != 1 || rows.single is! Map) {
        throw const ReferralRepositoryException();
      }

      final row = Map<String, dynamic>.from(rows.single as Map);
      final code = row['referral_code'];
      final createdAt = row['created_at'];
      if (code is! String || code.isEmpty || createdAt is! String) {
        throw const ReferralRepositoryException();
      }

      return InvestorReferral(
        code: code,
        createdAt: DateTime.parse(createdAt),
      );
    } on ReferralRepositoryException {
      rethrow;
    } catch (_) {
      throw const ReferralRepositoryException();
    }
  }
}
