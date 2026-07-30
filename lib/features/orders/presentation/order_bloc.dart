import 'package:flutter/material.dart';
import '../data/order_repository.dart';
import '../domain/order_models.dart';
import 'order_state.dart';

class OrderBloc extends ChangeNotifier {
  final OrderRepository _repository;
  OrderState _state;

  OrderBloc(this._repository)
      : _state = const OrderState(
          phase: OrderPhase.initial,
          draft: OrderDraft(schemeCode: '', type: OrderType.buy),
        );

  OrderState get state => _state;

  void _updateState(OrderState newState) {
    _state = newState;
    notifyListeners();
  }

  /// Initialize context for Investor Flow
  Future<void> initiateForInvestor({
    required String investorProfileId,
    required String initiatorProfileId,
    required String initiationRole,
    required String initiationChannel,
  }) async {
    _updateState(_state.copyWith(
      phase: OrderPhase.loadingReferenceData,
      clearErrorMessage: true,
      clearSubmittedOrderId: true,
    ));

    try {
      final context = await _repository.resolveInvestorContext(
        investorProfileId: investorProfileId,
        initiatorProfileId: initiatorProfileId,
        initiationRole: initiationRole,
        initiationChannel: initiationChannel,
      );

      final funds = await _repository.fetchMutualFunds();
      final folios =
          await _repository.fetchFolios(investorProfileId, context.workspaceId);

      _updateState(_state.copyWith(
        phase: OrderPhase.ready,
        draft: _state.stateDraftWithContext(context),
        funds: funds,
        folios: folios,
      ));
    } on OrderFailure catch (e) {
      _updatePhaseForFailure(e);
    } catch (e) {
      _updateState(_state.copyWith(
        phase: OrderPhase.failure,
        errorMessage: "Initialization failed: $e",
      ));
    }
  }

  /// Initialize context for Advisor Flow
  Future<void> initiateForAdvisor({
    required String advisorProfileId,
    String? preSelectedInvestorId,
    required String initiatorProfileId,
    required String initiationRole,
    required String initiationChannel,
  }) async {
    _updateState(_state.copyWith(
      phase: OrderPhase.loadingReferenceData,
      clearErrorMessage: true,
      clearSubmittedOrderId: true,
    ));

    try {
      if (preSelectedInvestorId != null) {
        final context = await _repository.resolveInvestorContext(
          investorProfileId: preSelectedInvestorId,
          initiatorProfileId: initiatorProfileId,
          initiationRole: initiationRole,
          initiationChannel: initiationChannel,
        );

        final funds = await _repository.fetchMutualFunds();
        final folios = await _repository.fetchFolios(
            preSelectedInvestorId, context.workspaceId);

        _updateState(_state.copyWith(
          phase: OrderPhase.ready,
          draft: _state.stateDraftWithContext(context),
          funds: funds,
          folios: folios,
        ));
      } else {
        final assigned =
            await _repository.fetchAssignedInvestors(advisorProfileId);
        if (assigned.isEmpty) {
          _updateState(_state.copyWith(
            phase: OrderPhase.emptyInvestors,
            assignedInvestors: const [],
          ));
          return;
        }

        final funds = await _repository.fetchMutualFunds();

        _updateState(_state.copyWith(
          phase: OrderPhase.ready,
          assignedInvestors: assigned,
          funds: funds,
        ));
      }
    } on OrderFailure catch (e) {
      _updatePhaseForFailure(e);
    } catch (e) {
      _updateState(_state.copyWith(
        phase: OrderPhase.failure,
        errorMessage: "Initialization failed: $e",
      ));
    }
  }

  /// Handle typed failures and update state phase accordingly
  void _updatePhaseForFailure(OrderFailure failure) {
    OrderPhase nextPhase = OrderPhase.failure;
    if (failure is AccessDeniedFailure) {
      nextPhase = OrderPhase.accessDenied;
    } else if (failure is NetworkFailure) {
      nextPhase = OrderPhase.offline;
    } else if (failure is EmptyFailure) {
      nextPhase = OrderPhase.emptyInvestors;
    }
    _updateState(_state.copyWith(
      phase: nextPhase,
      errorMessage: failure.message,
    ));
  }

  /// Update active beneficiary client & workspace
  Future<void> updateBeneficiary(
      String investorProfileId, String workspaceId) async {
    // Prevent setting workspaceId = investorProfileId
    if (workspaceId == investorProfileId) {
      _updateState(_state.copyWith(
        phase: OrderPhase.failure,
        errorMessage:
            "Invalid context mapping: Workspace ID cannot be identical to Investor Profile ID.",
      ));
      return;
    }

    _updateState(_state.copyWith(
      phase: OrderPhase.loadingReferenceData,
      clearErrorMessage: true,
      // Clear all stale financial fields on beneficiary swap
      draft: _state.draft.copyWith(
        clearContext: true,
        schemeCode: '',
        clearAmount: true,
        clearUnits: true,
        clearFolio: true,
        clearDestScheme: true,
      ),
    ));

    try {
      final context = await _repository.resolveInvestorContext(
        investorProfileId: investorProfileId,
        initiatorProfileId: _state.draft.context?.initiatorProfileId ?? '',
        initiationRole: _state.draft.context?.initiationRole ?? '',
        initiationChannel: _state.draft.context?.initiationChannel ?? '',
      );

      final folios =
          await _repository.fetchFolios(investorProfileId, context.workspaceId);
      final holdings = await _repository.fetchHoldings(
          investorProfileId, context.workspaceId);

      _updateState(_state.copyWith(
        phase: OrderPhase.ready,
        draft: _state.stateDraftWithContext(context),
        folios: folios,
        holdings: holdings,
      ));
    } on OrderFailure catch (e) {
      _updatePhaseForFailure(e);
    } catch (e) {
      _updateState(_state.copyWith(
        phase: OrderPhase.failure,
        errorMessage: "Failed to load beneficiary context: $e",
      ));
    }
  }

