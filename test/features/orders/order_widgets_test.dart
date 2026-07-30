import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mutual_fund_portfolio_app/features/orders/presentation/widgets/order_modal.dart';
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

  group('OrderModal Widget Tests', () {
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

    testWidgets('renders OrderModal for investor Buy flow', (tester) async {
      final repository = FakeOrderRepository();
      final modal = OrderModal(repository: repository);

      await tester.pumpWidget(buildTestableWidget(modal, auth: investorAuth));
      await tester.pumpAndSettle();

      expect(find.text('Place Mutual Fund Order'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);
      expect(find.text('Buy'), findsWidgets);
    });

    testWidgets('renders preselected locked client in MFD flow',
        (tester) async {
      final repository = FakeOrderRepository();
      final modal = OrderModal(
        repository: repository,
        preSelectedClientId: 'investor-1',
        preSelectedClientName: 'John Doe Client',
      );

      await tester.pumpWidget(buildTestableWidget(modal, auth: advisorAuth));
      await tester.pumpAndSettle();

      expect(find.text('Advisor-Assisted Order'), findsOneWidget);
      expect(find.text('John Doe Client'), findsOneWidget);
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

      expect(find.text('Network Offline'), findsOneWidget);
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

      expect(find.text('Place Mutual Fund Order'), findsOneWidget);
    });
  });
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
