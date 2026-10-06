import 'package:supabase_flutter/supabase_flutter.dart';

abstract class VerifiedContactRepository {
  Future<void> send(String phone);
  Future<bool> verify(String phone, String token);
}

/// Reuse the current Supabase account and phone-change verification flow.
/// No investor id, linking instruction or verification claim is sent by Flutter.
class SupabaseVerifiedContactRepository implements VerifiedContactRepository {
  SupabaseVerifiedContactRepository(this.client, this.userId);
  final SupabaseClient client;
  final String userId;
  void _assertAccount() {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Account session changed');
    }
  }

  @override
  Future<void> send(String phone) async {
    _assertAccount();
    await client.auth.updateUser(UserAttributes(phone: phone));
    _assertAccount();
  }

  @override
  Future<bool> verify(String phone, String token) async {
    _assertAccount();
    final result = await client.auth
        .verifyOTP(phone: phone, token: token, type: OtpType.phoneChange);
    _assertAccount();
    // Secure phone-change may require another OTP before returning a user.
    if (result.user == null) {
      return false;
    }
    if (result.user!.id != userId) throw StateError('Account session changed');
    return true;
  }
}
