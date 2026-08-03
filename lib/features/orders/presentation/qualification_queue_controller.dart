import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/qualification_queue_repository.dart';
import '../domain/qualification_queue_models.dart';

typedef PeriodicTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

typedef OneShotTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

class QualificationQueueController extends ChangeNotifier {
  QualificationQueueController({
    required QualificationQueueRepository repository,
    required String? reviewerProfileId,
    required bool isAuthorizedReviewer,
    Duration debounceDuration = const Duration(milliseconds: 350),
    PeriodicTimerFactory? periodicTimerFactory,
    OneShotTimerFactory? oneShotTimerFactory,
  })  : _repository = repository,
        _reviewerProfileId = reviewerProfileId,
        _isAuthorizedReviewer = isAuthorizedReviewer,
        _debounceDuration = debounceDuration,
        _periodicTimerFactory = periodicTimerFactory ?? Timer.periodic,
        _oneShotTimerFactory = oneShotTimerFactory ??
            ((duration, callback) => Timer(duration, callback));

  final QualificationQueueRepository _repository;
  final String? _reviewerProfileId;
  final bool _isAuthorizedReviewer;
  final Duration _debounceDuration;
  final PeriodicTimerFactory _periodicTimerFactory;
  final OneShotTimerFactory _oneShotTimerFactory;

  QualificationQueuePhase _phase = QualificationQueuePhase.initial;
  List<QualificationQueueItem> _items = const [];
  DateTime? _fetchedAt;
  String? _message;
  String? _errorMessage;
  String? _activeActionOrderId;
  QualificationDecision? _activeActionDecision;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _started = false;
  bool _disposed = false;
  Timer? _fallbackTimer;
  Timer? _debounceTimer;
  QualificationQueueSubscription? _subscription;

  QualificationQueuePhase get phase => _phase;
  List<QualificationQueueItem> get items => _items;
  DateTime? get fetchedAt => _fetchedAt;
  String? get message => _message;
  String? get errorMessage => _errorMessage;
  String? get activeActionOrderId => _activeActionOrderId;
  QualificationDecision? get activeActionDecision => _activeActionDecision;
  bool get isRefreshing => _refreshInFlight;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (!_isAuthorizedReviewer || _reviewerProfileId == null) {
      _phase = QualificationQueuePhase.accessDenied;
      _errorMessage = 'This queue is available only to authorised MFD users.';
      _notify();
      return;
    }

    _subscription =
        _repository.subscribeToOrderChanges(_scheduleDebouncedRefresh);
    _fallbackTimer = _periodicTimerFactory(
      _repository.fallbackRefreshInterval,
      (_) => refresh(),
    );
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed || !_isAuthorizedReviewer || _reviewerProfileId == null) {
      return;
    }
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }

    _refreshInFlight = true;
    _errorMessage = null;
    if (_items.isEmpty) {
      _phase = _phase == QualificationQueuePhase.initial
          ? QualificationQueuePhase.loading
          : _phase;
    } else {
      _phase = QualificationQueuePhase.refreshing;
    }
    _notify();

    try {
      final snapshot = await _repository.fetchQueue(
        reviewerProfileId: _reviewerProfileId!,
      );
      if (_disposed) return;
      _items = List<QualificationQueueItem>.unmodifiable(snapshot.items);
      _fetchedAt = snapshot.fetchedAt;
      _phase = _items.isEmpty
          ? QualificationQueuePhase.empty
          : QualificationQueuePhase.ready;
    } on QualificationQueueFailure catch (error) {
      if (_disposed) return;
      _errorMessage = error.message;
      _phase = switch (error.kind) {
        QualificationFailureKind.accessDenied =>
          QualificationQueuePhase.accessDenied,
        QualificationFailureKind.network => QualificationQueuePhase.offline,
        QualificationFailureKind.stale => QualificationQueuePhase.failure,
        QualificationFailureKind.unknown => QualificationQueuePhase.failure,
      };
    } catch (_) {
      if (_disposed) return;
      _errorMessage = 'The qualification queue is unavailable.';
      _phase = QualificationQueuePhase.failure;
    } finally {
      _refreshInFlight = false;
      final shouldRefreshAgain = _refreshQueued;
      _refreshQueued = false;
      if (!_disposed) _notify();
      if (shouldRefreshAgain && !_disposed) {
        unawaited(refresh());
      }
    }
  }

  Future<void> approve(QualificationQueueItem item) =>
      _qualify(item, QualificationDecision.approved, null);

  Future<void> reject(QualificationQueueItem item, String? reason) =>
      _qualify(item, QualificationDecision.rejected, reason);

  Future<void> _qualify(
    QualificationQueueItem item,
    QualificationDecision decision,
    String? reason,
  ) async {
    if (_activeActionOrderId == item.id) return;

    _activeActionOrderId = item.id;
    _activeActionDecision = decision;
    _message = null;
    _errorMessage = null;
    _notify();

    final trimmedReason = reason?.trim();
    try {
      await _repository.qualifyOrder(
        orderId: item.id,
        decision: decision,
        rejectionReason: decision == QualificationDecision.rejected &&
                trimmedReason != null &&
                trimmedReason.isNotEmpty
            ? trimmedReason
            : null,
      );
      if (_disposed) return;
      _message = decision == QualificationDecision.approved
          ? 'Order approved.'
          : 'Order rejected.';
      _items = List<QualificationQueueItem>.unmodifiable(
        _items.where((queueItem) => queueItem.id != item.id),
      );
      _phase = _items.isEmpty
          ? QualificationQueuePhase.empty
          : QualificationQueuePhase.ready;
      await refresh();
    } on QualificationQueueFailure catch (error) {
      if (_disposed) return;
      _errorMessage = error.message;
      if (error.kind == QualificationFailureKind.stale) {
        _message = 'This order was already resolved. The queue was refreshed.';
        await refresh();
      }
    } catch (_) {
      if (_disposed) return;
      _errorMessage = 'The order could not be qualified.';
    } finally {
      if (!_disposed) {
        _activeActionOrderId = null;
        _activeActionDecision = null;
        _notify();
      }
    }
  }

  void realtimeChangedForTest() => _scheduleDebouncedRefresh();

  void _scheduleDebouncedRefresh() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = _oneShotTimerFactory(_debounceDuration, refresh);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _fallbackTimer?.cancel();
    _debounceTimer?.cancel();
    final subscription = _subscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
