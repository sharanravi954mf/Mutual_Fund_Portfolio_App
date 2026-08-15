import 'package:flutter/foundation.dart';

import '../../investor_identity/models/user_profile.dart';
import '../data/referral_repository.dart';

enum ReferralAttributionState {
  idle,
  waitingForAuthentication,
  waitingForProfile,
  processing,
  applied,
  replayed,
  rejected,
  retryableFailure,
}

class ReferralAttributionController extends ChangeNotifier {
  ReferralAttributionController({required ReferralRepository repository})
      : _repository = repository;

  final ReferralRepository _repository;

  String? _pendingCode;
  String? _boundUserId;
  String? _attemptedUserId;
  ReferralAttributionState _state = ReferralAttributionState.idle;
  ReferralRepositoryFailure? _failure;

  String? get pendingCode => _pendingCode;
  String? get boundUserId => _boundUserId;
  ReferralAttributionState get state => _state;
  ReferralRepositoryFailure? get failure => _failure;

  void capture(String referralCode) {
    if (referralCode.isEmpty || referralCode.length > 512) {
      _finishRejected(ReferralRepositoryFailure.invalidCode);
      return;
    }

    if (_pendingCode == referralCode) return;

    _pendingCode = referralCode;
    _boundUserId = null;
    _attemptedUserId = null;
    _failure = null;
    _state = ReferralAttributionState.waitingForAuthentication;
    notifyListeners();
  }

  Future<void> synchronize({
    required String? userId,
    required UserProfile? profile,
  }) async {
    final code = _pendingCode;
    if (code == null) return;

    if (userId == null) {
      if (_boundUserId != null) {
        _clearPending();
      } else {
        _setState(ReferralAttributionState.waitingForAuthentication);
      }
      return;
    }

    if (_boundUserId != null && _boundUserId != userId) {
      // A referral captured for one authenticated account must never be
      // attributed to a later account in the same application process.
      _clearPending();
      return;
    }
    _boundUserId ??= userId;

    if (profile == null) {
      _setState(ReferralAttributionState.waitingForProfile);
      return;
    }

    if (profile.role != UserRole.investor || !profile.isActive) {
      _finishRejected(ReferralRepositoryFailure.ineligibleInvestor);
      return;
    }

    if (_attemptedUserId == userId) return;
    _attemptedUserId = userId;
    _setState(ReferralAttributionState.processing);

    try {
      final result =
          await _repository.processCurrentInvestorReferralConversion(code);
      _pendingCode = null;
      _failure = null;
      _state = result.replayed
          ? ReferralAttributionState.replayed
          : ReferralAttributionState.applied;
      notifyListeners();
    } on ReferralRepositoryException catch (error) {
      if (error.isTerminal) {
        _finishRejected(error.reason);
      } else {
        _attemptedUserId = null;
        _failure = error.reason;
        _setState(ReferralAttributionState.retryableFailure);
      }
    } catch (_) {
      _attemptedUserId = null;
      _failure = ReferralRepositoryFailure.unknown;
      _setState(ReferralAttributionState.retryableFailure);
    }
  }

  void _finishRejected(ReferralRepositoryFailure failure) {
    _pendingCode = null;
    _attemptedUserId = null;
    _failure = failure;
    _state = ReferralAttributionState.rejected;
    notifyListeners();
  }

  void _clearPending() {
    _pendingCode = null;
    _boundUserId = null;
    _attemptedUserId = null;
    _failure = null;
    _state = ReferralAttributionState.idle;
    notifyListeners();
  }

  void _setState(ReferralAttributionState state) {
    if (_state == state) return;
    _state = state;
    notifyListeners();
  }
}
