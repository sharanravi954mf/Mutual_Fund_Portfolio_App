import 'dart:async';
import '../features/platform_administration/data/platform_authority_repository.dart';
import '../features/platform_administration/models/platform_context.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/authentication/data/supabase_identity_repository.dart';
import '../features/authentication/services/identity_bootstrap_service.dart';
import '../features/authentication/services/identity_verification_service.dart';
import '../features/authentication/services/onboarding_coordinator.dart';
import '../features/investor_identity/models/user_account.dart';
import '../features/investor_identity/models/user_profile.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  late final SupabaseService _supabaseService;
  StreamSubscription<AuthState>? _authSubscription;
  int _sessionGeneration = 0;
  bool _disposed = false;
  late final IdentityBootstrapService _identityBootstrapService;
  late final OnboardingCoordinator _onboardingCoordinator;

  PlatformContext _platformContext = const PlatformContext();
  PlatformContext get platformContext => _platformContext;

  User? _user;
  UserAccount? _userAccount;
  UserProfile? _userProfile;
  bool _isLoading = true;
  String? _errorMessage;
  Future<void>? _identityLoad;
  String? _identityLoadUserId;

  User? get user => _user;
  UserAccount? get userAccount => _userAccount;
  UserProfile? get userProfile => _userProfile;
  AccountState? get accountState => _userAccount?.accountState;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _user != null;

  AuthProvider(
      {IdentityBootstrapService? identityBootstrapService,
      SupabaseClient? client,
      Uri? initialUri}) {
    _supabaseService =
        client == null ? SupabaseService() : SupabaseService.withClient(client);
    _identityBootstrapService = identityBootstrapService ??
        IdentityBootstrapService(
          SupabaseIdentityRepository(_supabaseService.client),
        );
    _onboardingCoordinator = OnboardingCoordinator(
      repository: SupabaseIdentityRepository(_supabaseService.client),
      verificationService: const PlaceholderIdentityVerificationService(),
    );
    _init(initialUri ?? Uri.base);
  }

  void _init(Uri callback) {
    _authSubscription =
        _supabaseService.client.auth.onAuthStateChange.listen((data) {
      final nextUser = data.session?.user;
      if (_user?.id != nextUser?.id ||
          data.event == AuthChangeEvent.signedOut) {
        _sessionGeneration++;
        _identityLoad = null;
        _identityLoadUserId = null;
        _userAccount = null;
        _userProfile = null;
        _platformContext = const PlatformContext();
      }
      _user = nextUser;
      if (nextUser != null) {
        unawaited(_loadIdentity(nextUser));
      } else {
        _isLoading = false;
        notifyListeners();
      }
    }, onError: (Object _) {
      _errorMessage =
          'This verification link could not be used. It may have expired or already been opened. Sign in if verified, or request a new email from Sign Up.';
      _isLoading = false;
      notifyListeners();
    });
    // initialize() may emit initialSession before this provider is constructed.
    _user = _supabaseService.currentUser;
    if (_user != null) {
      unawaited(_loadIdentity(_user!));
    } else {
      _isLoading = false;
    }
    if (callback.queryParameters.containsKey('error') ||
        callback.fragment.contains('error=') ||
        (_user == null && callback.path == '/auth/callback')) {
      _errorMessage =
          'This verification link could not be used. Sign in if already verified, or request a new email from Sign Up.';
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionGeneration++;
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadIdentity(User user) {
    if (_identityLoad != null && _identityLoadUserId == user.id) {
      return _identityLoad!;
    }

    late final Future<void> load;
    load = _performIdentityLoad(user).whenComplete(() {
      if (identical(_identityLoad, load)) {
        _identityLoad = null;
        _identityLoadUserId = null;
      }
    });
    _identityLoad = load;
    _identityLoadUserId = user.id;
    return load;
  }

  Future<void> _performIdentityLoad(User user) async {
    final generation = _sessionGeneration;
    _user = user;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _identityBootstrapService.load();
      if (_disposed ||
          _sessionGeneration != generation ||
          _user?.id != user.id) {
        return;
      }
      _userAccount = result.account;
      final platform =
          await PlatformAuthorityRepository(_supabaseService.client).load();
      if (_disposed ||
          _sessionGeneration != generation ||
          _user?.id != user.id) {
        return;
      }
      _platformContext = platform;
      if (platform.isPlatformAdmin) {
        _userProfile = null; // Platform authority requires no business profile.
        return;
      }

      // A linked investor must have a live business relationship; Explorer
      // accounts legitimately have no profile. Do not synthesize one.
      String? profileId;
      if (result.account.accountState == AccountState.linkedInvestor) {
        final link = await _supabaseService.client
            .from('investor_account_links')
            .select('profile_id')
            .eq('user_id', user.id)
            .eq('link_status', 'active')
            .single();
        profileId = link['profile_id'] as String;
      }
      final query = _supabaseService.client.from('profiles').select();
      final profileResponse = await (profileId == null
              ? query.eq('user_id', user.id)
              : query.eq('id', profileId))
          .maybeSingle();
      if (result.account.accountState == AccountState.linkedInvestor &&
          profileResponse == null) {
        throw StateError('Linked profile unavailable');
      }

      if (!_disposed &&
          _sessionGeneration == generation &&
          _user?.id == user.id) {
        if (profileResponse != null) {
          _userProfile = UserProfile.fromJson(profileResponse);
        } else {
          _userProfile = null;
        }
      }
    } catch (e) {
      if (!_disposed &&
          _sessionGeneration == generation &&
          _user?.id == user.id) {
        _errorMessage = 'Unable to load your account securely.';
        _userAccount = null;
        _userProfile = null;
        _platformContext = const PlatformContext();
      }
    } finally {
      if (!_disposed &&
          _sessionGeneration == generation &&
          _user?.id == user.id) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshIdentity() async {
    final currentUser = _user;
    if (currentUser != null) {
      await _loadIdentity(currentUser);
    }
  }

  Future<void> chooseExplorer() async {
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();
    try {
      _userAccount = await _onboardingCoordinator.chooseExplorer();
    } catch (e) {
      _errorMessage = 'Unable to update your onboarding choice.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> beginPortfolioLinking() async {
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();
    try {
      _userAccount = await _onboardingCoordinator.choosePortfolioLinking();
    } catch (e) {
      _errorMessage = 'Unable to start portfolio linking.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<VerificationMethodDescriptor> get verificationMethods {
    return _onboardingCoordinator.verificationMethods();
  }

  /// Sign in using credentials and load corresponding profile role
  Future<bool> signIn(String emailOrPhone, String password) async {
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _supabaseService.signIn(emailOrPhone, password);
      _user = response.user;
      if (_user != null) {
        await _loadIdentity(_user!);
        return true;
      }
      _errorMessage = "Authentication failed. Please check your credentials.";
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage =
          'Unable to sign in. Check your credentials and verify your email. If needed, request a new verification email from Sign Up.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Sign out current session
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _supabaseService.signOut();
      _user = null;
      _userAccount = null;
      _userProfile = null;
      _platformContext = const PlatformContext();
      _errorMessage = null;
    } catch (e) {
      _errorMessage =
          'Unable to sign out. Check your connection and try again.';
    }
    _isLoading = false;
    notifyListeners();
  }
}
