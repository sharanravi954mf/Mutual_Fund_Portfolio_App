import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final SupabaseClient client = Supabase.instance.client;

  /// Authenticate user via email/phone & password
  Future<AuthResponse> signIn(String emailOrPhone, String password) async {
    final trimmed = emailOrPhone.trim();
    final isPhone = RegExp(r'^\d{3}').hasMatch(trimmed);
    if (isPhone) {
      final phone = trimmed.startsWith('+') ? trimmed : '+91$trimmed';
      return await client.auth.signInWithPassword(phone: phone, password: password);
    } else {
      return await client.auth.signInWithPassword(email: trimmed, password: password);
    }
  }

  /// Sign out current user
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Get the current authenticated user metadata
  User? get currentUser => client.auth.currentUser;

  /// Retrieve user role from profiles database table
  Future<String?> getUserRole(String uid) async {
    try {
      final response = await client
          .from('profiles')
          .select('role')
          .eq('id', uid)
          .maybeSingle();
      if (response == null) return null;
      return response['role'] as String?;
    } catch (e) {
      return null;
    }
  }
}
