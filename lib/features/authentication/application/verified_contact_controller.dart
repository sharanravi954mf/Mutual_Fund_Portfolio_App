import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/verified_contact_repository.dart';

class VerifiedContactController extends ChangeNotifier {
  VerifiedContactController(this.repository, this.onVerified);
  final VerifiedContactRepository repository;
  final Future<void> Function() onVerified;
  bool busy = false, coolingDown = false, _disposed = false;
  String? error, sentPhone;
  Timer? _cooldown;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cooldown?.cancel();
    super.dispose();
  }

  void requestAnother() {
    if (!busy && !coolingDown) {
      sentPhone = null;
      _notify();
    }
  }

  Future<void> send(String phone) async {
    if (busy || coolingDown || _disposed) return;
    final value = phone.trim();
    if (!RegExp(r'^\+[1-9][0-9]{9,14}$').hasMatch(value)) {
      error = 'Enter your mobile with + and country code.';
      _notify();
      return;
    }
    busy = true;
    coolingDown = true;
    error = null;
    _notify();
    _cooldown = Timer(const Duration(seconds: 60), () {
      coolingDown = false;
      _notify();
    });
    try {
      await repository.send(value);
      if (!_disposed) sentPhone = value;
    } catch (_) {
      if (!_disposed) {
        error =
            'Unable to send a code. Check the number and try again after 60 seconds.';
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> verify(String token) async {
    if (busy || sentPhone == null || _disposed) return false;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(token.trim())) {
      error = 'Enter the six-digit verification code.';
      _notify();
      return false;
    }
    busy = true;
    error = null;
    _notify();
    try {
      final complete = await repository.verify(sentPhone!, token.trim());
      if (!complete && !_disposed) {
        error =
            'Additional confirmation is required. Complete the remaining mobile verification code before continuing.';
        return false;
      }
      if (_disposed) return false;
      await onVerified();
      return true;
    } catch (_) {
      if (!_disposed) {
        error =
            'The code could not be verified. Check the code or request a new one.';
      }
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }
}
