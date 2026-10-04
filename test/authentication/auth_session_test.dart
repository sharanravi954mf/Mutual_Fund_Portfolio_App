import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'package:mutual_fund_portfolio_app/services/supabase_service.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/application/email_signup_controller.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_account.dart';

const userId = 'ef000000-0000-0000-0000-000000000001';
Map<String, dynamic> userJson() => {
      'id': userId,
      'aud': 'authenticated',
      'email': 'test@example.test',
      'email_confirmed_at': '2026-10-02T00:00:00Z',
      'created_at': '2026-10-02T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {}
    };
Map<String, dynamic> sessionJson() => {
      'access_token': 'synthetic.${base64Url.encode(utf8.encode(jsonEncode({
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                'sub': userId
              }))).replaceAll('=', '')}.signature',
      'refresh_token': 'synthetic-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': userJson()
    };
Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class MemoryPkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late List<http.Request> requests;
  String state = 'explorer';
  bool platformGranted = false;
  bool platformUnavailable = false;
  Completer<void>? bootstrapWait;
  bool missingLink = false;
  setUp(() {
    requests = [];
    state = 'explorer';
    platformGranted = false;
    platformUnavailable = false;
    bootstrapWait = null;
    missingLink = false;
    client = SupabaseClient('https://synthetic.invalid', 'synthetic-public-key',
        authOptions: AuthClientOptions(
            autoRefreshToken: false, pkceAsyncStorage: MemoryPkceStorage()),
        httpClient: MockClient((request) async {
      http.Response jsonResponse(String body, int status) =>
          http.Response(body, status,
              headers: {'content-type': 'application/json'}, request: request);
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('/signup')) {
        return jsonResponse(jsonEncode(userJson()), 200);
      }
      if (path.endsWith('/resend') || path.endsWith('/logout')) {
        return jsonResponse('{}', 200);
      }
      if (path.endsWith('/token')) {
        return jsonResponse(jsonEncode(sessionJson()), 200);
      }
      if (path.endsWith('/user')) {
        return jsonResponse(jsonEncode(userJson()), 200);
      }
      if (path.endsWith('/get_my_platform_context')) {
        return jsonResponse(
            jsonEncode({
              'is_platform_admin': platformGranted,
              'capabilities':
                  platformGranted ? ['mfd_applications.review'] : [],
              'step_up_verified': false,
              'mfa_enrolled': false
            }),
            platformUnavailable ? 503 : 200);
      }
      if (path.endsWith('/bootstrap_identity')) {
        if (bootstrapWait != null) await bootstrapWait!.future;
        return jsonResponse(
            jsonEncode([
              {
                'account_state': state,
                'onboarding_completed': true,
                'resolution': state == 'explorer' ? 'no_match' : 'existing_link'
              }
            ]),
            200);
      }
      if (path.endsWith('/investor_account_links')) {
        return jsonResponse(
            jsonEncode(missingLink ? [] : {'profile_id': 'profile-1'}), 200);
      }
      if (path.endsWith('/profiles')) {
        return jsonResponse(
            jsonEncode(state == 'explorer'
                ? []
                : [
                    {
                      'id': 'profile-1',
                      'role': 'investor',
                      'account_status': 'active',
                      'created_at': '2026-10-02T00:00:00Z'
                    }
                  ]),
            200);
      }
      throw StateError('Unexpected request: $path');
    }));
  });
  tearDown(() async {
    await client.dispose();
  });
  test(
      'platform projection loads without business profile and revokes with same session',
      () async {
    platformGranted = true;
    final auth = AuthProvider(client: client);
    await auth.signIn('test@example.test', 'test passphrase only');
    expect(auth.platformContext.isPlatformAdmin, isTrue);
    expect(auth.userProfile, isNull);
    expect(auth.accountState, AccountState.explorer);
    expect(requests.where((r) => r.url.path.endsWith('/profiles')), isEmpty);
    final token = client.auth.currentSession!.accessToken;
    platformGranted = false;
    await auth.refreshIdentity();
    expect(client.auth.currentSession!.accessToken, token);
    expect(auth.platformContext.isPlatformAdmin, isFalse);
    platformGranted = true;
    await auth.refreshIdentity();
    expect(auth.platformContext.isPlatformAdmin, isTrue);
    platformUnavailable = true;
    await auth.refreshIdentity();
    expect(auth.platformContext.isPlatformAdmin, isFalse);
    expect(auth.accountState, isNull);
    auth.dispose();
  });

  test('signup/resend use SDK and fixed callback without business metadata',
      () async {
    final gateway = SupabaseEmailSignupGateway(client,
        redirectTo: 'https://app.example.test/auth/callback');
    await gateway.signUp('test@example.test', 'test passphrase only');
    await gateway.resend('test@example.test');
    final signup = requests.firstWhere((r) => r.url.path.endsWith('/signup'));
    final body = jsonDecode(signup.body) as Map;
    expect(body['email'], 'test@example.test');
    expect(body['data'], anyOf(isNull, isEmpty));
    expect(body.containsKey('phone'), false);
    expect(signup.url.queryParameters['redirect_to'],
        'https://app.example.test/auth/callback');
    expect(client.auth.currentSession, isNull);
    expect(jsonDecode(requests.last.body)['type'], 'signup');
  });
  test(
      'PKCE confirmation callback exchanges through SDK, bootstraps and rejects replay',
      () async {
    final gateway = SupabaseEmailSignupGateway(client,
        redirectTo: 'https://app.example.test/auth/callback');
    final auth = AuthProvider(client: client);
    addTearDown(auth.dispose);
    await gateway.signUp('test@example.test', 'test passphrase only');
    final uri =
        Uri.parse('https://app.example.test/auth/callback?code=synthetic-code');
    await client.auth.getSessionFromUrl(uri);
    await flush();
    expect(auth.accountState, AccountState.explorer);
    final exchange = requests
        .firstWhere((r) => r.url.queryParameters['grant_type'] == 'pkce');
    expect(jsonDecode(exchange.body)['auth_code'], 'synthetic-code');
    expect(jsonDecode(exchange.body)['code_verifier'], isNotEmpty);
    await expectLater(
        client.auth.getSessionFromUrl(uri), throwsA(isA<AuthException>()));
    expect(auth.isAuthenticated, true);
  });
  test(
      'restored SDK session bootstraps Explorer without profile; logout and login work',
      () async {
    await client.auth.recoverSession(jsonEncode(sessionJson()));
    final auth = AuthProvider(client: client);
    addTearDown(auth.dispose);
    await flush();
    expect(auth.isLoading, false);
    expect(auth.accountState, AccountState.explorer);
    expect(auth.userProfile, isNull);
    await auth.signOut();
    await flush();
    expect(auth.isAuthenticated, false);
    expect(auth.userAccount, isNull);
    expect(
        await auth.signIn('test@example.test', 'test passphrase only'), true);
    expect(auth.accountState, AccountState.explorer);
  });
  test(
      'SDK verification return triggers bootstrap and requires a live investor link',
      () async {
    state = 'linked_investor';
    final auth = AuthProvider(client: client);
    addTearDown(auth.dispose);
    await client.auth.recoverSession(jsonEncode(sessionJson()));
    await flush();
    expect(auth.accountState, AccountState.linkedInvestor);
    expect(auth.userProfile?.id, 'profile-1');
    missingLink = true;
    await auth.refreshIdentity();
    expect(auth.accountState, isNull);
    expect(auth.errorMessage, 'Unable to load your account securely.');
  });
  test('late bootstrap cannot resurrect a logged out identity', () async {
    bootstrapWait = Completer<void>();
    final auth = AuthProvider(client: client);
    addTearDown(auth.dispose);
    await client.auth.recoverSession(jsonEncode(sessionJson()));
    await flush();
    await auth.signOut();
    bootstrapWait!.complete();
    await flush();
    expect(auth.isAuthenticated, false);
    expect(auth.userAccount, isNull);
    expect(auth.userProfile, isNull);
  });
  test(
      'invalid expired or replayed callback errors render a safe recovery message',
      () async {
    final auth = AuthProvider(client: client);
    addTearDown(auth.dispose);
    // The Flutter SDK sends callback failures on this stream.
    // ignore: invalid_use_of_internal_member
    client.auth.notifyException(
        const AuthException('secret-token customer details',
            code: 'otp_expired'),
        StackTrace.current);
    await flush();
    expect(auth.errorMessage, contains('Sign in if verified'));
    expect(auth.errorMessage, isNot(contains('secret-token')));
    expect(auth.isLoading, false);
  });
  test(
      'cold-start failed callback gives recovery even if SDK error preceded provider',
      () {
    final auth = AuthProvider(
        client: client,
        initialUri: Uri.parse(
            'https://app.example.test/auth/callback?code=already-used'));
    addTearDown(auth.dispose);
    expect(auth.isAuthenticated, false);
    expect(auth.errorMessage, contains('request a new email'));
    expect(auth.errorMessage, isNot(contains('already-used')));
  });
  test('email and international/mobile password sign in use correct SDK fields',
      () async {
    final service = SupabaseService.withClient(client);
    await service.signIn('9876543210', 'test');
    expect(jsonDecode(requests.last.body)['phone'], '+919876543210');
    await service.signIn('+44 7700 900123', 'test');
    expect(jsonDecode(requests.last.body)['phone'], '+447700900123');
    await service.signIn('test@example.test', 'test');
    expect(jsonDecode(requests.last.body)['email'], 'test@example.test');
  });
}
