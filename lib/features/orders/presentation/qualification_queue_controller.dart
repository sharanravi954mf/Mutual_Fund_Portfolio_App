import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/qualification_queue_repository.dart';
import '../domain/order_models.dart';
import '../domain/qualification_queue_models.dart';

typedef PeriodicTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

typedef OneShotTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

class QualificationQueueRefreshBus {
  QualificationQueueRefreshBus._();

  static final StreamController<void> _controller =
      StreamController<void>.broadcast();

  static Stream<void> get stream => _controller.stream;

  static void notifyChanged() => _controller.add(null);
}

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
  final Map<String, QualificationDecision> _activeActions = {};
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
  bool get isRefreshing => _refreshInFlight;

  QualificationDecision? activeDecisionFor(String orderId) =>
      _activeActions[orderId];

  bool isOrderActionActive(String orderId) =>
      _activeActions.containsKey(orderId);

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
        QualificationFailureKind.ambiguous => QualificationQueuePhase.failure,
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
    if (isOrderActionActive(item.id)) return;

    _activeActions[item.id] = decision;
    _message = null;
    _errorMessage = null;
    _notify();

    final trimmedReason = reason?.trim();
    try {
      final result = await _repository.qualifyOrder(
        orderId: item.id,
        decision: decision,
        rejectionReason: decision == QualificationDecision.rejected &&
                trimmedReason != null &&
                trimmedReason.isNotEmpty
            ? trimmedReason
            : null,
      );
      if (_disposed) return;
      _message = _confirmedActionMessage(result.status);
      _items = List<QualificationQueueItem>.unmodifiable(
        _items.where((queueItem) => queueItem.id != item.id),
      );
      _phase = _items.isEmpty
          ? QualificationQueuePhase.empty
          : QualificationQueuePhase.ready;
      await refresh();
      QualificationQueueRefreshBus.notifyChanged();
    } on QualificationQueueFailure catch (error) {
      if (_disposed) return;
      if (error.kind == QualificationFailureKind.stale ||
          error.kind == QualificationFailureKind.network ||
          error.kind == QualificationFailureKind.ambiguous ||
          error.kind == QualificationFailureKind.unknown) {
        await _reconcileQualification(item, decision);
      } else {
        _errorMessage = error.message;
      }
    } catch (_) {
      if (_disposed) return;
      _errorMessage = 'The order could not be qualified.';
    } finally {
      if (!_disposed) {
        _activeActions.remove(item.id);
        _notify();
      }
    }
  }

  Future<void> _reconcileQualification(
    QualificationQueueItem item,
    QualificationDecision decision,
  ) async {
    OrderStatus? status;
    try {
      status = await _repository.fetchOrderStatus(orderId: item.id);
    } on QualificationQueueFailure catch (error) {
      if (error.kind != QualificationFailureKind.stale) {
        _errorMessage =
            'The decision was not confirmed. Refresh the queue before retrying.';
        await refresh();
        return;
      }
    } catch (_) {
      _errorMessage =
          'The decision was not confirmed. Refresh the queue before retrying.';
      await refresh();
      return;
    }

    await refresh();
    if (_disposed) return;

    final expectedStatus = decision == QualificationDecision.approved
        ? OrderStatus.approved
        : OrderStatus.rejected;
    if (status == expectedStatus) {
      _message = _confirmedActionMessage(status!);
      _errorMessage = null;
      QualificationQueueRefreshBus.notifyChanged();
      return;
    }
    if (status == OrderStatus.pendingReview) {
      _message = null;
      _errorMessage =
          'The decision was not confirmed. Review the refreshed order before retrying.';
      return;
    }

    _errorMessage = null;
    if (status == null) {
      _message =
          'This order was already resolved or is no longer available. The queue was refreshed.';
    } else {
      _message =
          'This order was already resolved as ${_statusLabel(status)}. The queue was refreshed.';
    }
    QualificationQueueRefreshBus.notifyChanged();
  }

  static String _confirmedActionMessage(OrderStatus status) => switch (status) {
        OrderStatus.approved => 'Order approved.',
        OrderStatus.rejected => 'Order rejected.',
        _ => 'Order decision confirmed.',
      };

  static String _statusLabel(OrderStatus status) =>
      status.databaseValue.replaceAll('_', ' ');

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

class QualificationQueueCountController extends ChangeNotifier {
  QualificationQueueCountController({
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

  int? _count;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _started = false;
  bool _disposed = false;
  Timer? _fallbackTimer;
  Timer? _debounceTimer;
  StreamSubscription<void>? _qualificationSubscription;
  QualificationQueueSubscription? _orderSubscription;

  int? get count => _count;
  bool get isRefreshing => _refreshInFlight;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (!_isAuthorizedReviewer || _reviewerProfileId == null) {
      _count = null;
      _notify();
      return;
    }

    _orderSubscription =
        _repository.subscribeToOrderChanges(_scheduleDebouncedRefresh);
    _qualificationSubscription =
        QualificationQueueRefreshBus.stream.listen((_) {
      _scheduleDebouncedRefresh();
    });
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
    _notify();
    try {
      _count = await _repository.fetchPendingReviewCount(
        reviewerProfileId: _reviewerProfileId!,
      );
    } catch (_) {
      _count = null;
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
    unawaited(_qualificationSubscription?.cancel());
    final orderSubscription = _orderSubscription;
    if (orderSubscription != null) {
      unawaited(orderSubscription.cancel());
    }
    super.dispose();
  }
}
