import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_account.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_profile.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/services/route_guard.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/services/identity_verification_service.dart';

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

  bool _isLoading;
  bool _isAuthenticated;
  UserAccount? _userAccount;
  UserProfile? _userProfile;

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
          id: 'user-id',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        )
      : null;

  @override
  Future<void> chooseExplorer() async {}

  @override
  Future<void> beginPortfolioLinking() async {}

  @override
  List<VerificationMethodDescriptor> get verificationMethods => [];

  @override
  Future<bool> signIn(String emailOrPhone, String password) async => true;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> refreshIdentity() async {}
}

void main() {
  group('UserProfile Model Tests', () {
    test('deserializes profile JSON successfully', () {
      final json = {
        'id': 'profile-id',
        'role': 'investor',
        'account_status': 'active',
        'full_name': 'Jane Doe',
        'phone_number': '+919876543210',
        'email': 'jane@example.com',
        'created_at': '2026-07-22T00:00:00Z',
        'updated_at': '2026-07-22T00:00:00Z',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'profile-id');
      expect(profile.role, UserRole.investor);
      expect(profile.accountStatus, AccountStatus.active);
      expect(profile.fullName, 'Jane Doe');
      expect(profile.isActive, true);
      expect(profile.isSuspended, false);
      expect(profile.isInactive, false);
      expect(profile.isAuthorizedForInvestorDashboard, true);
      expect(profile.isAuthorizedForAdvisorDashboard, false);
    });

    test('supports and correctly checks suspended state', () {
      final profile = UserProfile(
        id: 'profile-id',
        role: UserRole.investor,
        accountStatus: AccountStatus.suspended,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(profile.isActive, false);
      expect(profile.isSuspended, true);
    });

    test('supports and correctly checks inactive state', () {
      final profile = UserProfile(
        id: 'profile-id',
        role: UserRole.investor,
        accountStatus: AccountStatus.inactive,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(profile.isActive, false);
      expect(profile.isInactive, true);
    });
  });

  group('RouteGuard Tests', () {
    final RouteGuard guard = RouteGuard(
      loginBuilder: (_) => const Text('login_screen'),
      loadingBuilder: (_) => const Text('loading_screen'),
      errorBuilder: (title, message) => Text('error_screen: $title - $message'),
      advisorBuilder: (_) => const Text('advisor_dashboard'),
      investorBuilder: (_) => const Text('investor_dashboard'),
      explorerBuilder: (_) => const Text('explorer_screen'),
      linkingBuilder: (_) => const Text('linking_screen'),
    );

    final now = DateTime.now();

    testWidgets('resolves to LoadingScreen if auth state is loading',
        (tester) async {
      final auth = FakeAuthProvider(isLoading: true);
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => guard.resolve(context, auth)),
      ));

      expect(find.text('loading_screen'), findsOneWidget);
    });

    testWidgets('resolves to LoginScreen if not authenticated', (tester) async {
      final auth = FakeAuthProvider(isAuthenticated: false);
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => guard.resolve(context, auth)),
      ));

      expect(find.text('login_screen'), findsOneWidget);
    });

    testWidgets('resolves to AccountAccessErrorScreen if profile is missing',
        (tester) async {
      final auth = FakeAuthProvider(
        isAuthenticated: true,
        userAccount: UserAccount(
          userId: 'user-id',
          accountState: AccountState.explorer,
          onboardingCompleted: true,
          createdAt: now,
          updatedAt: now,
        ),
        userProfile: null,
      );
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => guard.resolve(context, auth)),
      ));

      expect(find.textContaining('error_screen: Profile Setup Unavailable'),
          findsOneWidget);
    });

    testWidgets('resolves to AccountAccessErrorScreen if user is suspended',
        (tester) async {
      final auth = FakeAuthProvider(
        isAuthenticated: true,
        userAccount: UserAccount(
          userId: 'user-id',
          accountState: AccountState.linkedInvestor,
          onboardingCompleted: true,
          createdAt: now,
          updatedAt: now,
        ),
        userProfile: UserProfile(
          id: 'profile-id',
          role: UserRole.investor,
          accountStatus: AccountStatus.suspended,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => guard.resolve(context, auth)),
      ));

      expect(find.textContaining('error_screen: Account Suspended'),
          findsOneWidget);
    });

    testWidgets(
        'resolves to ClientDashboard for linked investor with active profile',
        (tester) async {
      final auth = FakeAuthProvider(
        isAuthenticated: true,
        userAccount: UserAccount(
          userId: 'user-id',
          accountState: AccountState.linkedInvestor,
          onboardingCompleted: true,
          createdAt: now,
          updatedAt: now,
        ),
        userProfile: UserProfile(
          id: 'profile-id',
          role: UserRole.investor,
          accountStatus: AccountStatus.active,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => guard.resolve(context, auth)),
      ));

      expect(find.text('investor_dashboard'), findsOneWidget);
    });

    testWidgets(
        'resolves to AccountAccessErrorScreen if investor tries to access advisor dashboard',
        (tester) async {
      final auth = FakeAuthProvider(
        isAuthenticated: true,
        userAccount: UserAccount(
          userId: 'user-id',
          accountState: AccountState.advisor,
          onboardingCompleted: true,
          createdAt: now,
          updatedAt: now,
        ),
        userProfile: UserProfile(
          id: 'profile-id',
          role: UserRole.investor,
          accountStatus: AccountStatus.active,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => guard.resolve(context, auth)),
      ));

      expect(
          find.textContaining('error_screen: Access Denied'), findsOneWidget);
    });
  });
}