  /// Update order type (Buy/Sell/Switch) and reset stale inputs
  Future<void> updateOrderType(OrderType type) async {
    final ctx = _state.draft.context;
    // Clear all stale financial fields on order type switch
    var newDraft = _state.draft.copyWith(
      type: type,
      schemeCode: '',
      clearAmount: true,
      clearUnits: true,
      clearFolio: true,
      clearDestScheme: true,
    );

    _updateState(_state.copyWith(
      draft: newDraft,
      clearErrorMessage: true,
    ));

    if (ctx != null &&
        (type == OrderType.sell || type == OrderType.switchOrder)) {
      _updateState(_state.copyWith(phase: OrderPhase.loadingReferenceData));
      try {
        final holdings = await _repository.fetchHoldings(
            ctx.investorProfileId, ctx.workspaceId);
        _updateState(_state.copyWith(
          phase: OrderPhase.ready,
          holdings: holdings,
        ));
      } on OrderFailure catch (e) {
        _updatePhaseForFailure(e);
      } catch (e) {
        _updateState(_state.copyWith(
          phase: OrderPhase.failure,
          errorMessage: "Failed to load holdings: $e",
        ));
      }
    }
  }

  /// Update selected scheme
  void updateScheme(String schemeCode) {
    _updateState(_state.copyWith(
      draft: _state.draft.copyWith(schemeCode: schemeCode),
    ));
  }

  /// Update Switch destination scheme
  void updateDestScheme(String destSchemeCode) {
    _updateState(_state.copyWith(
      draft: _state.draft.copyWith(destSchemeCode: destSchemeCode),
    ));
  }

  /// Update selected folio & clear incompatible schemes
  Future<void> updateFolio(String folioNumber) async {
    var newDraft = _state.draft.copyWith(folioNumber: folioNumber);
    final ctx = _state.draft.context;

    if (ctx != null &&
        (_state.draft.type == OrderType.sell ||
            _state.draft.type == OrderType.switchOrder)) {
      // List only source schemes actually held in the selected folio
      _updateState(_state.copyWith(phase: OrderPhase.loadingReferenceData));
      try {
        final holdings = await _repository.fetchHoldings(
            ctx.investorProfileId, ctx.workspaceId);

        // Check if current schemeCode is held in this folio (or portfolio).
        // If not, clear the incompatible scheme.
        final isHeld =
            holdings.any((h) => h['scheme_code'] == _state.draft.schemeCode);
        if (!isHeld) {
          newDraft = newDraft.copyWith(schemeCode: '');
        }

        _updateState(_state.copyWith(
          phase: OrderPhase.ready,
          draft: newDraft,
          holdings: holdings,
        ));
      } on OrderFailure catch (e) {
        _updatePhaseForFailure(e);
      } catch (e) {
        _updateState(_state.copyWith(
          phase: OrderPhase.failure,
          errorMessage: "Failed to update folio: $e",
        ));
      }
    } else {
      _updateState(_state.copyWith(draft: newDraft));
    }
  }

  /// Update transaction amount
  void updateAmount(double? amount) {
    _updateState(_state.copyWith(
      draft: _state.draft.copyWith(
        amount: amount,
        clearUnits: true,
      ),
    ));
  }

  /// Update transaction units
  void updateUnits(double? units) {
    _updateState(_state.copyWith(
      draft: _state.draft.copyWith(
        units: units,
        clearAmount: true,
      ),
    ));
  }

  /// Submit order intent
  Future<void> submitOrder() async {
    // 1. Validation
    final errors = _state.draft.validate();
    if (errors != null && errors.isNotEmpty) {
      _updateState(_state.copyWith(
        phase: OrderPhase.failure,
        errorMessage: errors.join('\n'),
      ));
      return;
    }

    // 2. Prevent duplicate submissions
    if (_state.phase == OrderPhase.submitting) return;

    _updateState(_state.copyWith(phase: OrderPhase.submitting));

    try {
      final orderId = await _repository.submitOrder(_state.draft);
      _updateState(_state.copyWith(
        phase: OrderPhase.submitted,
        submittedOrderId: orderId,
        clearErrorMessage: true,
      ));
    } on OrderFailure catch (e) {
      _updatePhaseForFailure(e);
    } catch (e) {
      _updateState(_state.copyWith(
        phase: OrderPhase.failure,
        errorMessage: "Submission failed: $e",
      ));
    }
  }
}

extension on OrderState {
  OrderDraft stateDraftWithContext(OrderContext context) {
    return draft.copyWith(context: context);
  }
}
