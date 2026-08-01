import 'package:flutter/material.dart';
import '../data/order_repository.dart';
import '../domain/order_models.dart';
import 'order_state.dart';

class OrderBloc extends ChangeNotifier {
  final OrderRepository _repository;
  OrderState _state;

  // Immutable initiator context — stored independently from any beneficiary
  // selection so it is never overwritten when the advisor changes client.
  String? _initiatorProfileId;
  String? _initiationRole;
  String? _initiationChannel;

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
    _initiatorProfileId = initiatorProfileId;
    _initiationRole = initiationRole;
    _initiationChannel = initiationChannel;

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

      final funds = await _repository.fetchInitialMutualFunds();
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
    } catch (_) {
      _updateState(_state.copyWith(
        phase: OrderPhase.failure,
        errorMessage:
            'Unable to initialize the order session. Please try again.',
      ));
    }
  }

  /// Initialize context for Advisor Flow.
  ///
  /// When [preSelectedInvestorId] is null, the advisor must select a
  /// beneficiary from their assigned investor list.
  Future<void> initiateForAdvisor({
    required String advisorProfileId,
    String? preSelectedInvestorId,
    String? selectedWorkspaceId,
    required String initiatorProfileId,
    required String initiationRole,
    required String initiationChannel,
  }) async {
    _initiatorProfileId = initiatorProfileId;
    _initiationRole = initiationRole;
    _initiationChannel = initiationChannel;

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
          selectedWorkspaceId: selectedWorkspaceId,
        );

        final funds = await _repository.fetchInitialMutualFunds();
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

        final funds = await _repository.fetchInitialMutualFunds();

        _updateState(_state.copyWith(
          phase: OrderPhase.ready,
          assignedInvestors: assigned,
          funds: funds,
        ));
      }
    } on OrderFailure catch (e) {
      _updatePhaseForFailure(e);
    } catch (_) {
      _updateState(_state.copyWith(
        phase: OrderPhase.failure,
        errorMessage:
            'Unable to initialize the advisor session. Please try again.',
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

  /// Update active beneficiary client & workspace.
  ///
  /// This clears all stale financial fields but preserves immutable
  /// initiator context: [_initiatorProfileId], [_initiationRole], and
  /// [_initiationChannel] are never read from the draft that was just cleared.
  Future<void> updateBeneficiary(
      String investorProfileId, String workspaceId) async {
    // Prevent setting workspaceId = investorProfileId
    if (workspaceId == investorProfileId) {
      _updateState(_state.copyWith(
        phase: OrderPhase.failure,
        errorMessage:
            'Invalid context mapping: Workspace ID cannot be identical to Investor Profile ID.',
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
      // Read initiator values from the bloc-level fields, NOT from a draft
      // context that has just been cleared.
      final context = await _repository.resolveInvestorContext(
        investorProfileId: investorProfileId,
        initiatorProfileId: _initiatorProfileId ?? '',
        initiationRole: _initiationRole ?? '',
        initiationChannel: _initiationChannel ?? '',
        selectedWorkspaceId: workspaceId,
      );

      final folios =
          await _repository.fetchFolios(investorProfileId, context.workspaceId);

      _updateState(_state.copyWith(
        phase: OrderPhase.ready,
        draft: _state.stateDraftWithContext(context),
        folios: folios,
        holdings: const [],
      ));
    } on OrderFailure catch (e) {
      _updatePhaseForFailure(e);
    } catch (_) {
      _updateState(_state.copyWith(
        phase: OrderPhase.failure,
        errorMessage: 'Unable to load the selected client. Please try again.',
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
      final folio = _state.draft.folioNumber;
      if (folio != null && folio.isNotEmpty) {
        _updateState(_state.copyWith(phase: OrderPhase.loadingReferenceData));
        try {
          final holdings = await _repository.fetchHoldings(
              ctx.investorProfileId, ctx.workspaceId, folio);
          _updateState(_state.copyWith(
            phase: OrderPhase.ready,
            holdings: holdings,
          ));
        } on OrderFailure catch (e) {
          _updatePhaseForFailure(e);
        } catch (_) {
          _updateState(_state.copyWith(
            phase: OrderPhase.failure,
            errorMessage: 'Unable to load holdings. Please try again.',
          ));
        }
      } else {
        _updateState(_state.copyWith(
          holdings: const [],
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
            ctx.investorProfileId, ctx.workspaceId, folioNumber);

        // Check if current schemeCode is held in this folio.
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
      } catch (_) {
        _updateState(_state.copyWith(
          phase: OrderPhase.failure,
          errorMessage: 'Unable to load folio holdings. Please try again.',
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
    } catch (_) {
      _updateState(_state.copyWith(
        phase: OrderPhase.failure,
        errorMessage: 'An unexpected error occurred. Please try again.',
      ));
    }
  }

  void setAccessDenied(String message) {
    _updateState(_state.copyWith(
      phase: OrderPhase.accessDenied,
      errorMessage: message,
    ));
  }
}

extension on OrderState {
  OrderDraft stateDraftWithContext(OrderContext context) {
    return draft.copyWith(context: context);
  }
}
