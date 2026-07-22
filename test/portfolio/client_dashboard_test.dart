import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mutual_fund_portfolio_app/features/portfolio/data/portfolio_repository.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/application/folio_verification_service.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/folio_verification_controller.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/folio_verification_route_factory.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/pages/folio_verification_page.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'package:mutual_fund_portfolio_app/providers/language_provider.dart';
import 'package:mutual_fund_portfolio_app/providers/theme_provider.dart';
import 'package:mutual_fund_portfolio_app/screens/client_dashboard.dart';

import '../support/folio_verification_fakes.dart';

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        localStorage: _EmptyLocalStorage(),
        pkceAsyncStorage: _EmptyAsyncStorage(),
      ),
    );
  });

  Widget buildDashboard(PortfolioRepository repository,
      {FolioVerificationRouteFactory? folioVerificationRouteFactory}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: MaterialApp(
        home: ClientDashboard(
          portfolioRepository: repository,
          folioVerificationRouteFactory: folioVerificationRouteFactory,
        ),
      ),
    );
  }

  testWidgets('renders the prepared dashboard on narrow and desktop widths',
      (tester) async {
    final repository = _FakePortfolioRepository(_sampleData());
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(buildDashboard(repository));
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('Your portfolio'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Your portfolio'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('shows a friendly permission-denied state', (tester) async {
    await tester.pumpWidget(buildDashboard(_DeniedPortfolioRepository()));
    await tester.pump();

    expect(find.text('Portfolio access is unavailable'), findsOneWidget);
    expect(find.textContaining('not currently linked'), findsOneWidget);
  });

  testWidgets('shows a friendly repository-failure state', (tester) async {
    await tester.pumpWidget(buildDashboard(_FailingPortfolioRepository()));
    await tester.pump();

    expect(find.text('We could not load your portfolio'), findsOneWidget);
    expect(find.textContaining('Please try again'), findsOneWidget);
  });

  testWidgets('opens an injected folio feature once and returns to dashboard',
      (tester) async {
    // The production header contains two fixed-width action groups. Use the
    // wide desktop viewport that represents this integration scenario rather
    // than testing that unrelated header at its breakpoint boundary.
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final folioRepository = FolioTestRepository();
    var factoryCalls = 0;
    final factory = (BuildContext context) {
      factoryCalls++;
      return MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => FolioVerificationController(
            FolioVerificationService(folioRepository, folioRepository),
          ),
          child: const FolioVerificationPage(),
        ),
      );
    };
    await tester.pumpWidget(buildDashboard(
      _FakePortfolioRepository(_sampleData()),
      folioVerificationRouteFactory: factory,
    ));
    // The repository future completes in a microtask. Do not use
    // pumpAndSettle here: the dashboard intentionally has perpetual visual
    // animations that never settle in a widget test.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    await tester.tap(find.byKey(const Key('verify-folios-navigation-item')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(factoryCalls, 1);
    expect(folioRepository.refreshCalls, 1);
    expect(find.text('Verify Mutual Fund Folio'), findsOneWidget);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Your portfolio'), findsOneWidget);
  });
}

class _FakePortfolioRepository implements PortfolioRepository {
  _FakePortfolioRepository(this.data);

  final InvestorPortfolioData data;

  @override
  Future<InvestorPortfolioData> loadCurrentInvestorPortfolio() async => data;
}

class _EmptyLocalStorage extends LocalStorage {
  const _EmptyLocalStorage();

  @override
  Future<String?> accessToken() async => null;

  @override
  Future<bool> hasAccessToken() async => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> persistSession(String persistSessionString) async {}

  @override
  Future<void> removePersistedSession() async {}
}

class _EmptyAsyncStorage extends GotrueAsyncStorage {
  const _EmptyAsyncStorage();

  @override
  Future<String?> getItem({required String key}) async => null;

  @override
  Future<void> removeItem({required String key}) async {}

  @override
  Future<void> setItem({required String key, required String value}) async {}
}

class _DeniedPortfolioRepository implements PortfolioRepository {
  @override
  Future<InvestorPortfolioData> loadCurrentInvestorPortfolio() =>
      Future<InvestorPortfolioData>.error(
          const PortfolioAccessDeniedException());
}

class _FailingPortfolioRepository implements PortfolioRepository {
  @override
  Future<InvestorPortfolioData> loadCurrentInvestorPortfolio() =>
      Future<InvestorPortfolioData>.error(StateError('repository failure'));
}

InvestorPortfolioData _sampleData() {
  return const InvestorPortfolioData(
    portfolio: {
      'total_invested_value': 1000,
      'current_market_value': 1200,
      'last_updated': '2026-07-22T10:00:00Z',
    },
    transactions: [
      {
        'transaction_type': 'BUY',
        'amount': 1000,
        'units': 50,
        'execution_date': '2026-07-01',
        'mutual_funds': {
          'id': 'fund-1',
          'scheme_code': 'FUND-1',
          'scheme_name': 'Sample Fund',
          'fund_house': 'Sample AMC',
          'category': 'Equity',
          'current_nav': 24,
        },
      },
    ],
    allFunds: [],
    profile: {'full_name': 'Investor One'},
  );
}
