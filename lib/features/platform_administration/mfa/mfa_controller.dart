import 'dart:async';
import 'package:flutter/foundation.dart';
import 'mfa_models.dart';
import 'mfa_repository.dart';

class MfaController extends ChangeNotifier {
  MfaController(this.repository)
      : _owner = repository.userId,
        _account = repository.accountGeneration {
    repository.operations.addListener(_emit);
    _scheduleRetryReady();
  }
  final MfaRepository repository;
  final String? _owner;
  final int _account;
  bool _disposed = false, _busy = false;
  Timer? _retryReady;
  bool foreground = true;
  MfaPhase phase = MfaPhase.checking;
  MfaStatus? status;
  MfaSetup? setup;
  MfaError? error;
  String? selectedId;
  bool get busy => _busy || repository.operations.busy;
  bool get current =>
      !_disposed &&
      _owner != null &&
      _owner == repository.userId &&
      _account == repository.accountGeneration &&
      phase != MfaPhase.unavailable;
  bool get canAct =>
      current &&
      foreground &&
      !busy &&
      !(repository.retryNotBefore?.isAfter(DateTime.now()) ?? false);
  bool get confirmed =>
      current && foreground && !busy && phase == MfaPhase.confirmed;
  bool get canEnroll =>
      canAct &&
      status != null &&
      !status!.hasVerified &&
      (status!.factors.isEmpty || status!.totp.isNotEmpty);
  bool get canVerify =>
      canAct &&
      status != null &&
      selectedId != null &&
      status!.totp.any((f) => f.id == selectedId);

