import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/authentication/data/supabase_identity_repository.dart';
import '../features/authentication/services/identity_bootstrap_service.dart';
import '../features/authentication/services/identity_verification_service.dart';
import '../features/authentication/services/onboarding_coordinator.dart';
import '../features/investor_identity/models/user_account.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();
  late final IdentityBootstrapService _identityBootstrapService;
  late final OnboardingCoordinator _onboardingCoordinator;

  User? _user;
  UserAccount? _userAccount;
  bool _isLoading = true;
  String? _errorMessage;
  Future<void>? _identityLoad;
  String? _identityLoadUserId;

  User? get user => _user;
  UserAccount? get userAccount => _userAccount;
  AccountState? get accountState => _userAccount?.accountState;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _user != null;

  AuthProvider({IdentityBootstrapService? identityBootstrapService}) {
    _identityBootstrapService = identityBootstrapService ??
        IdentityBootstrapService(
          SupabaseIdentityRepository(_supabaseService.client),
        );
    _onboardingCoordinator = OnboardingCoordinator(
      repository: SupabaseIdentityRepository(_supabaseService.client),
      verificationService: const PlaceholderIdentityVerificationService(),
    );
    _init();
  }

  void _init() {
    _supabaseService.client.auth.onAuthStateChange.listen((data) async {
      final Session? session = data.session;
      _user = session?.user;
      if (_user != null) {
        await _loadIdentity(_user!);
      } else {
        _userAccount = null;
        _isLoading = false;
        notifyListeners();
      }
    });
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
    _user = user;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _identityBootstrapService.load();
      if (_user?.id == user.id) {
        _userAccount = result.account;
      }
    } catch (e) {
      if (_user?.id == user.id) {
        _errorMessage = 'Unable to load your account securely.';
        _userAccount = null;
      }
    } finally {
      if (_user?.id == user.id) {
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
    _isLoading = true;
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
      _errorMessage = e is AuthException ? e.message : e.toString();
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
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }
}
