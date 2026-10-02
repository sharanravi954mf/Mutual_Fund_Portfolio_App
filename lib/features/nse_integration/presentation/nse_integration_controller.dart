import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/nse_pending_storage.dart';
import '../data/nse_read_repository.dart';
import '../domain/nse_models.dart';

enum NseConsolePhase { loading, ready, empty, accessDenied, unavailable }

typedef NseTimerFactory = Timer Function(
    Duration duration, void Function() callback);

class NsePendingRequest {
  const NsePendingRequest(this.target, this.requestId, this.command);
  final String target, requestId;
  final NseReadCommand command;
  String encode() => jsonEncode(
      {'target': target, 'request_id': requestId, 'command': command.toJson()});
  factory NsePendingRequest.decode(String raw) {
    final row = nseObject(jsonDecode(raw));
    return NsePendingRequest(nseUuid(row['target']), nseUuid(row['request_id']),
        NseReadCommand.fromJson(nseObject(row['command'])));
  }
}

class NseIntegrationController extends ChangeNotifier {
  NseIntegrationController(
      {required NseReadRepository repository,
      required NsePendingStorage storage,
      DateTime Function()? now,
      String Function()? uuid,
      NseTimerFactory? timerFactory,
      double Function()? jitter})
      : _repository = repository,
        _storage = storage,
        _now = now ?? DateTime.now,
        _uuid = uuid ?? _newUuid,
        _timerFactory =
            timerFactory ?? ((duration, callback) => Timer(duration, callback)),
        _jitter = jitter ?? Random().nextDouble;
  final NseReadRepository _repository;
  final NsePendingStorage _storage;
  final DateTime Function() _now;
  final String Function() _uuid;
  final NseTimerFactory _timerFactory;
  final double Function() _jitter;
  bool _disposed = false,
      _visible = true,
      _refreshing = false,
      _submitting = false;
  int _generation = 0, _pollStep = 0;
  Timer? _timer;
  DateTime? _watchSince;
  String? _operationId;
  NsePendingRequest? _pending;
  NseConsolePhase phase = NseConsolePhase.loading;
  List<NseTarget> targets = [];
  Object? targetCursor, historyCursor, candidateCursor;
  NseTarget? target;
  NseReadContext? context;
  List<NseOperation> history = [];
  List<NseCandidate> candidates = [];
  NseOperation? operation;
  NseFailure? failure;
  bool pollingPaused = false;
  bool get isRefreshing => _refreshing;
  bool get isSubmitting => _submitting;
  bool get hasUnconfirmedRequest => _pending != null;
  bool get takingLonger =>
      _watchSince != null &&
      _now().difference(_watchSince!) >= const Duration(minutes: 2) &&
      operation?.terminal != true;

  Future<void> start({String? initialTarget, String? initialOperation}) async {
    final generation = ++_generation;
    try {
      final raw = _storage.read();
      if (raw != null) {
        try {
          _pending = NsePendingRequest.decode(raw);
        } catch (_) {
          _storage.clear();
        }
      }
      final page = await _repository.targets();
      if (!_current(generation)) return;
      targets = page.items;
      targetCursor = page.cursor;
      final wanted = _pending?.target ?? initialTarget;
      target = targets.where((x) => x.id == wanted).firstOrNull ??
          (wanted == null
              ? targets.firstOrNull
              : NseTarget(wanted, 'Selected client', 'Workspace'));
      if (target == null) {
        phase = NseConsolePhase.empty;
        _notify();
        return;
      }
      _operationId = initialOperation;
      await refresh();
      if (_pending != null && phase == NseConsolePhase.ready) await recover();
    } on NseFailure catch (e) {
      if (_current(generation)) _fail(e);
    }
    _notify();
  }

