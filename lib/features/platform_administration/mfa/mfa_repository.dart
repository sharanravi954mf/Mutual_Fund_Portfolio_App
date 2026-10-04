import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../authentication/services/auth_session_fence.dart';
import '../../../providers/auth_provider.dart';
import 'mfa_models.dart';

class MfaOperationSlot extends ChangeNotifier {
  bool busy = false;
  bool acquire() {
    if (busy) return false;
    busy = true;
    notifyListeners();
    return true;
  }

  void release() {
    busy = false;
    notifyListeners();
  }
}

abstract class MfaRepository {
  MfaOperationSlot get operations;
  String? get userId;
  int get accountGeneration;
  String get accountLabel;
  String get issuer;
  DateTime? get retryNotBefore;
  Future<MfaStatus> inspect();
  Future<MfaSetup> enroll();
  Future<void> verify(String factorId, String code);
}

class SupabaseMfaRepository implements MfaRepository {
  SupabaseMfaRepository(this.client, this.auth);
  static final _slots = Expando<MfaOperationSlot>();
  @override
  MfaOperationSlot get operations => _slots[client] ??= MfaOperationSlot();
  final SupabaseClient client;
  final AuthProvider auth;
  @override
  String? get userId => auth.user?.id;
  @override
  int get accountGeneration => auth.accountGeneration;
  @override
  String get accountLabel =>
      auth.user?.email ?? auth.user?.phone ?? 'Signed-in account';
  @override
  String get issuer =>
      Uri.parse(client.rest.url).host == 'rskryngwzyuzmiwtriyy.supabase.co'
          ? 'MoneyBowl DEV'
          : Uri.parse(client.rest.url).host == '127.0.0.1' ||
                  Uri.parse(client.rest.url).host == 'localhost'
              ? 'MoneyBowl LOCAL'
              : 'MoneyBowl';
  @override
  DateTime? get retryNotBefore =>
      AuthSessionFence.forClient(client)?.retryNotBefore;

  void _current(String? id, int generation) {
    if (AuthSessionFence.forClient(client) == null) {
      throw const MfaFailure(MfaError.disabled);
    }
    if (id == null ||
        userId != id ||
        generation != accountGeneration ||
        client.auth.currentUser?.id != id ||
        client.auth.currentSession == null) {
      throw const MfaFailure(MfaError.sessionChanged);
    }
  }

  @override
  Future<MfaStatus> inspect() async {
    final id = userId, generation = accountGeneration;
    _current(id, generation);
    try {
      // Never called from a tokenRefreshed callback: this method refreshes.
      final factors = await client.auth.mfa.listFactors();
      _current(id, generation);
      await auth.refreshPlatformContext();
      _current(id, generation);
      if (!auth.platformContextCurrent) {
        // A superseded read may finish before the current read. Unknown is
        // recoverable, and never evidence of either a grant or its revocation.
        throw const MfaFailure(MfaError.contextUnavailable);
      }
      if (!auth.platformContext.isPlatformAdmin) {
        throw const MfaFailure(MfaError.access);
      }
      if (auth.platformAssuranceMismatch) {
        throw const MfaFailure(MfaError.contextMismatch);
      }
      final level = client.auth.mfa.getAuthenticatorAssuranceLevel();
      return MfaStatus(
          factors: List.unmodifiable(factors.all.map((f) => MfaFactor(
              id: f.id,
              kind: f.factorType == FactorType.totp
                  ? MfaFactorKind.totp
                  : MfaFactorKind.unsupported,
              verified: f.status == FactorStatus.verified))),
          aal2: level.currentLevel == AuthenticatorAssuranceLevels.aal2,
          platform: auth.platformContext);
    } catch (error) {
      throw MfaFailure(mfaError(error));
    }
  }

  @override
  Future<MfaSetup> enroll() async {
    final id = userId, generation = accountGeneration;
    _current(id, generation);
    try {
      final response = await client.auth.mfa
          .enroll(factorType: FactorType.totp, issuer: issuer);
      _current(id, generation);
      final totp = response.totp;
      if (totp == null || !validTotpSetup(totp.uri, totp.secret, issuer)) {
        throw const MfaFailure(MfaError.invalidSetup);
      }
      return MfaSetup(
          factorId: response.id, secret: totp.secret, uri: totp.uri);
    } catch (error) {
      throw MfaFailure(mfaError(error));
    }
  }

  @override
  Future<void> verify(String factorId, String code) async {
    final id = userId, generation = accountGeneration;
    _current(id, generation);
    final session = client.auth.currentSession;
    try {
      final challenge = await client.auth.mfa.challenge(factorId: factorId);
      _current(id, generation);
      if (!identical(session, client.auth.currentSession)) {
        throw const MfaFailure(MfaError.sessionChanged);
      }
      await client.auth.mfa
          .verify(factorId: factorId, challengeId: challenge.id, code: code);
      _current(id, generation);
    } catch (error) {
      throw MfaFailure(mfaError(error));
    }
  }
}

bool validTotpSetup(String value, String secret, String issuer) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      value.length > 4096 ||
      !RegExp(r'^[A-Z2-7]{16,256}$').hasMatch(secret)) {
    return false;
  }
  final query = uri.queryParameters;
  return uri.scheme == 'otpauth' &&
      uri.host == 'totp' &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      !uri.hasFragment &&
      uri.path.length > 1 &&
      query['secret'] == secret &&
      query['issuer'] == issuer &&
      (query['algorithm'] ?? 'SHA1').toUpperCase() == 'SHA1' &&
      (query['digits'] ?? '6') == '6' &&
      (query['period'] ?? '30') == '30' &&
      uri.queryParametersAll.values.every((v) => v.length == 1);
}

MfaError mfaError(Object error) {
  if (error is MfaFailure) return error.kind;
  if (error is AuthException) {
    if (error.statusCode == '429') return MfaError.rateLimited;
    return switch (error.code) {
      'mfa_verification_failed' => MfaError.invalidCode,
      'mfa_challenge_expired' ||
      'session_expired' ||
      'session_not_found' ||
      'refresh_token_not_found' ||
      'bad_jwt' =>
        MfaError.expired,
      'mfa_totp_enroll_not_enabled' ||
      'mfa_totp_verify_not_enabled' ||
      'mfa_disabled' =>
        MfaError.disabled,
      'mfa_factor_limit_exceeded' => MfaError.factorLimit,
      'mfa_session_changed' => MfaError.sessionChanged,
      'mfa_factor_not_found' => MfaError.expired,
      _ => MfaError.uncertain,
    };
  }
  return MfaError.uncertain;
}
