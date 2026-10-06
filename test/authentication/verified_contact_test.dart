import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/application/verified_contact_controller.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/data/verified_contact_repository.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/presentation/verified_contact_screen.dart';

class FakeContactRepository implements VerifiedContactRepository {
  int sends = 0, verifications = 0;
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<void> send(String phone) async {
    sends++;
    if (pending != null) await pending!.future;
  }

  @override
  Future<bool> verify(String phone, String token) async {
    verifications++;
    if (fail) throw StateError('sensitive provider detail');
    return true;
  }
}

void main() {
  test('Supabase changes the same account phone and verifies phone_change OTP',
      () async {
    const id = 'ee000000-0000-0000-0000-000000000001';
    final user = {
      'id': id,
      'aud': 'authenticated',
      'email': 'synthetic@example.test',
      'created_at': '2026-10-06T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {}
    };
    final session = {
      'access_token': 'synthetic-token',
      'refresh_token': 'synthetic-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': user
    };
    final calls = <http.Request>[];
    final client = SupabaseClient(
        'https://synthetic.supabase.co', 'synthetic-anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
      calls.add(r);
      return http.Response(
          jsonEncode(r.url.path.endsWith('/verify') ? session : user), 200,
          headers: {'content-type': 'application/json'});
    }));
    addTearDown(client.dispose);
    await client.auth.recoverSession(jsonEncode(session));
    calls.clear();
    final repo = SupabaseVerifiedContactRepository(client, id);
    await repo.send('+919000000001');
    await repo.verify('+919000000001', '000000');
    expect(calls.first.method, 'PUT');
    expect(calls.first.url.path, endsWith('/user'));
    expect(jsonDecode(calls.first.body)['phone'], '+919000000001');
    expect(calls.last.url.path, endsWith('/verify'));
    expect(jsonDecode(calls.last.body)['type'], 'phone_change');
    expect(client.auth.currentUser!.id, id);
    await expectLater(
        SupabaseVerifiedContactRepository(client, 'other-account')
            .send('+919000000001'),
        throwsStateError);
  });
  testWidgets(
      'mobile verification is same-account, rate limited and masked on compact screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeContactRepository();
    int refreshes = 0;
    await tester.pumpWidget(MaterialApp(
        home: VerifiedContactScreen(
            repository: repo,
            onVerified: () async {
              refreshes++;
            },
            onSignOut: () async {})));
    await tester.enterText(find.byType(TextField).first, '+919000000001');
    await tester.tap(find.text('Send verification code'));
    await tester.pumpAndSettle();
    expect(repo.sends, 1);
    expect(find.textContaining('+919000000001'), findsNothing);
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Request another code'))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField).first, '000000');
    repo.fail = true;
    await tester.tap(find.text('Verify and continue'));
    await tester.pumpAndSettle();
    expect(refreshes, 0);
    expect(find.textContaining('sensitive provider detail'), findsNothing);
    repo.fail = false;
    await tester.tap(find.text('Verify and continue'));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
      'disposed contact request cannot change a newer account or refresh identity',
      () async {
    final repo = FakeContactRepository()..pending = Completer<void>();
    int refreshed = 0;
    final c = VerifiedContactController(repo, () async {
      refreshed++;
    });
    final sending = c.send('+919000000001');
    c.dispose();
    repo.pending!.complete();
    await sending;
    expect(c.sentPhone, isNull);
    expect(refreshed, 0);
  });
}
