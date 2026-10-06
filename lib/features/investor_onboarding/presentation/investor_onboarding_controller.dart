import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/investor_onboarding_repository.dart';
import '../models/onboarding_case.dart';

enum OnboardingPhase {
  loading,
  directory,
  editing,
  review,
  saved,
  unavailable,
  failure
}

class InvestorOnboardingController extends ChangeNotifier {
  InvestorOnboardingController(this.repository);
  final InvestorOnboardingRepository repository;
  OnboardingPhase phase = OnboardingPhase.loading;
  List<Map<String, String>> workspaces = [];
  List<OnboardingCase> cases = [];
  String? workspace, error;
  OnboardingCase? current;
  Map<String, String> fields = {};
  String? _draftId;
  bool busy = false, _disposed = false;
  int _generation = 0;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    fields.clear();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(Future<void> Function(int) work) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    final generation = ++_generation;
    _notify();
    try {
      await work(generation);
    } catch (e) {
      if (_valid(generation)) {
        error = _message(e);
        if (phase == OnboardingPhase.loading) phase = OnboardingPhase.failure;
      }
    } finally {
      if (_valid(generation)) {
        busy = false;
        _notify();
      }
    }
  }

  bool _valid(int generation) => !_disposed && generation == _generation;
  Future<void> load() => _run((g) async {
        phase = OnboardingPhase.loading;
        final result = await repository.workspaces();
        if (!_valid(g)) return;
        workspaces = result;
        if (result.isEmpty) {
          phase = OnboardingPhase.unavailable;
          return;
        }
        workspace ??= result.first['id'];
        final rows = await repository.list(workspace!);
        if (!_valid(g)) return;
        cases = rows;
        phase = OnboardingPhase.directory;
      });
  Future<void> selectWorkspace(String id) async {
    if (busy || !workspaces.any((w) => w['id'] == id)) return;
    current = null;
    fields = {};
    workspace = id;
    await load();
  }

  void start() {
    if (busy || workspace == null) return;
    current = null;
    fields = {};
    error = null;
    _draftId = _uuid();
    phase = OnboardingPhase.editing;
    _notify();
  }

  Future<void> resume(String id) => _run((g) async {
        final result = await repository.get(id);
        if (!_valid(g)) return;
        current = result;
        fields = Map.of(result.fields);
        _draftId = result.id;
        phase = OnboardingPhase.saved;
      });
  void edit() {
    if (!busy) {
      phase = OnboardingPhase.editing;
      _notify();
    }
  }

  void review() {
    if (!busy) {
      phase = OnboardingPhase.review;
      error = null;
      _notify();
    }
  }

  Future<void> save({bool resolve = false}) => _run((g) async {
        final saved = await repository.save(
            workspace!, _draftId!, current?.version ?? 0, Map.of(fields));
        if (!_valid(g)) return;
        current = saved;
        _draftId = saved.id;
        fields = Map.of(saved.fields);
        if (resolve) {
          final resolved = await repository.resolve(saved.id, saved.version);
          if (!_valid(g)) return;
          current = resolved;
          _draftId = resolved.id;
          fields = Map.of(resolved.fields);
        }
        phase = OnboardingPhase.saved;
      });
  static String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  static String _message(Object e) {
    final code = e is PostgrestException ? e.message : '';
    const messages = {
      'onboarding_not_authorized':
          'Your MFD authority or workspace access is unavailable. Return to Clients and refresh.',
      'onboarding_version_conflict':
          'This draft changed elsewhere. Resume it again before editing.',
      'identity_details_required':
          'Enter the legal name and PAN before continuing onboarding.',
      'resolved_identity_immutable':
          'Resolved identity details require reconciliation. Contact platform support; do not create another investor.',
      'verified_registration_requires_review':
          'Verified registration details need a review before they can be changed.',
      'bank_change_requires_review':
          'This bank record needs review before it can be changed.',
      'registration_inputs_locked':
          'Registration is already in progress. Review its status before changing details.',
      'invalid_onboarding_choice':
          'Choose a supported value or leave it incomplete.',
      'invalid_ckyc_number':
          'Enter the 14-digit CKYC number or leave it incomplete.',
      'invalid_pan': 'Enter a valid PAN.',
      'invalid_email': 'Enter a valid email.',
      'invalid_mobile': 'Enter a mobile number with country code.',
      'invalid_date_of_birth': 'Enter a valid past date in YYYY-MM-DD format.',
      'invalid_ifsc_code': 'Enter a valid IFSC.',
      'invalid_micr_code': 'Enter a 9-digit MICR.',
      'invalid_bank_account_number': 'Check the bank account number.',
    };
    return messages[code] ??
        'Unable to save securely. Your entries are retained. Retry or resume the saved draft.';
  }
}
