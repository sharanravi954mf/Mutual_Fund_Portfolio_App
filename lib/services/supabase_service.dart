import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal() : client = Supabase.instance.client;
  SupabaseService.withClient(this.client);

  final SupabaseClient client;

  /// Authenticate user via email/phone & password
  Future<AuthResponse> signIn(String emailOrPhone, String password) async {
    final trimmed = emailOrPhone.trim();
    final isPhone = !trimmed.contains('@') &&
        RegExp(r'^\+?[0-9 ()-]{10,}$').hasMatch(trimmed);
    if (isPhone) {
      final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
      final phone = trimmed.startsWith('+') ? '+$digits' : '+91$digits';
      return await client.auth
          .signInWithPassword(phone: phone, password: password);
    } else {
      return await client.auth
          .signInWithPassword(email: trimmed, password: password);
    }
  }

  /// Sign out current user
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Get the current authenticated user metadata
  User? get currentUser => client.auth.currentUser;

  /// Fetch the latest factsheet for a given mutual fund scheme
  Future<Map<String, dynamic>?> getLatestFactsheet(String fundId) async {
    try {
      final response = await client
          .from('fund_factsheets')
          .select()
          .eq('mutual_fund_id', fundId)
          .order('month_year', ascending: false)
          .limit(1)
          .maybeSingle();
      return response;
    } catch (e) {
      return null;
    }
  }

  /// Upsert a factsheet for a given mutual fund (Admin only)
  Future<bool> upsertFactsheet(Map<String, dynamic> data) async {
    try {
      await client
          .from('fund_factsheets')
          .upsert(data, onConflict: 'mutual_fund_id,month_year');
      return true;
    } catch (e) {
      return false;
    }
  }
}