  void _scheduleRetryReady() {
    _retryReady?.cancel();
    final deadline = repository.retryNotBefore;
    if (deadline != null && deadline.isAfter(DateTime.now())) {
      // One UI wake-up, never an Auth request or retry.
      _retryReady = Timer(deadline.difference(DateTime.now()), _emit);
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void invalidateAccount() {
    setup = null;
    status = null;
    selectedId = null;
    phase = MfaPhase.unavailable;
    error = MfaError.sessionChanged;
    _emit();
  }

  void accessChanged(
      {required bool currentAccess,
      required bool admin,
      required bool stepUp}) {
    if (!current) {
      invalidateAccount();
      return;
    }
    if (currentAccess && !admin) {
      invalidateAccount();
      error = MfaError.access;
    } else if (!currentAccess) {
      // Unknown/refreshing access cannot retain actionable factor status.
      status = null;
      if (!busy) phase = MfaPhase.ready;
    } else if (!stepUp && phase == MfaPhase.confirmed) {
      phase = MfaPhase.ready;
    }
    _emit();
  }

  void suspend() {
    foreground = false;
    _emit();
  }

  Future<void> resume() async {
    foreground = true;
    // A still-running request retains its slot; never launch its replacement.
    if (busy) {
      _emit();
      return;
    }
    await refresh();
  }

  void select(String? id) {
    if (!canAct || !(status?.totp.any((f) => f.id == id) ?? false)) return;
    selectedId = id;
    error = null;
    _emit();
  }

  void _apply(MfaStatus value) {
    if (!value.platform.isPlatformAdmin) {
      throw const MfaFailure(MfaError.access);
    }
    status = value;
    final choices = value.totp;
    if (!choices.any((f) => f.id == selectedId)) {
      selectedId = choices.length == 1 ? choices.single.id : null;
    }
    if (setup != null &&
        !choices.any((f) => f.id == setup!.factorId && !f.verified)) {
      setup = null;
    }
    if (value.confirmed) {
      setup = null;
      phase = MfaPhase.confirmed;
    } else {
      phase = MfaPhase.ready;
      if (value.platform.stepUpVerified != value.aal2 ||
          (value.aal2 && !choices.any((f) => f.verified))) {
        error = MfaError.contextMismatch;
      } else if (choices.isEmpty && value.factors.isNotEmpty) {
        error = MfaError.unsupported;
      }
    }
  }

  Future<void> refresh() async {
    if (!canAct) return;
    if (!repository.operations.acquire()) return;
    _busy = true;
    error = null;
    status = null;
    phase = MfaPhase.checking;
    _emit();
    try {
      final value = await repository.inspect();
      if (current) _apply(value);
    } catch (e) {
      if (current) _fail(e);
    } finally {
      _busy = false;
      _scheduleRetryReady();
      repository.operations.release();
      if (!current && !_disposed) invalidateAccount();
      _emit();
    }
  }

  void _fail(Object e) {
    error = mfaError(e);
    phase = MfaPhase.ready;
    if (error == MfaError.access || error == MfaError.sessionChanged) {
      setup = null;
      status = null;
      selectedId = null;
      phase = MfaPhase.unavailable;
    }
  }

  Future<void> _reconcile(Object failure) async {
    final original = mfaError(failure);
    // One status reconciliation only. The mutation itself is never retried.
    if (original == MfaError.uncertain ||
        original == MfaError.expired ||
        original == MfaError.invalidSetup) {
      status = null;
      try {
        final value = await repository.inspect();
        if (!current) return;
        _apply(value);
        if (value.confirmed) {
          error = null;
          return;
        }
      } catch (reconciliationError) {
        if (!current) return;
        final kind = mfaError(reconciliationError);
        if (kind == MfaError.access || kind == MfaError.sessionChanged) {
          _fail(reconciliationError);
          return;
        }
        status = null;
      }
    }
    if (current) _fail(failure);
  }

  Future<void> enroll({bool restartAcknowledged = false}) async {
    if (!canEnroll) return;
    if (!repository.operations.acquire()) return;
    _busy = true;
    phase = MfaPhase.enrolling;
    error = null;
    _emit();
    try {
      final fresh = await repository.inspect();
      if (!current) return;
      _apply(fresh);
      if (fresh.hasVerified ||
          (fresh.factors.isNotEmpty &&
              (fresh.totp.isEmpty || !restartAcknowledged))) {
        return;
      }
      setup = null;
      final result = await repository.enroll();
      if (!current) return;
      setup = result;
      selectedId = result.factorId;
      status = MfaStatus(factors: [
        ...fresh.factors,
        MfaFactor(
            id: result.factorId, kind: MfaFactorKind.totp, verified: false)
      ], aal2: false, platform: fresh.platform.withoutStepUp());
      phase = MfaPhase.ready;
    } catch (e) {
      if (current) await _reconcile(e);
    } finally {
      _busy = false;
      _scheduleRetryReady();
      repository.operations.release();
      if (!current && !_disposed) invalidateAccount();
      _emit();
    }
  }

  Future<void> verify(String code) async {
    if (!canVerify) return;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      error = MfaError.invalidCode;
      _emit();
      return;
    }
    final factor = selectedId!;
    if (!repository.operations.acquire()) return;
    _busy = true;
    phase = MfaPhase.verifying;
    error = null;
    _emit();
    try {
      // Refresh ownership/status before challenging, including pending factors.
      final fresh = await repository.inspect();
      if (!current) return;
      _apply(fresh);
      if (!fresh.totp.any((f) => f.id == factor)) {
        throw const MfaFailure(MfaError.expired);
      }
      await repository.verify(factor, code);
      code =
          ''; // Release our reference; this is not guaranteed secure erasure.
      if (!current) return;
      setup = null;
      final confirmed = await repository.inspect();
      if (!current) return;
      _apply(confirmed);
      if (!confirmed.confirmed) error = MfaError.contextMismatch;
    } catch (e) {
      if (current) await _reconcile(e);
    } finally {
      code = '';
      _busy = false;
      _scheduleRetryReady();
      repository.operations.release();
      if (!current && !_disposed) invalidateAccount();
      _emit();
    }
  }

  void cancel() {
    // In-flight requests cannot be cancelled. UI disposal releases references;
    // their completion cannot revive this controller or start a replacement.
    setup = null;
    status = null;
    selectedId = null;
    phase = MfaPhase.unavailable;
    _emit();
  }

  @override
  void dispose() {
    _retryReady?.cancel();
    repository.operations.removeListener(_emit);
    _disposed = true;
    setup = null;
    status = null;
    selectedId = null;
    super.dispose();
  }
}
