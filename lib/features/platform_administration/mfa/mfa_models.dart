import '../models/platform_context.dart';

enum MfaPhase { checking, ready, enrolling, verifying, confirmed, unavailable }

enum MfaFactorKind { totp, unsupported }

enum MfaError {
  invalidCode,
  expired,
  rateLimited,
  disabled,
  factorLimit,
  uncertain,
  access,
  sessionChanged,
  unsupported,
  contextMismatch,
  invalidSetup,
}

extension MfaErrorMessage on MfaError {
  String get message => switch (this) {
        MfaError.invalidCode =>
          'That code was not accepted. Check the authenticator and enter a new six-digit code.',
        MfaError.expired =>
          'The challenge or session expired. Refresh security status, then verify again or sign in.',
        MfaError.rateLimited =>
          'Too many attempts. Wait for the server retry period before trying again.',
        MfaError.disabled =>
          'Authenticator MFA is unavailable in this environment. Contact your platform administrator.',
        MfaError.factorLimit =>
          'The account has reached its factor limit. Pending factors may remain from earlier setup. Factor removal and recovery are not available here.',
        MfaError.uncertain =>
          'The result could not be confirmed. Check security status before another explicit attempt. A pending setup may have been created.',
        MfaError.access =>
          'Platform access is unavailable. Refresh access or sign in again. MFA does not grant review permission.',
        MfaError.sessionChanged =>
          'Your sign-in context changed. Close this page and open Account security again.',
        MfaError.unsupported =>
          'This account uses a factor type this screen does not support. V1 supports authenticator (TOTP) only.',
        MfaError.contextMismatch =>
          'MFA and the current server context do not agree. Sensitive actions remain disabled. Refresh security status.',
        MfaError.invalidSetup =>
          'Setup material could not be validated. Refresh status. If a pending factor exists, follow the incomplete setup guidance.',
      };
}

class MfaFailure implements Exception {
  const MfaFailure(this.kind);
  final MfaError kind;
  @override
  String toString() => 'MfaFailure(${kind.name})';
}

class MfaFactor {
  const MfaFactor(
      {required this.id, required this.kind, required this.verified});
  final String id;
  final MfaFactorKind kind;
  final bool verified;
  // Never carry server-provided friendly names into labels or diagnostics.
}

/// Transient only. Never serialize or include setup material in diagnostics.
class MfaSetup {
  const MfaSetup(
      {required this.factorId, required this.secret, required this.uri});
  final String factorId, secret, uri;
  @override
  String toString() => 'MfaSetup(redacted)';
}

class MfaStatus {
  const MfaStatus(
      {required this.factors, required this.aal2, required this.platform});
  final List<MfaFactor> factors;
  final bool aal2;
  final PlatformContext platform;
  List<MfaFactor> get totp =>
      factors.where((f) => f.kind == MfaFactorKind.totp).toList();
  bool get hasVerified => factors.any((f) => f.verified);
  bool get confirmed =>
      aal2 && platform.stepUpVerified && totp.any((f) => f.verified);
}

/// Internal reference only; never a redirect URL or secret-bearing route.
class MfaDestination {
  const MfaDestination.account() : applicationId = null;
  const MfaDestination.review(this.applicationId);
  final String? applicationId;
}
