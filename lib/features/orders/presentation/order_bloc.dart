import 'package:flutter/material.dart';
import '../data/order_repository.dart';
import '../domain/order_models.dart';
import 'order_state.dart';

class OrderBloc extends ChangeNotifier {
  final OrderRepository repository;
  OrderState _state;

  OrderBloc(
    this.repository, {
    required String workspaceId,
    required String investorProfileId,
  }) : _state = OrderState.initial(
          workspaceId: workspaceId,
          investorProfileId: investorProfileId,
        );

  OrderState get state => _state;

  void _updateState(OrderState newState) {
    _state = newState;
    notifyListeners();
  }

  /// Load reference data: mutual funds, folios, and optionally assigned investors
  Future<void> loadReferenceData(
    String currentProfileId, {
    required bool isAdvisor,
  }) async {
    _updateState(_state.copyWith(phase: 'loadingReferenceData'));

    try {
      final funds = await repository.fetchMutualFunds();
      final folios =
          await repository.fetchFolios(_state.draft.investorProfileId);
      List<OrderInvestor> assigned = const [];

      if (isAdvisor) {
        assigned = await repository.fetchAssignedInvestors(currentProfileId);
      }

      _updateState(_state.copyWith(
        phase: 'ready',
        funds: funds,
        folios: folios,
        assignedInvestors: assigned,
      ));
    } catch (e) {
      _updateState(_state.copyWith(
        phase: 'failure',
        errorMessage: 'Failed to load reference data. Please try again.',
      ));
    }
  }

  /// Update order type and safely clear incompatible draft fields
  void updateOrderType(OrderType type) {
    final draft = _state.draft;
    // Clear amount, units, folio, destSchemeCode when type changes to prevent stale states
    final clearedDraft = draft.copyWith(
      type: type,
      clearAmount: true,
      clearUnits: true,
      clearFolio: true,
      clearDestScheme: true,
    );

    _updateState(_state.copyWith(
      draft: clearedDraft,
      errorMessage: null,
    ));

    // Reload folios since sell/switch require them
    if (type == OrderType.sell || type == OrderType.switchOrder) {
      _loadFoliosOnly();
    }
  }

  /// Update the beneficiary investor (Advisor-only flow)
  Future<void> updateBeneficiary(
      String investorProfileId, String workspaceId) async {
    final clearedDraft = _state.draft.copyWith(
      investorProfileId: investorProfileId,
      workspaceId: workspaceId,
      schemeCode: '',
      clearAmount: true,
      clearUnits: true,
      clearFolio: true,
      clearDestScheme: true,
    );

    _updateState(_state.copyWith(
      draft: clearedDraft,
      phase: 'loadingReferenceData',
      errorMessage: null,
    ));

    try {
      final folios = await repository.fetchFolios(investorProfileId);
      _updateState(_state.copyWith(
        phase: 'ready',
        folios: folios,
      ));
    } catch (e) {
      _updateState(_state.copyWith(
        phase: 'failure',
        errorMessage: 'Failed to load folios for beneficiary.',
      ));
    }
  }

  Future<void> _loadFoliosOnly() async {
    try {
      final folios =
          await repository.fetchFolios(_state.draft.investorProfileId);
      _updateState(_state.copyWith(folios: folios));
    } catch (_) {}
  }

  void updateScheme(String schemeCode) {
    _updateState(_state.copyWith(
      draft: _state.draft.copyWith(schemeCode: schemeCode),
      errorMessage: null,
    ));
  }

  void updateFolio(String folioNumber) {
    _updateState(_state.copyWith(
      draft: _state.draft.copyWith(folioNumber: folioNumber),
      errorMessage: null,
    ));
  }

  void updateDestScheme(String destSchemeCode) {
    _updateState(_state.copyWith(
      draft: _state.draft.copyWith(destSchemeCode: destSchemeCode),
      errorMessage: null,
    ));
  }

  void updateAmount(double? amount) {
    _updateState(_state.copyWith(
      draft: _state.draft
          .copyWith(amount: amount, clearUnits: true), // Mutual exclusivity
      errorMessage: null,
    ));
  }

  void updateUnits(double? units) {
    _updateState(_state.copyWith(
      draft: _state.draft
          .copyWith(units: units, clearAmount: true), // Mutual exclusivity
      errorMessage: null,
    ));
  }

  /// Submit the order to Supabase
  Future<void> submitOrder({
    required String initiatedByProfileId,
    required String initiatedByRole,
    required String initiationChannel,
  }) async {
    // Duplicate submission guard
    if (_state.phase == 'submitting' || _state.phase == 'submitted') {
      return;
    }

    _updateState(_state.copyWith(phase: 'validating'));

    final validationErrors = _state.draft.validate();
    if (validationErrors != null && validationErrors.isNotEmpty) {
      _updateState(_state.copyWith(
        phase: 'failure',
        errorMessage: validationErrors.join('\n'),
      ));
      return;
    }

    _updateState(_state.copyWith(phase: 'submitting'));

    try {
      final orderId = await repository.submitOrder(
        _state.draft,
        initiatedByProfileId: initiatedByProfileId,
        initiatedByRole: initiatedByRole,
        initiationChannel: initiationChannel,
      );

      _updateState(_state.copyWith(
        phase: 'submitted',
        submittedOrderId: orderId,
      ));
    } catch (e) {
      // Map error safely without exposing raw DB exception
      String friendlyError =
          'Submission failed. Please check connection and try again.';
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('permission') || errStr.contains('not_authorized')) {
        friendlyError =
            'Access Denied: You are not authorized to initiate this order.';
      } else if (errStr.contains('relationship')) {
        friendlyError = 'Invalid beneficiary relationship in this workspace.';
      }

      _updateState(_state.copyWith(
        phase: 'failure',
        errorMessage: friendlyError,
      ));
    }
  }

  /// Reset form state back to ready for placing another order
  void reset() {
    _updateState(_state.copyWith(
      phase: 'ready',
      submittedOrderId: null,
      errorMessage: null,
      draft: _state.draft.copyWith(
        schemeCode: '',
        amount: null,
        units: null,
        folioNumber: null,
        destSchemeCode: null,
      ),
    ));
  }
}
