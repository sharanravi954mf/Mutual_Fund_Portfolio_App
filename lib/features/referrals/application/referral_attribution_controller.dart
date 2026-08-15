import 'package:flutter/foundation.dart';

import '../../investor_identity/models/user_profile.dart';
import '../data/referral_repository.dart';

enum ReferralAttributionState {
  idle,
  creatingClaim,
  waitingForAuthentication,
  waitingForProfile,
  processing,
  applied,
  replayed,
  rejected,
  retryableFailure,
}

class ReferralAttributionController extends ChangeNotifier {
  ReferralAttributionController({
    required ReferralRepository repository,
    Future<void> Function(Duration delay)? retryDelay,
    this.maxAttempts = 3,
    this.retryBaseDelay = const Duration(milliseconds: 250),
  })  : assert(maxAttempts > 0),
        _repository = repository,
        _retryDelay = retryDelay ?? Future<void>.delayed;

  final ReferralRepository _repository;
  final Future<void> Function(Duration delay) _retryDelay;
  final int maxAttempts;
  final Duration retryBaseDelay;

  String? _pendingCode;
  String? _claimToken;
  String? _boundUserId;
  String? _latestUserId;
  UserProfile? _latestProfile;
  Future<void>? _activeSynchronization;
  ReferralAttributionState _state = ReferralAttributionState.idle;
  ReferralRepositoryFailure? _failure;

  String? get pendingCode => _pendingCode;
  bool get hasPendingAttribution =>
      _pendingCode != null || _claimToken != null;
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
    _claimToken = null;
    _boundUserId = null;
    _failure = null;
    _state = ReferralAttributionState.waitingForAuthentication;
    notifyListeners();
  }

  Future<void> synchronize({
    required String? userId,
    required UserProfile? profile,
  }) async {
    _latestUserId = userId;
    _latestProfile = profile;

    final active = _activeSynchronization;
    if (active != null) return active;

    final operation = _synchronizePending();
    _activeSynchronization = operation;
    try {
      await operation;
    } finally {
      if (identical(_activeSynchronization, operation)) {
        _activeSynchronization = null;
      }
    }
  }

  Future<void> _synchronizePending() async {
    if (!hasPendingAttribution) return;

    if (_claimToken == null) {
      final code = _pendingCode;
      if (code == null) return;
      _setState(ReferralAttributionState.creatingClaim);
      try {
        _claimToken = await _withRetry(
          () => _repository.createReferralOnboardingClaim(code),
        );
        _pendingCode = null;
      } on ReferralRepositoryException catch (error) {
        _handleFailure(error);
        return;
      }
    }

    final claimToken = _claimToken;
    if (claimToken == null) return;

    final userId = _latestUserId;

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
    if (_boundUserId == null) {
      _setState(ReferralAttributionState.processing);
      try {
        await _withRetry(
          () => _repository.bindCurrentUserReferralOnboardingClaim(claimToken),
        );
      } on ReferralRepositoryException catch (error) {
        _handleFailure(error);
        return;
      }

      if (_latestUserId != userId) {
        _clearPending();
        return;
      }
      _boundUserId = userId;
    }

    final profile = _latestProfile;
    if (profile == null) {
      _setState(ReferralAttributionState.waitingForProfile);
      return;
    }

    if (profile.role != UserRole.investor || !profile.isActive) {
      _finishRejected(ReferralRepositoryFailure.ineligibleInvestor);
      return;
    }

    _setState(ReferralAttributionState.processing);

    try {
      final result = await _withRetry(
        () => _repository.processCurrentInvestorReferralConversion(claimToken),
      );
      _pendingCode = null;
      _claimToken = null;
      _boundUserId = null;
      _failure = null;
      _state = result.replayed
          ? ReferralAttributionState.replayed
          : ReferralAttributionState.applied;
      notifyListeners();
    } on ReferralRepositoryException catch (error) {
      _handleFailure(error);
    }
  }

  Future<T> _withRetry<T>(Future<T> Function() action) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } on ReferralRepositoryException catch (error) {
        if (error.isTerminal || attempt == maxAttempts) rethrow;
      } catch (_) {
        if (attempt == maxAttempts) {
          throw const ReferralRepositoryException();
        }
      }

      final multiplier = 1 << (attempt - 1);
      await _retryDelay(retryBaseDelay * multiplier);
    }
    throw const ReferralRepositoryException();
  }

  void _handleFailure(ReferralRepositoryException error) {
    if (error.isTerminal) {
      _finishRejected(error.reason);
    } else {
      _failure = error.reason;
      _setState(ReferralAttributionState.retryableFailure);
    }
  }

  void _finishRejected(ReferralRepositoryFailure failure) {
    _pendingCode = null;
    _claimToken = null;
    _boundUserId = null;
    _failure = failure;
    _state = ReferralAttributionState.rejected;
    notifyListeners();
  }

  void _clearPending() {
    _pendingCode = null;
    _claimToken = null;
    _boundUserId = null;
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
