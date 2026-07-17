import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();

  User? _user;
  String? _role;
  bool _isLoading = false;
  String? _errorMessage;

  User? get user => _user;
  String? get role => _role;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _user != null;

  AuthProvider() {
    _init();
  }

  void _init() {
    // Listen to changes in auth state from Supabase
    _supabaseService.client.auth.onAuthStateChange.listen((data) async {
      final Session? session = data.session;
      _user = session?.user;
      if (_user != null) {
        _isLoading = true;
        notifyListeners();
        _role = await _supabaseService.getUserRole(_user!.id);
      } else {
        _role = null;
      }
      _isLoading = false;
      notifyListeners();
    });
  }

  /// Sign in using credentials and load corresponding profile role
  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _supabaseService.signIn(email, password);
      _user = response.user;
      if (_user != null) {
        _role = await _supabaseService.getUserRole(_user!.id);
        _isLoading = false;
        notifyListeners();
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
      _role = null;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }
}
