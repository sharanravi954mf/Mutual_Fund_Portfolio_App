import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class EmailSignupGateway {
  Future<void> signUp(String email, String password);
  Future<void> resend(String email);
}

class SupabaseEmailSignupGateway implements EmailSignupGateway {
  SupabaseEmailSignupGateway(this.client, {String? redirectTo})
      : redirectTo = redirectTo ?? defaultRedirect;
  final SupabaseClient client;
  final String redirectTo;

  static String get defaultRedirect {
    const configured = String.fromEnvironment('AUTH_EMAIL_REDIRECT_URL');
    if (configured.isNotEmpty) return configured;
    return kIsWeb
        ? Uri.base.resolve('/auth/callback').toString()
        : 'app.moneybowl://auth/callback';
  }

  @override
  Future<void> signUp(String email, String password) async {
    await client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: redirectTo,
    );
  }

  @override
  Future<void> resend(String email) async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: redirectTo,
    );
  }
}

/// Transient form state only. Supabase owns tokens, persistence and passwords.
class EmailSignupController extends ChangeNotifier {
  EmailSignupController(this.gateway, {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final EmailSignupGateway gateway;
  final DateTime Function() _now;
  static const cooldown = Duration(seconds: 60);
  bool busy = false;
  String? pendingEmail;
  String? message;
  DateTime? _nextAttempt;
  bool _disposed = false;

  int get secondsRemaining {
    final milliseconds = _nextAttempt?.difference(_now()).inMilliseconds ?? 0;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  String get maskedEmail {
    final parts = pendingEmail!.split('@');
    return '${parts.first.substring(0, 1)}•••@${parts.last}';
  }

  static String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    return email.length <= 254 &&
            RegExp(r'^[^\s@]+@[^\s@.]+(?:\.[^\s@.]+)+$').hasMatch(email)
        ? null
        : 'Enter a valid email address';
  }

  static String? validatePassword(String? value) => (value?.length ?? 0) < 12
      ? 'Use at least 12 characters'
      : (value!.length > 128 ? 'Use no more than 128 characters' : null);

  void _startCooldown() {
    _nextAttempt = _now().add(cooldown);
  }

  Future<void> submit(String email, String password) async {
    if (busy || secondsRemaining > 0) return;
    if (validateEmail(email) != null || validatePassword(password) != null) {
      return;
    }
    busy = true;
    message = null;
    _startCooldown();
    notifyListeners();
    try {
      await gateway.signUp(email.trim(), password);
      pendingEmail = email.trim();
    } on AuthException catch (error) {
      if (error.code == 'user_already_exists' || error.code == 'email_exists') {
        pendingEmail =
            email.trim(); // Same outcome as Supabase's obfuscated response.
      } else {
        message =
            'Unable to send verification. Please wait a minute and try again.';
      }
    } catch (_) {
      message =
          'Unable to send verification. Check your connection and try again.';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> resend() async {
    if (busy || pendingEmail == null || secondsRemaining > 0) return;
    busy = true;
    message = null;
    _startCooldown(); // Failed requests are bounded too; never retry automatically.
    notifyListeners();
    try {
      await gateway.resend(pendingEmail!);
      message = 'If verification is needed, a new email will arrive shortly.';
    } catch (_) {
      message =
          'Unable to resend right now. Wait a minute, then try again or sign in.';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void changeEmail() {
    if (busy) return;
    pendingEmail = null;
    message = null;
    // Keep the cooldown when changing email or returning to the form.
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
