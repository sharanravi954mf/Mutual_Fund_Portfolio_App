import 'package:flutter/foundation.dart';
import 'dart:math';
import '../data/onboarding_kyc_repository.dart';
import '../models/onboarding_case.dart';

class OnboardingKycController extends ChangeNotifier {
  OnboardingKycController(this.repository);
  final OnboardingKycRepository repository;
  List<Map<String, String>> workspaces = [];
  List<OnboardingCase> cases = [];
  KycCase? current;
  String? workspace, error;
  bool busy = false, loaded = false, editing = true, _disposed = false;
  String _draft = _uuid();
  final Map<String, String> _requests = {};
  static String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  @override
  void dispose() {
    _disposed = true;
    current = null;
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (_) {
      if (!_disposed) {
        error =
            'Unable to complete this action securely. Refresh the saved case or contact support.';
      }
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> load({bool startNew = true}) => _run(() async {
        final ws = await repository.legacy.workspaces();
        if (_disposed) return;
        workspaces = ws;
        workspace ??= ws.isEmpty ? null : ws.first['id'];
        if (workspace != null) {
          final rows = await repository.legacy.list(workspace!);
          if (_disposed) return;
          cases = rows;
        }
        editing = startNew;
        loaded = true;
      });
  void start() {
    if (busy) return;
    current = null;
    editing = true;
    _draft = _uuid();
    _requests.clear();
    error = null;
    notifyListeners();
  }

  Future<void> resume(String id) => _run(() async {
        final value = await repository.get(id);
        if (_disposed) return;
        current = value;
        editing = true;
      });
  Future<void> check(String pan) => _run(() async {
        final saved = current == null || current!.state == 'DRAFT'
            ? await repository.start(
                workspace!, current?.id ?? _draft, pan.trim().toUpperCase())
            : current!;
        if (_disposed) return;
        current = saved;
        if (saved.state != 'KYC_CHECK_REQUIRED') return;
        final value = await repository.request(
            saved.id, _requests.putIfAbsent('CHECK', () => _uuid()), 'CHECK');
        if (!_disposed) current = value;
      });
  Future<void> act(String action,
          {String? email, String? mobile, String? amc}) =>
      _run(() async {
        final value = await repository.request(
            current!.id, _requests.putIfAbsent(action, () => _uuid()), action,
            email: email, mobile: mobile, amc: amc);
        if (!_disposed) current = value;
      });
  Future<void> refreshView() => _run(() async {
        final value = await repository.get(current!.id);
        if (_disposed) return;
        current = value;
        if (value.state == 'EKYC_IN_PROGRESS') _requests.remove('REFRESH');
      });
  Future<void> open(Future<bool> Function(Uri) launch) => _run(() async {
        final secret = await repository.link(current!.id);
        if (_disposed) return;
        final uri = secret == null ? null : Uri.tryParse(secret);
        if (uri == null ||
            secret!.length > 2048 ||
            uri.scheme != 'https' ||
            uri.host != 'nseinvestuat.nseindia.com' ||
            uri.userInfo.isNotEmpty ||
            uri.hasPort ||
            uri.hasQuery ||
            uri.hasFragment ||
            !RegExp(r'^/nsemfdesk/ekycVerifyByUser/[A-Za-z0-9_-]{1,255}$')
                .hasMatch(uri.path)) {
          throw StateError('secure_action_unavailable');
        }
        if (!await launch(uri)) throw StateError('secure_action_unavailable');
      });
}
