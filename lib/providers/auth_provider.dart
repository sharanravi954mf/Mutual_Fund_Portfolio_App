import 'dart:async';
import '../features/platform_administration/data/platform_authority_repository.dart';
import '../features/platform_administration/models/platform_context.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/authentication/data/supabase_identity_repository.dart';
import '../features/authentication/models/identity_bootstrap_result.dart';
import '../features/authentication/services/identity_bootstrap_service.dart';
import '../features/authentication/services/identity_verification_service.dart';
import '../features/authentication/services/onboarding_coordinator.dart';
import '../features/investor_identity/models/user_account.dart';
import '../features/investor_identity/models/user_profile.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier with WidgetsBindingObserver {
  late final SupabaseService _supabaseService;
  StreamSubscription<AuthState>? _authSubscription;
  int _sessionGeneration = 0;
  int _accountGeneration = 0;
  int _platformRequest = 0;
  int _authAttempt = 0;
  bool _platformRefreshScheduled = false;
  Session? _platformReadSession;
  bool _platformReading = false;
  Session? _session;
  Timer? _expiry;
  bool _platformCurrent = false;
  bool _platformAssuranceMismatch = false;
  bool get platformAssuranceMismatch => _platformAssuranceMismatch;
  bool _foreground = true;
  int get accountGeneration => _accountGeneration;
  bool get platformContextCurrent =>
      _platformCurrent &&
      _foreground &&
      identical(_session, client.auth.currentSession) &&
      !(client.auth.currentSession?.isExpired ?? true);
  SupabaseClient get client => _supabaseService.client;
  bool _disposed = false;
  late final IdentityBootstrapService _identityBootstrapService;
  late final OnboardingCoordinator _onboardingCoordinator;

  PlatformContext _platformContext = const PlatformContext();
  PlatformContext get platformContext => platformContextCurrent
      ? _platformContext
      : _platformContext.withoutStepUp();

  User? _user;
  UserAccount? _userAccount;
  bool _identityReconciliationRequired = false;
  bool _verifiedContactsRequired = false;
  bool get verifiedContactsRequired => _verifiedContactsRequired;
  bool get identityReconciliationRequired => _identityReconciliationRequired;
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
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = client.auth.onAuthStateChange.listen((data) {
      // Queued events for an already replaced SDK session have no authority.
      if (!identical(data.session, client.auth.currentSession)) return;
      final nextUser = data.session?.user;
      final accountChanged = _user?.id != nextUser?.id ||
          data.event == AuthChangeEvent.signedOut ||
          data.event == AuthChangeEvent.signedIn;
      if (accountChanged) {
        _accountGeneration++;
        _userAccount = null;
        _identityReconciliationRequired = false;
        _verifiedContactsRequired = false;
        _userProfile = null;
        _platformContext = const PlatformContext();
      }
      if (!identical(_session, data.session) || accountChanged) {
        _sessionGeneration++;
        _platformRequest++;
        _platformCurrent = false;
        _identityLoad = null;
        _identityLoadUserId = null;
      }
      _session = data.session;
      _user = nextUser;
      _scheduleExpiry();
      notifyListeners();
      if (nextUser == null) {
        _isLoading = false;
        notifyListeners();
      } else if (_userAccount != null && !accountChanged && !_isLoading) {
        // No factor inventory here: listFactors itself emits tokenRefreshed.
        _schedulePlatformRefresh();
      } else {
        unawaited(_loadIdentity(nextUser));
      }
    }, onError: (Object _) {
      if (client.auth.currentSession == null &&
          _user == null &&
          _authAttempt == 0) {
        _errorMessage =
            'This verification link could not be used. Sign in if verified, or request a new email from Sign Up.';
        _isLoading = false;
        notifyListeners();
      }
      // The SDK error stream has no request ownership metadata. Never let an
      // old refresh failure change identity, navigation or a newer login.
      // Every new projection/mutation still has its own failure handling.
    });
    _session = client.auth.currentSession;
    _user = _supabaseService.currentUser;
    _scheduleExpiry();
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

  void _schedulePlatformRefresh() {
    if (_platformRefreshScheduled) return;
    _platformRefreshScheduled = true;
    // Leave the SDK callback before starting a request. Coalesce queued events.
    scheduleMicrotask(() {
      _platformRefreshScheduled = false;
      if (_disposed || _user == null) return;
      if (_platformReading &&
          identical(_platformReadSession, client.auth.currentSession)) {
        return;
      }
      unawaited(refreshPlatformContext());
    });
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    final expiresAt = _session?.expiresAt;
    if (expiresAt == null) return;
    final remaining = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
        .difference(DateTime.now());
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      invalidatePlatformContext();
    });
  }

  void invalidatePlatformContext() {
    _platformReadSession = null;
    _platformReading = false;
    _platformRequest++;
    _platformCurrent = false;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    invalidatePlatformContext();
    if (_foreground && _user != null) unawaited(refreshPlatformContext());
  }

  /// Latest request and SDK session must both still own the projection.
  /// Never refresh Auth or query factors from this method.
  Future<void> refreshPlatformContext() async {
    final session = client.auth.currentSession;
    final generation = _sessionGeneration;
    final request = ++_platformRequest;
    _platformReadSession = session;
    _platformReading = true;
    _platformCurrent = false;
    notifyListeners();
    bool current() =>
        !_disposed &&
        generation == _sessionGeneration &&
        request == _platformRequest &&
        identical(session, client.auth.currentSession);
    if (session == null) {
      _platformReading = false;
      return;
    }
    try {
      final result = await PlatformAuthorityRepository(client).load();
      if (!current()) return;
      final sdkAal2 =
          client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
              AuthenticatorAssuranceLevels.aal2;
      final supported = session.user.factors?.any((factor) =>
              factor.factorType == FactorType.totp &&
              factor.status == FactorStatus.verified) ??
          false;
      _platformAssuranceMismatch =
          result.stepUpVerified && (!sdkAal2 || !supported);
      _platformContext =
          _platformAssuranceMismatch ? result.withoutStepUp() : result;
      _platformCurrent = !session.isExpired;
    } catch (_) {
      if (!current()) return;
      _platformContext = const PlatformContext();
      _platformCurrent = false;
    } finally {
      if (current()) {
        _platformReading = false;
        notifyListeners();
      }
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiry?.cancel();
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
      _verifiedContactsRequired =
          result.resolution == IdentityResolution.verifiedContactsRequired;
      _identityReconciliationRequired =
          result.resolution == IdentityResolution.reconciliationRequired;
      await refreshPlatformContext();
      final platform = platformContext;
      if (_disposed ||
          _sessionGeneration != generation ||
          _user?.id != user.id) {
        return;
      }
      if (!_platformCurrent) throw StateError('Platform context unavailable');
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
        _identityReconciliationRequired = false;
        _verifiedContactsRequired = false;
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
    invalidatePlatformContext();
    if (currentUser != null) {
      await _loadIdentity(currentUser);
    }
  }

  Future<void> chooseExplorer() async {
    final generation = _accountGeneration;
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();
    try {
      final account = await _onboardingCoordinator.chooseExplorer();
      if (generation != _accountGeneration || _disposed) return;
      _userAccount = account;
    } catch (e) {
      if (generation != _accountGeneration || _disposed) return;
      _errorMessage = 'Unable to update your onboarding choice.';
    } finally {
      if (generation == _accountGeneration && !_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> beginPortfolioLinking() async {
    final generation = _accountGeneration;
    _errorMessage = null;
    _isLoading = true;
    notifyListeners();
    try {
      final account = await _onboardingCoordinator.choosePortfolioLinking();
      if (generation != _accountGeneration || _disposed) return;
      _userAccount = account;
    } catch (e) {
      if (generation != _accountGeneration || _disposed) return;
      _errorMessage = 'Unable to start portfolio linking.';
    } finally {
      if (generation == _accountGeneration && !_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  List<VerificationMethodDescriptor> get verificationMethods {
    return _onboardingCoordinator.verificationMethods();
  }

  /// Sign in using credentials and load corresponding profile role
  Future<bool> signIn(String emailOrPhone, String password) async {
    final attempt = ++_authAttempt;
    _errorMessage = null;
    invalidatePlatformContext();
    try {
      final response = await _supabaseService.signIn(emailOrPhone, password);
      if (_disposed ||
          attempt != _authAttempt ||
          !identical(response.session, client.auth.currentSession)) {
        return false;
      }
      // Let the SDK event establish the account generation before loading.
      await Future<void>.delayed(Duration.zero);
      if (_disposed ||
          attempt != _authAttempt ||
          _user?.id != response.user?.id) {
        return false;
      }
      if (_user != null) {
        await _loadIdentity(_user!);
        return attempt == _authAttempt && !_disposed;
      }
    } catch (_) {
      if (_disposed || attempt != _authAttempt) return false;
      _errorMessage =
          'Unable to sign in. Check your credentials and verify your email. If needed, request a new verification email from Sign Up.';
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  /// Local SDK logout removes the session before its network request returns.
  Future<void> signOut() async {
    final attempt = ++_authAttempt;
    _accountGeneration++;
    _sessionGeneration++;
    _user = null;
    _userAccount = null;
    _identityReconciliationRequired = false;
    _verifiedContactsRequired = false;
    _userProfile = null;
    _platformContext = const PlatformContext();
    _isLoading = false;
    invalidatePlatformContext();
    try {
      await _supabaseService.signOut();
    } catch (_) {
      if (_disposed ||
          attempt != _authAttempt ||
          client.auth.currentSession != null) {
        return;
      }
      _errorMessage =
          'Signed out locally. The server sign-out result could not be confirmed.';
      notifyListeners();
    }
  }
}
