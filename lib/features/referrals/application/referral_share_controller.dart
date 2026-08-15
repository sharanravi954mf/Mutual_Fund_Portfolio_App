import 'package:flutter/foundation.dart';

import '../data/referral_repository.dart';
import '../domain/investor_referral.dart';

enum ReferralLoadState { idle, loading, ready, failure }

abstract class ReferralExternalLauncher {
  Future<bool> open(Uri uri);
}

class ReferralShareController extends ChangeNotifier {
  ReferralShareController({
    required ReferralRepository repository,
    required ReferralExternalLauncher launcher,
    required ReferralShareLinkBuilder linkBuilder,
  })  : _repository = repository,
        _launcher = launcher,
        _linkBuilder = linkBuilder;

  final ReferralRepository _repository;
  final ReferralExternalLauncher _launcher;
  final ReferralShareLinkBuilder _linkBuilder;

  ReferralLoadState _state = ReferralLoadState.idle;
  InvestorReferral? _referral;
  bool _isSharing = false;
  String? _errorMessage;

  ReferralLoadState get state => _state;
  InvestorReferral? get referral => _referral;
  bool get isSharing => _isSharing;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    if (_state == ReferralLoadState.loading ||
        _state == ReferralLoadState.ready) {
      return;
    }
    _state = ReferralLoadState.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      _referral = await _repository.getOrCreateCurrentInvestorReferral();
      _state = ReferralLoadState.ready;
    } catch (_) {
      _state = ReferralLoadState.failure;
      _errorMessage = 'We could not prepare your invite. Please try again.';
    }
    notifyListeners();
  }

  Future<void> shareOnWhatsApp() async {
    final currentReferral = _referral;
    if (currentReferral == null || _isSharing) return;

    _isSharing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final opened = await _launcher.open(
        _linkBuilder.whatsAppUri(currentReferral.code),
      );
      if (!opened) {
        _errorMessage = 'WhatsApp could not be opened on this device.';
      }
    } catch (_) {
      _errorMessage = 'WhatsApp could not be opened on this device.';
    } finally {
      _isSharing = false;
      notifyListeners();
    }
  }
}