  Future<void> moreTargets() async {
    if (targetCursor == null || _refreshing) return;
    _refreshing = true;
    final generation = _generation;
    _notify();
    try {
      final page = await _repository.targets(after: targetCursor as String);
      if (_current(generation)) {
        targets = [...targets, ...page.items];
        targetCursor = page.cursor;
      }
    } on NseFailure catch (e) {
      if (_current(generation)) _fail(e);
    } finally {
      _refreshing = false;
      _notify();
    }
  }

  Future<void> selectTarget(NseTarget selected) async {
    if (_submitting || _pending != null) return;
    ++_generation;
    _timer?.cancel();
    _operationId = null;
    _watchSince = null;
    operation = null;
    context = null;
    history = [];
    candidates = [];
    target = selected;
    failure = null;
    phase = NseConsolePhase.loading;
    _notify();
    // Any previous refresh completes against its generation before this starts.
    while (_refreshing && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await refresh();
  }

  Future<void> refresh({bool automatic = false}) async {
    if (_disposed || target == null || _refreshing) return;
    _refreshing = true;
    final generation = _generation;
    final targetId = target!.id;
    if (!automatic) {
      pollingPaused = false;
      _watchSince = _now();
    }
    _notify();
    try {
      if (!automatic || context == null) {
        final result = await Future.wait<Object>(
            [_repository.context(targetId), _repository.history(targetId)]);
        if (!_current(generation)) return;
        final ctx = result[0] as NseReadContext;
        if (ctx.target != targetId) throw const NseFailure('INVALID_RESPONSE');
        context = ctx;
        final page = result[1] as NsePage<NseOperation>;
        if (page.items.any((item) => item.targetRef != targetId)) {
          throw const NseFailure('INVALID_RESPONSE');
        }
        history = page.items;
        historyCursor = page.cursor;
      }
      if (_operationId != null) {
        final watchedId = _operationId;
        final fresh = await _repository.operation(operationId: watchedId);
        if (!_current(generation)) return;
        if (_operationId != watchedId) return;
        if (fresh.targetRef != targetId) {
          throw const NseFailure('TARGET_UNAVAILABLE');
        }
        operation = fresh;
        history = history
            .map((entry) => entry.id == fresh.id ? fresh : entry)
            .toList();
        if (fresh.terminal) {
          _timer?.cancel();
        }
      }
      if (!_current(generation)) return;
      failure = null;
      phase = NseConsolePhase.ready;
    } on NseFailure catch (e) {
      if (_current(generation)) _fail(e);
    } finally {
      _refreshing = false;
      if (_current(generation)) {
        _notify();
        _schedule();
      }
    }
  }

  Future<void> moreHistory() async {
    if (target == null || historyCursor == null || _refreshing) return;
    _refreshing = true;
    final generation = _generation;
    _notify();
    try {
      final page = await _repository.history(target!.id, cursor: historyCursor);
      if (_current(generation)) {
        if (page.items.any((item) => item.targetRef != target!.id)) {
          throw const NseFailure('INVALID_RESPONSE');
        }
        history = [...history, ...page.items];
        historyCursor = page.cursor;
      }
    } on NseFailure catch (e) {
      if (_current(generation)) _fail(e);
    } finally {
      _refreshing = false;
      _notify();
    }
  }

  Future<void> selectOperation(String id) async {
    if (_submitting) return;
    ++_generation;
    _timer?.cancel();
    _operationId = id;
    operation = null;
    _pollStep = 0;
    _watchSince = _now();
    pollingPaused = false;
    while (_refreshing && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await refresh(automatic: true);
  }

  Future<void> loadCandidates(NseReadKind kind, String source,
      {bool more = false}) async {
    if (target == null || _refreshing) return;
    final generation = _generation;
    _refreshing = true;
    if (!more) candidates = [];
    _notify();
    try {
      final page = await _repository.candidates(target!.id, kind, source,
          after: more ? (candidateCursor as int? ?? -1) : -1);
      if (_current(generation)) {
        candidates = [if (more) ...candidates, ...page.items];
        candidateCursor = page.cursor;
        failure = null;
      }
    } on NseFailure catch (e) {
      if (_current(generation)) _fail(e);
    } finally {
      _refreshing = false;
      _notify();
    }
  }

  Future<void> submit(NseReadCommand command) async {
    if (_disposed || _submitting || _pending != null || target == null) return;
    _pending = NsePendingRequest(target!.id, _uuid(), command);
    try {
      _storage.write(_pending!.encode());
    } catch (_) {
      _pending = null;
      _fail(const NseFailure('TEMPORARILY_UNAVAILABLE'));
      _notify();
      return;
    }
    await retryPending();
  }

  Future<void> retryPending() async {
    final pending = _pending;
    if (_disposed || _submitting || pending == null) return;
    _submitting = true;
    _timer?.cancel();
    final generation = _generation;
    failure = null;
    _notify();
    try {
      final accepted = await _repository.submit(
          pending.target, pending.requestId, pending.command);
      if (!_current(generation)) return;
      _pending = null;
      _storage.clear();
      _operationId = accepted.operationId;
      operation = null;
      _watchSince = _now();
      pollingPaused = false;
      // An older status request may already be in flight when acceptance arrives.
      // Drain it before starting the new watch; never lose the accepted operation.
      while (_refreshing && _current(generation)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (!_current(generation)) return;
      _timer?.cancel();
      _pollStep = 0;
      await refresh();
    } on NseFailure catch (e) {
      if (_current(generation)) {
        if (!e.uncertain) {
          _pending = null;
          _storage.clear();
        }
        _fail(e);
      }
    } finally {
      _submitting = false;
      if (_current(generation) && _timer?.isActive != true) {
        _schedule();
      }
      _notify();
    }
  }

  Future<void> recover() async {
    final pending = _pending;
    if (pending == null || _submitting || _disposed) return;
    _submitting = true;
    final generation = _generation;
    _notify();
    try {
      final found = await _repository.operation(requestId: pending.requestId);
      if (!_current(generation)) return;
      if (found.kind != pending.command.kind ||
          found.targetRef != pending.target) {
        throw const NseFailure('INVALID_RESPONSE');
      }
      operation = found;
      _operationId = found.id;
      _pending = null;
      _storage.clear();
      _watchSince = _now();
      _pollStep = 0;
      failure = null;
      _schedule();
    } on NseFailure catch (e) {
      if (_current(generation)) {
        failure = e;
      }
    } finally {
      _submitting = false;
      _notify();
    }
  }

  void setVisible(bool visible) {
    _visible = visible;
    _timer?.cancel();
    if (visible) unawaited(refresh());
  }

  void clearSession() {
    _storage.clear();
    _pending = null;
    _timer?.cancel();
    ++_generation;
    targets = [];
    target = null;
    context = null;
    history = [];
    candidates = [];
    targetCursor = historyCursor = candidateCursor = null;
    operation = null;
    _operationId = null;
    failure = null;
    phase = NseConsolePhase.accessDenied;
    _notify();
  }

  void _fail(NseFailure e) {
    failure = e;
    if (e.accessDenied) {
      phase = NseConsolePhase.accessDenied;
      context = null;
      history = [];
      operation = null;
      candidates = [];
      _operationId = null;
      _timer?.cancel();
    } else if (context == null) {
      phase = NseConsolePhase.unavailable;
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed ||
        !_visible ||
        _operationId == null ||
        operation?.terminal == true ||
        phase == NseConsolePhase.accessDenied) {
      return;
    }
    _watchSince ??= _now();
    if (_now().difference(_watchSince!) >= const Duration(minutes: 10)) {
      pollingPaused = true;
      _notify();
      return;
    }
    const seconds = [2, 4, 8, 15];
    final step = _pollStep.clamp(0, 3);
    _pollStep++;
    final milliseconds =
        (seconds[step] * 1000 * (.9 + .2 * _jitter())).round().clamp(1, 15000);
    _timer = _timerFactory(Duration(milliseconds: milliseconds),
        () => unawaited(refresh(automatic: true)));
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  static String _newUuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
