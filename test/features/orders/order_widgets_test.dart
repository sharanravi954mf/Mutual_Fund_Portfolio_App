import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mutual_fund_portfolio_app/features/orders/presentation/widgets/order_modal.dart';
import 'package:mutual_fund_portfolio_app/features/orders/presentation/widgets/advisor_order_action.dart';
import 'package:mutual_fund_portfolio_app/features/orders/data/order_repository.dart';
import 'package:mutual_fund_portfolio_app/features/orders/domain/order_models.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'package:mutual_fund_portfolio_app/providers/language_provider.dart';
import 'package:mutual_fund_portfolio_app/providers/theme_provider.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_profile.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_account.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/services/identity_verification_service.dart';
import '../../features/orders/order_unit_test.dart';

void main() {
  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test-anon-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
          localStorage: _EmptyLocalStorage(),
          pkceAsyncStorage: _EmptyAsyncStorage(),
        ),
      );
    } catch (_) {}
  });

  Widget buildTestableWidget(Widget child, {required AuthProvider auth}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  late FakeAuthProvider investorAuth;
  late FakeAuthProvider advisorAuth;

  setUp(() {
    investorAuth = FakeAuthProvider(
      isAuthenticated: true,
      userProfile: UserProfile(
        id: 'investor-1',
        fullName: 'John Doe',
        email: 'john@example.com',
        phoneNumber: '9876543210',
        role: UserRole.investor,
        accountStatus: AccountStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      userAccount: UserAccount(
        userId: 'user-1',
        accountState: AccountState.linkedInvestor,
        onboardingCompleted: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    advisorAuth = FakeAuthProvider(
      isAuthenticated: true,
      userProfile: UserProfile(
        id: 'advisor-1',
        fullName: 'Advisor Advisor',
        email: 'advisor@example.com',
        phoneNumber: '9876543211',
        role: UserRole.advisor,
        accountStatus: AccountStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  });

  Finder submitButtonFinder() =>
      find.widgetWithText(ElevatedButton, 'Submit Request');

  ElevatedButton submitButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(submitButtonFinder());

  List<String> textFieldTexts(WidgetTester tester) {
    return tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .map((field) => field.controller?.text ?? '')
        .toList();
  }

  Future<void> selectBuyScheme(WidgetTester tester,
      {String schemeName = 'HDFC Top 100'}) async {
    final schemeField = find.byType(TextFormField).first;
    await tester.ensureVisible(schemeField);
    await tester.pumpAndSettle();
    await tester.tap(schemeField);
    await tester.pumpAndSettle();
    await tester.tap(find.text(schemeName).last);
    await tester.pumpAndSettle();
  }

  Future<void> enterCurrentValue(WidgetTester tester, String text) async {
    final valueField = find.byType(TextFormField).last;
    await tester.ensureVisible(valueField);
    await tester.pumpAndSettle();
    await tester.enterText(valueField, text);
    await tester.pumpAndSettle();
  }

  Future<void> confirmReview(WidgetTester tester) async {
    final checkbox = find.byType(Checkbox);
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
  }

  Future<void> prepareConfirmedBuyOrder(WidgetTester tester,
      {String amount = '5000'}) async {
    await selectBuyScheme(tester);
    await enterCurrentValue(tester, amount);
    await confirmReview(tester);
    expect(submitButton(tester).onPressed, isNotNull);
  }

  Future<void> selectDropdownText(
    WidgetTester tester,
    Finder dropdown,
    Pattern text,
  ) async {
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> tapOrderType(WidgetTester tester, String label) async {
    final button = find.text(label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Finder dropdownAt(int index) {
    return find
        .byWidgetPredicate(
          (widget) => widget is DropdownButtonFormField<dynamic>,
        )
        .at(index);
  }

  // ---------------------------------------------------------------------------
  // OrderModal Widget Tests
  // ---------------------------------------------------------------------------
  group('OrderModal Widget Tests', () {
    testWidgets('renders OrderModal for investor Buy flow', (tester) async {
      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();

      expect(find.text('Place Mutual Fund Order'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Buy'), findsWidgets);
    });

    testWidgets(
        'renders OrderModal for UserRole.client and does not show Access Denied',
        (tester) async {
      final clientAuth = FakeAuthProvider(
        isAuthenticated: true,
        userProfile: UserProfile(
          id: 'client-1',
          fullName: 'Client User',
          email: 'client@example.com',
          phoneNumber: '9876543210',
          role: UserRole.client,
          accountStatus: AccountStatus.active,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        userAccount: UserAccount(
          userId: 'user-1',
          accountState: AccountState.linkedInvestor,
          onboardingCompleted: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: clientAuth));
      await tester.pumpAndSettle();

      expect(find.text('Place Mutual Fund Order'), findsOneWidget);
      expect(find.text('Access Denied'), findsNothing);
    });

    testWidgets('renders resolved locked client name in MFD flow',
        (tester) async {
      final repository = ResolvedNameOrderRepository('Verified Client Name');
      final modal = OrderModal(
        repository: repository,
        preSelectedClientId: 'investor-1',
        preSelectedClientName: 'Placeholder Client',
        preSelectedWorkspaceId: 'workspace-1',
      );

      await tester.pumpWidget(buildTestableWidget(modal, auth: advisorAuth));
      await tester.pumpAndSettle();

      expect(find.text('Advisor-Assisted Order'), findsOneWidget);
      expect(find.text('Verified Client Name'), findsOneWidget);
      expect(find.text('Placeholder Client'), findsNothing);
      expect(find.text('Beneficiary Client (Locked)'), findsOneWidget);
    });

    testWidgets('shows Access Denied state', (tester) async {
      final repository = FakeOrderRepository()..shouldThrowAccessDenied = true;
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('Access is restricted'), findsOneWidget);
    });

    testWidgets('shows Offline / Network Error state', (tester) async {
      final repository = FakeOrderRepository()..shouldThrowNetworkError = true;
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();

      expect(find.text('Network Offline'), findsWidgets);
    });

    testWidgets('supports narrow 320px layout responsive design',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();

      // No overflow or uncaught exceptions at 320px
      expect(find.text('Place Mutual Fund Order'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('supports desktop-width layout', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();

      expect(find.text('Place Mutual Fund Order'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'confirmation invalidates when beneficiary changes and clears stale amount text',
        (tester) async {
      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: advisorAuth));
      await tester.pumpAndSettle();

      await selectDropdownText(
        tester,
        dropdownAt(0),
        'John Doe',
      );
      await prepareConfirmedBuyOrder(tester);

      await selectDropdownText(
        tester,
        dropdownAt(0),
        'Jane Smith',
      );

      expect(submitButton(tester).onPressed, isNull);
      expect(textFieldTexts(tester), isNot(contains('5000')));

      await prepareConfirmedBuyOrder(tester, amount: '6000');
      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets(
        'confirmation invalidates when order type changes and clears stale amount text',
        (tester) async {
      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();
      await prepareConfirmedBuyOrder(tester);

      await tapOrderType(tester, 'Sell');

      expect(submitButton(tester).onPressed, isNull);
      expect(textFieldTexts(tester), isNot(contains('5000')));

      await selectDropdownText(
        tester,
        dropdownAt(0),
        '••••5678',
      );
      await selectDropdownText(
        tester,
        dropdownAt(1),
        'Scheme Alpha Fund',
      );
      await enterCurrentValue(tester, '7000');
      await confirmReview(tester);

      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('confirmation invalidates for amount and units edits',
        (tester) async {
      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();
      await prepareConfirmedBuyOrder(tester);

      await enterCurrentValue(tester, '5500');
      expect(submitButton(tester).onPressed, isNull);
      await confirmReview(tester);
      expect(submitButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Units'));
      await tester.pumpAndSettle();
      await enterCurrentValue(tester, '12.5');
      await confirmReview(tester);
      expect(submitButton(tester).onPressed, isNotNull);

      await enterCurrentValue(tester, '13.5');
      expect(submitButton(tester).onPressed, isNull);
      await confirmReview(tester);
      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('confirmation invalidates for folio and source scheme edits',
        (tester) async {
      final repository = MultiHoldingOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();
      await tapOrderType(tester, 'Sell');

      await selectDropdownText(
        tester,
        dropdownAt(0),
        '••••5678',
      );
      await selectDropdownText(
        tester,
        dropdownAt(1),
        'Scheme Alpha Fund',
      );
      await enterCurrentValue(tester, '5000');
      await confirmReview(tester);
      expect(submitButton(tester).onPressed, isNotNull);

      await selectDropdownText(
        tester,
        dropdownAt(1),
        'Scheme Gamma Fund',
      );
      expect(submitButton(tester).onPressed, isNull);
      await confirmReview(tester);
      expect(submitButton(tester).onPressed, isNotNull);

      await selectDropdownText(
        tester,
        dropdownAt(0),
        '••••9012',
      );
      expect(submitButton(tester).onPressed, isNull);
      await selectDropdownText(
        tester,
        dropdownAt(1),
        'Scheme Beta Fund',
      );
      await confirmReview(tester);
      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('confirmation invalidates for destination scheme edits',
        (tester) async {
      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();
      await tapOrderType(tester, 'Switch');

      await selectDropdownText(
        tester,
        dropdownAt(0),
        '••••5678',
      );
      await selectDropdownText(
        tester,
        dropdownAt(1),
        'Scheme Alpha Fund',
      );
      await selectBuyScheme(tester, schemeName: 'HDFC Top 100');
      await enterCurrentValue(tester, '5000');
      await confirmReview(tester);
      expect(submitButton(tester).onPressed, isNotNull);

      await selectBuyScheme(tester, schemeName: 'SBI Bluechip');
      expect(submitButton(tester).onPressed, isNull);
      await confirmReview(tester);
      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('Sell request renders folio and source holding workflow',
        (tester) async {
      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sell'));
      await tester.pumpAndSettle();

      expect(find.text('Temporarily Unavailable'), findsNothing);
      expect(find.text('Verified Folio'), findsOneWidget);
      expect(find.text('Holding Scheme to Sell'), findsOneWidget);
      expect(
        find.text('Select a verified folio to load available source holdings.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'same folio reference on two portfolios remains a distinct selection',
        (tester) async {
      final repository = SharedFolioOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();
      await tapOrderType(tester, 'Sell');

      final formField = find.byType(DropdownButtonFormField<OrderFolio>).first;
      final dropdown = tester.widget<DropdownButton<OrderFolio>>(
        find.descendant(
          of: formField,
          matching: find.byType(DropdownButton<OrderFolio>),
        ),
      );
      final items = dropdown.items!;
      expect(items, hasLength(2));
      expect(items[0].value?.folioReferenceId, 'shared-folio');
      expect(items[1].value?.folioReferenceId, 'shared-folio');
      expect(items[0].value?.portfolioId, 'portfolio-1');
      expect(items[1].value?.portfolioId, 'portfolio-2');

      dropdown.onChanged!(items[1].value);
      await tester.pumpAndSettle();

      expect(repository.lastHoldingsPortfolioId, 'portfolio-2');
      expect(repository.lastHoldingsFolioReferenceId, 'shared-folio');
    });

    testWidgets('Switch request renders folio, source and destination workflow',
        (tester) async {
      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Switch'));
      await tester.pumpAndSettle();

      expect(find.text('Temporarily Unavailable'), findsNothing);
      expect(find.text('Verified Folio'), findsOneWidget);
      expect(find.text('Source Scheme (from holdings)'), findsOneWidget);
      expect(find.text('Destination Scheme'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // AdvisorOrderAction Widget Tests
  // ---------------------------------------------------------------------------
  // These tests validate the platform-neutral AdvisorOrderAction widget
  // independently, without importing the web-only AdminDashboard.
  group('AdvisorOrderAction Widget Tests', () {
    testWidgets(
        'AdvisorOrderAction renders Initiate Order button and opens modal on tap',
        (tester) async {
      final repository = FakeOrderRepository();
      final action = AdvisorOrderAction(repository: repository);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: advisorAuth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [action],
            ),
          ),
        ),
      ));

      // Button must be present with the canonical key
      final initiateButton = find.byKey(const Key('initiate_order_button'));
      expect(initiateButton, findsOneWidget);

      // Tap the button — the modal should open (advisor flow without client)
      await tester.tap(initiateButton);
      await tester.pumpAndSettle();

      // The advisor-flow modal must show the client selector
      expect(find.text('Choose client'), findsOneWidget);
    });

    testWidgets(
        'AdvisorOrderAction is platform-neutral and composes into any scaffold',
        (tester) async {
      final repository = FakeOrderRepository();
      final action = AdvisorOrderAction(repository: repository);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: advisorAuth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: action),
          ),
        ),
      ));

      expect(find.byKey(const Key('initiate_order_button')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Light / Dark Mode Tests
  // ---------------------------------------------------------------------------
  group('Light and Dark Mode Tests', () {
    testWidgets('renders correctly in light mode', (tester) async {
      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: investorAuth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ],
        child: MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(body: modal),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Place Mutual Fund Order'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders correctly in dark mode', (tester) async {
      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: investorAuth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: modal),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Place Mutual Fund Order'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('SearchableSchemePicker Stale-Result Protection Tests', () {
    testWidgets(
      'search A cannot overwrite search B during B\'s debounce interval',
      (tester) async {
        final searchQueries = <String>[];
        final completers = <String, Completer<List<Map<String, dynamic>>>>{};

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SearchableSchemePicker(
                initialItems: const [
                  {
                    'scheme_code': 'SCH-1',
                    'scheme_name': 'HDFC Top 100',
                  },
                ],
                selectedSchemeCode: null,
                onSelected: (_) {},
                onSearch: (query) {
                  searchQueries.add(query);

                  final completer = Completer<List<Map<String, dynamic>>>();

                  completers[query] = completer;
                  return completer.future;
                },
                label: 'Scheme',
              ),
            ),
          ),
        );

        final finder = find.byType(TextFormField);

        await tester.tap(finder);
        await tester.pumpAndSettle();

        // Start search A.
        await tester.enterText(finder, 'A');
        await tester.pump(const Duration(milliseconds: 350));

        // A must now be running.
        expect(searchQueries, equals(['A']));

        // Type B, but do not let B's debounce finish yet.
        await tester.enterText(finder, 'B');
        await tester.pump(const Duration(milliseconds: 100));

        // Complete A while B is still inside its debounce period.
        completers['A']!.complete([
          {
            'scheme_code': 'SCH-A',
            'scheme_name': 'Stale Scheme A',
          },
        ]);

        await tester.pump();

        // A is stale and must not appear.
        expect(find.text('Stale Scheme A'), findsNothing);

        // Allow B's debounce to finish.
        await tester.pump(const Duration(milliseconds: 250));

        expect(searchQueries, equals(['A', 'B']));

        // Complete the latest search.
        completers['B']!.complete([
          {
            'scheme_code': 'SCH-B',
            'scheme_name': 'Current Scheme B',
          },
        ]);

        await tester.pumpAndSettle();

        expect(find.text('Current Scheme B'), findsOneWidget);
        expect(find.text('Stale Scheme A'), findsNothing);
      },
    );

    testWidgets(
        'in-flight search A cannot overwrite search B when B completes first',
        (tester) async {
      final searchQueries = <String>[];
      final completers = <String, Completer<List<Map<String, dynamic>>>>{};

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SearchableSchemePicker(
            initialItems: const [
              {'scheme_code': 'SCH-1', 'scheme_name': 'HDFC Top 100'}
            ],
            selectedSchemeCode: null,
            onSelected: (_) {},
            onSearch: (query) {
              searchQueries.add(query);
              final completer = Completer<List<Map<String, dynamic>>>();
              completers[query] = completer;
              return completer.future;
            },
            label: 'Scheme',
          ),
        ),
      ));

      final finder = find.byType(TextFormField);
      await tester.tap(finder);
      await tester.pumpAndSettle();

      await tester.enterText(finder, 'A');
      await tester.pump(const Duration(milliseconds: 350));

      await tester.enterText(finder, 'B');
      await tester.pump(const Duration(milliseconds: 350));

      expect(searchQueries, equals(['A', 'B']));

      completers['B']!.complete([
        {'scheme_code': 'SCH-B', 'scheme_name': 'Scheme B Result'}
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Scheme B Result'), findsOneWidget);

      completers['A']!.complete([
        {'scheme_code': 'SCH-A', 'scheme_name': 'Scheme A Result'}
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Scheme B Result'), findsOneWidget);
      expect(find.text('Scheme A Result'), findsNothing);
    });

    testWidgets(
        'a running search cannot overwrite results after the field is cleared',
        (tester) async {
      final completers = <String, Completer<List<Map<String, dynamic>>>>{};

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SearchableSchemePicker(
            initialItems: const [
              {'scheme_code': 'SCH-1', 'scheme_name': 'HDFC Top 100'}
            ],
            selectedSchemeCode: null,
            onSelected: (_) {},
            onSearch: (query) {
              final completer = Completer<List<Map<String, dynamic>>>();
              completers[query] = completer;
              return completer.future;
            },
            label: 'Scheme',
          ),
        ),
      ));

      final finder = find.byType(TextFormField);
      await tester.tap(finder);
      await tester.pumpAndSettle();

      await tester.enterText(finder, 'A');
      await tester.pump(const Duration(milliseconds: 350));

      await tester.enterText(finder, '');
      await tester.pumpAndSettle();

      completers['A']!.complete([
        {'scheme_code': 'SCH-A', 'scheme_name': 'Scheme A Result'}
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Scheme A Result'), findsNothing);
    });
  });

  // Large Text Scale Test
  // ---------------------------------------------------------------------------
  group('Accessibility Tests', () {
    testWidgets('renders without overflow at large text scale', (tester) async {
      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: investorAuth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: MaterialApp(
            home: Scaffold(body: modal),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'No uncaught exceptions at 1.5x text scale');
    });
  });
}

// ---------------------------------------------------------------------------
// Supabase stub storage implementations for test isolation
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// FakeAuthProvider — minimal test double for AuthProvider
// ---------------------------------------------------------------------------
class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  FakeAuthProvider({
    bool isLoading = false,
    bool isAuthenticated = false,
    UserAccount? userAccount,
    UserProfile? userProfile,
  })  : _isLoading = isLoading,
        _isAuthenticated = isAuthenticated,
        _userAccount = userAccount,
        _userProfile = userProfile;

  final bool _isLoading;
  final bool _isAuthenticated;
  final UserAccount? _userAccount;
  final UserProfile? _userProfile;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  UserAccount? get userAccount => _userAccount;

  @override
  UserProfile? get userProfile => _userProfile;

  @override
  AccountState? get accountState => _userAccount?.accountState;

  @override
  String? get errorMessage => null;

  @override
  User? get user => _isAuthenticated
      ? User(
          id: _userProfile?.id ?? 'test-user-id',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        )
      : null;

  @override
  List<VerificationMethodDescriptor> get verificationMethods => const [];

  @override
  Future<void> beginPortfolioLinking() async {}

  @override
  Future<void> chooseExplorer() async {}

  @override
  Future<void> refreshIdentity() async {}

  @override
  Future<bool> signIn(String emailOrPhone, String password) async => true;

  @override
  Future<void> signOut() async {}
}

class ResolvedNameOrderRepository extends FakeOrderRepository {
  ResolvedNameOrderRepository(this.resolvedName);

  final String resolvedName;

  @override
  Future<OrderContext> resolveInvestorContext({
    required String investorProfileId,
    required String initiatorProfileId,
    required String initiationRole,
    required String initiationChannel,
    String? selectedWorkspaceId,
  }) async {
    final base = await super.resolveInvestorContext(
      investorProfileId: investorProfileId,
      initiatorProfileId: initiatorProfileId,
      initiationRole: initiationRole,
      initiationChannel: initiationChannel,
      selectedWorkspaceId: selectedWorkspaceId,
    );
    return OrderContext(
      workspaceId: base.workspaceId,
      investorProfileId: base.investorProfileId,
      investorFullName: resolvedName,
      initiatorProfileId: base.initiatorProfileId,
      initiationRole: base.initiationRole,
      initiationChannel: base.initiationChannel,
    );
  }
}

class MultiHoldingOrderRepository extends FakeOrderRepository {
  @override
  Future<List<Map<String, dynamic>>> fetchHoldings(String investorProfileId,
      String workspaceId, String portfolioId, String folioReferenceId) async {
    if (folioReferenceId == 'folio-a') {
      return [
        {
          'scheme_code': 'SCH-A',
          'scheme_name': 'Scheme Alpha Fund',
          'units': 100.0,
        },
        {
          'scheme_code': 'SCH-C',
          'scheme_name': 'Scheme Gamma Fund',
          'units': 25.0,
        },
      ];
    }
    return super.fetchHoldings(
      investorProfileId,
      workspaceId,
      portfolioId,
      folioReferenceId,
    );
  }
}
