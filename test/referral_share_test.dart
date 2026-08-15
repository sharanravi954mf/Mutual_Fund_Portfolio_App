import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/referrals/application/referral_share_controller.dart';
import 'package:mutual_fund_portfolio_app/features/referrals/data/referral_repository.dart';
import 'package:mutual_fund_portfolio_app/features/referrals/data/supabase_referral_repository.dart';
import 'package:mutual_fund_portfolio_app/features/referrals/domain/investor_referral.dart';
import 'package:mutual_fund_portfolio_app/features/referrals/presentation/referral_share_card.dart';
import 'package:mutual_fund_portfolio_app/providers/theme_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('ReferralShareLinkBuilder', () {
    test('encodes the referral code in a public link and WhatsApp message', () {
      final builder = ReferralShareLinkBuilder(
        Uri(scheme: 'https', host: 'app.moneybowl.test', path: '/public'),
      );

      final referralUri = builder.referralUri('code+/=? with spaces');
      final whatsAppUri = builder.whatsAppUri('code+/=? with spaces');

      expect(referralUri.toString(), contains('/public/join?'));
      expect(referralUri.queryParameters['ref'], 'code+/=? with spaces');
      expect(whatsAppUri.scheme, 'https');
      expect(whatsAppUri.host, 'wa.me');
      expect(whatsAppUri.queryParameters['text'],
          contains(referralUri.toString()));
      expect(whatsAppUri.toString(), isNot(contains('profile_id')));
      expect(whatsAppUri.toString(), isNot(contains('user_id')));
    });
  });

  group('SupabaseReferralRepository', () {
    test('maps the single caller-safe RPC row', () async {
      final repository = SupabaseReferralRepository(
        _FakeRpcClient([
          {
            'referral_code': 'abc123',
            'created_at': '2026-08-14T10:00:00Z',
          }
        ]),
      );

      final result = await repository.getOrCreateCurrentInvestorReferral();

      expect(result.code, 'abc123');
      expect(result.createdAt, DateTime.utc(2026, 8, 14, 10));
    });

    test('normalises malformed and transport failures', () async {
      final malformed = SupabaseReferralRepository(_FakeRpcClient([]));
      final failed = SupabaseReferralRepository(
        _FakeRpcClient(null, error: StateError('secret transport detail')),
      );

      await expectLater(
        malformed.getOrCreateCurrentInvestorReferral(),
        throwsA(isA<ReferralRepositoryException>()),
      );
      await expectLater(
        failed.getOrCreateCurrentInvestorReferral(),
        throwsA(isA<ReferralRepositoryException>()),
      );
    });

    test('processes the opaque code through the caller-bound conversion RPC',
        () async {
      final client = _FakeRpcClient(
        [
          {
            'conversion_id': 'server-only-id',
            'replayed': false,
            'reward_entitlement_count': 2,
          }
        ],
        expectedFunction: 'process_investor_referral_conversion',
        expectedParameters: const <String, dynamic>{
          'p_referral_code': 'opaque-code',
        },
      );
      final repository = SupabaseReferralRepository(client);

      final result = await repository
          .processCurrentInvestorReferralConversion('opaque-code');

      expect(result.replayed, isFalse);
      expect(result.rewardEntitlementCount, 2);
    });

    for (final errorCase in <(String, ReferralRepositoryFailure)>[
      ('referral_code_invalid', ReferralRepositoryFailure.invalidCode),
      ('referral_self_not_allowed', ReferralRepositoryFailure.selfReferral),
      ('referral_conversion_conflict', ReferralRepositoryFailure.conflict),
    ]) {
      test('maps terminal server error ${errorCase.$1}', () async {
        final repository = SupabaseReferralRepository(
          _FakeRpcClient(
            null,
            error: PostgrestException(message: errorCase.$1),
            expectedFunction: 'process_investor_referral_conversion',
            expectedParameters: const <String, dynamic>{
              'p_referral_code': 'opaque-code',
            },
          ),
        );

        await expectLater(
          repository.processCurrentInvestorReferralConversion('opaque-code'),
          throwsA(
            isA<ReferralRepositoryException>()
                .having((error) => error.reason, 'reason', errorCase.$2)
                .having((error) => error.isTerminal, 'isTerminal', isTrue),
          ),
        );
      });
    }
  });

  group('ReferralShareController', () {
    test('can retry a failed load and does not create twice once ready',
        () async {
      final repository = _FakeReferralRepository(failuresRemaining: 1);
      final controller = _controller(repository: repository);

      await controller.load();
      expect(controller.state, ReferralLoadState.failure);
      expect(controller.errorMessage, isNotEmpty);

      await controller.load();
      await controller.load();
      expect(controller.state, ReferralLoadState.ready);
      expect(repository.calls, 2);
    });

    test('builds and launches only the WhatsApp share URI', () async {
      final launcher = _FakeLauncher();
      final controller = _controller(launcher: launcher);

      await controller.load();
      await controller.shareOnWhatsApp();

      expect(launcher.uris, hasLength(1));
      expect(launcher.uris.single.host, 'wa.me');
      expect(
          launcher.uris.single.queryParameters['text'], contains('/join?ref='));
      expect(controller.errorMessage, isNull);
    });

    test('reports launch failure without losing the prepared referral',
        () async {
      final launcher = _FakeLauncher(result: false);
      final controller = _controller(launcher: launcher);

      await controller.load();
      await controller.shareOnWhatsApp();

      expect(controller.state, ReferralLoadState.ready);
      expect(controller.referral, isNotNull);
      expect(controller.errorMessage, contains('could not be opened'));
    });
  });

  group('ReferralShareCard', () {
    testWidgets('is usable at 320 logical pixels and shares on WhatsApp',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final launcher = _FakeLauncher();
      final controller = _controller(launcher: launcher);

      await tester.pumpWidget(_testApp(controller));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('referral-share-card')), findsOneWidget);
      expect(find.byKey(const Key('referral-whatsapp-button')), findsOneWidget);
      expect(tester.takeException(), isNull);

      final buttonSize = tester.getSize(
        find.byKey(const Key('referral-whatsapp-button')),
      );
      expect(buttonSize.height, greaterThanOrEqualTo(44));

      await tester.tap(find.byKey(const Key('referral-whatsapp-button')));
      await tester.pumpAndSettle();
      expect(launcher.uris, hasLength(1));
    });

    testWidgets('shows an actionable retry after load failure', (tester) async {
      final repository = _FakeReferralRepository(failuresRemaining: 1);
      final controller = _controller(repository: repository);

      await tester.pumpWidget(_testApp(controller));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('referral-retry-button')), findsOneWidget);
      expect(find.byKey(const Key('referral-error-message')), findsOneWidget);

      await tester.tap(find.byKey(const Key('referral-retry-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('referral-whatsapp-button')), findsOneWidget);
    });

    testWidgets('renders with dark theme tokens', (tester) async {
      final controller = _controller();

      await tester.pumpWidget(_testApp(controller, isDark: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('referral-share-card')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('supports a desktop viewport with enlarged text',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _controller();

      await tester.pumpWidget(_testApp(controller, textScale: 2));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('referral-share-card')), findsOneWidget);
      expect(find.byKey(const Key('referral-whatsapp-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

ReferralShareController _controller({
  _FakeReferralRepository? repository,
  _FakeLauncher? launcher,
}) {
  return ReferralShareController(
    repository: repository ?? _FakeReferralRepository(),
    launcher: launcher ?? _FakeLauncher(),
    linkBuilder: ReferralShareLinkBuilder(
      Uri(scheme: 'https', host: 'moneybowl.test'),
    ),
  );
}

Widget _testApp(
  ReferralShareController controller, {
  bool isDark = false,
  double textScale = 1,
}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      useMaterial3: true,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ReferralShareCard(
          controller: controller,
          colors: AppThemeColors(isDark),
        ),
      ),
    ),
  );
}

class _FakeRpcClient implements ReferralRpcClient {
  _FakeRpcClient(
    this.response, {
    this.error,
    this.expectedFunction = 'get_or_create_investor_referral',
    this.expectedParameters = const <String, dynamic>{},
  });

  final dynamic response;
  final Object? error;
  final String expectedFunction;
  final Map<String, dynamic> expectedParameters;

  @override
  Future<dynamic> call(
    String functionName, {
    Map<String, dynamic> parameters = const <String, dynamic>{},
  }) async {
    expect(functionName, expectedFunction);
    expect(parameters, expectedParameters);
    if (error case final error?) throw error;
    return response;
  }
}

class _FakeReferralRepository implements ReferralRepository {
  _FakeReferralRepository({this.failuresRemaining = 0});

  int failuresRemaining;
  int calls = 0;

  @override
  Future<InvestorReferral> getOrCreateCurrentInvestorReferral() async {
    calls++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const ReferralRepositoryException();
    }
    return InvestorReferral(
      code: 'test-code',
      createdAt: DateTime.utc(2026, 8, 14),
    );
  }

  @override
  Future<ReferralConversionResult> processCurrentInvestorReferralConversion(
    String referralCode,
  ) async {
    return const ReferralConversionResult(
      replayed: false,
      rewardEntitlementCount: 2,
    );
  }
}

class _FakeLauncher implements ReferralExternalLauncher {
  _FakeLauncher({this.result = true});

  final bool result;
  final List<Uri> uris = [];

  @override
  Future<bool> open(Uri uri) async {
    uris.add(uri);
    return result;
  }
}
