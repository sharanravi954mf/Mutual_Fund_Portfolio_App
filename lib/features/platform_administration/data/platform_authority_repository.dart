import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/platform_context.dart';

class PlatformAuthorityRepository {
  const PlatformAuthorityRepository(this._client);
  final SupabaseClient _client;

  Future<PlatformContext> load() async {
    final result = await _client.rpc('get_my_platform_context');
    if (result is! Map) throw StateError('Platform context unavailable');
    return PlatformContext.fromJson(Map<String, dynamic>.from(result));
  }
}
