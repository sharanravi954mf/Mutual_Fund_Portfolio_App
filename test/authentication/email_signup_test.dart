import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/application/email_signup_controller.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'package:mutual_fund_portfolio_app/providers/theme_provider.dart';
import 'package:mutual_fund_portfolio_app/screens/login_screen.dart';
import 'route_guard_test.dart' show FakeAuthProvider;

class Gateway implements EmailSignupGateway {
  int signups = 0, resends = 0;
  Completer<void>? wait;
  Object? error;
  @override
  Future<void> signUp(String email, String password) async {
    signups++;
    if (wait != null) await wait!.future;
    if (error != null) throw error!;
  }

  @override
  Future<void> resend(String email) async {
    resends++;
    if (error != null) throw error!;
  }
}

class SignInAuth extends FakeAuthProvider {
  List<String>? credentials;
  @override
  Future<bool> signIn(String emailOrPhone, String password) async {
    credentials = [emailOrPhone, password];
    return true;
  }
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  late Gateway gateway;
  late EmailSignupController controller;
  late SignInAuth auth;
  late DateTime now;
  setUp(() {
    gateway = Gateway();
    now = DateTime.utc(2026, 10, 2);
    controller = EmailSignupController(gateway, now: () => now);
    auth = SignInAuth();
  });
  tearDown(() {
    controller.dispose();
    auth.dispose();
  });

  Future<void> mount(WidgetTester tester,
      {bool dark = false,
      double textScale = 1,
      Size size = const Size(390, 844)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final theme = ThemeProvider()
      ..setThemeMode(dark ? ThemeModeOption.dark : ThemeModeOption.light);
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => theme),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!),
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            home: LoginScreen(signupController: controller))));
    await tester.pump();
  }

  Future<void> signup(WidgetTester tester) async {
    await tester.tap(find.text('Sign Up'));
    await tester.pump();
  }

  Future<void> fill(WidgetTester tester,
      {String email = 'new@example.test',
      String password = 'a long unique passphrase',
      String? confirm}) async {
    await tester.enterText(find.byKey(const Key('auth-email')), email);
    await tester.enterText(find.byKey(const Key('auth-password')), password);
    await tester.enterText(
        find.byKey(const Key('auth-confirm')), confirm ?? password);
    await tester.ensureVisible(find.byKey(const Key('auth-submit')));
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pump();
  }

  testWidgets('first screen exposes both modes and switches without navigation',
      (tester) async {
    await mount(tester);
    expect(find.text('Sign In'), findsNWidgets(2));
    expect(find.text('Sign Up'), findsOneWidget);
    await signup(tester);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.byKey(const Key('auth-confirm')), findsOneWidget);
    expect(find.textContaining('Advisor'), findsNothing);
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    expect(find.byKey(const Key('auth-confirm')), findsNothing);
    expect(find.text('Email or Mobile Number'), findsOneWidget);
  });
  for (final credential in [
    'existing@example.test',
    '9876543210',
    '+919876543210'
  ]) {
    testWidgets('existing sign in passes credentials: $credential',
        (tester) async {
      await mount(tester);
      await tester.enterText(find.byKey(const Key('auth-email')), credential);
      await tester.enterText(
          find.byKey(const Key('auth-password')), 'existing-secret');
      await submit(tester);
      expect(auth.credentials, [credential, 'existing-secret']);
    });
  }
  testWidgets('invalid email, short password and mismatch block signup',
      (tester) async {
    await mount(tester);
    await signup(tester);
    await fill(tester,
        email: 'invalid', password: 'short', confirm: 'different');
    await submit(tester);
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Use at least 12 characters'), findsOneWidget);
    expect(find.text('Passwords must match'), findsOneWidget);
    expect(gateway.signups, 0);
  });
  testWidgets(
      'pending request blocks double submit then shows verification and clears passwords',
      (tester) async {
    gateway.wait = Completer<void>();
    await mount(tester);
    await signup(tester);
    await fill(tester);
    await submit(tester);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('auth-submit')))
            .onPressed,
        isNull);
    await controller.submit('new@example.test', 'a long unique passphrase');
    expect(gateway.signups, 1);
    gateway.wait!.complete();
    await tester.pump();
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('n•••@example.test'), findsOneWidget);
    await tester.ensureVisible(find.text('Change email'));
    await tester.tap(find.text('Change email'));
    await tester.pump();
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('auth-password')))
            .controller!
            .text,
        isEmpty);
    expect(controller.secondsRemaining, 60);
  });
  testWidgets('verification errors are generic and never echo tokens',
      (tester) async {
    gateway.error = const AuthException(
        'private customer email and verification token',
        code: 'over_email_send_rate_limit');
    await mount(tester);
    await signup(tester);
    await fill(tester);
    await submit(tester);
    expect(find.textContaining('Unable to send verification'), findsOneWidget);
    expect(find.textContaining('private customer'), findsNothing);
  });
  for (final size in [const Size(320, 640), const Size(1440, 900)]) {
    for (final dark in [false, true]) {
      testWidgets('signup and verification layout $size dark=$dark',
          (tester) async {
        await mount(tester, dark: dark, size: size);
        await signup(tester);
        await fill(tester);
        await submit(tester);
        expect(find.text('Check your email'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Return to Sign In'));
        await tester.tap(find.text('Return to Sign In'));
        await tester.pump();
        expect(find.text('Email or Mobile Number'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('compact signup remains usable with large text', (tester) async {
    await mount(tester, size: const Size(320, 640), textScale: 1.5);
    await signup(tester);
    await fill(tester);
    await submit(tester);
    expect(find.text('Check your email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('resend success and failure both enforce cooldown without retries',
      () async {
    await controller.submit('new@example.test', 'long enough password');
    await controller.resend();
    expect(gateway.resends, 0);
    now = now.add(const Duration(seconds: 60));
    await controller.resend();
    expect(gateway.resends, 1);
    await controller.resend();
    expect(gateway.resends, 1);
    now = now.add(const Duration(seconds: 60));
    gateway.error = Exception('sensitive');
    await controller.resend();
    expect(gateway.resends, 2);
    expect(controller.secondsRemaining, 60);
    expect(controller.message, isNot(contains('sensitive')));
    controller.changeEmail();
    expect(controller.secondsRemaining, 60);
  });
  test('existing email response uses same pending state', () async {
    gateway.error =
        const AuthException('already registered', code: 'user_already_exists');
    await controller.submit('existing@example.test', 'long enough password');
    expect(controller.pendingEmail, 'existing@example.test');
    expect(controller.message, isNull);
  });
  test(
      'email and password boundary validation supports modern domains and passphrases',
      () {
    expect(EmailSignupController.validateEmail('person+tag@example.technology'),
        isNull);
    expect(
        EmailSignupController.validateEmail('person @example.test'), isNotNull);
    expect(EmailSignupController.validatePassword('x' * 12), isNull);
    expect(EmailSignupController.validatePassword('x' * 129), isNotNull);
  });
}
