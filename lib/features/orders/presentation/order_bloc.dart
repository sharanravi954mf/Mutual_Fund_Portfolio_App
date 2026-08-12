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
  int _holdingsRequestId = 0;
  int _beneficiaryRequestId = 0;

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

  int _nextBeneficiaryRequest() {
    _holdingsRequestId++;
    return ++_beneficiaryRequestId;
  }

  bool _isCurrentBeneficiaryRequest(int requestId) {
    return requestId == _beneficiaryRequestId;
  }

  /// Initialize context for Investor Flow
  Future<void> initiateForInvestor({
    required String investorProfileId,
    required String initiatorProfileId,
    required String initiationRole,
    required String initiationChannel,
  }) async {
    final requestId = _nextBeneficiaryRequest();
    _initiatorProfileId = initiatorProfileId;
    _initiationRole = initiationRole;
    _initiationChannel = initiationChannel;

    _updateState(_state.copyWith(
      phase: OrderPhase.loadingReferenceData,
      clearSelectedFolio: true,
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
      if (!_isCurrentBeneficiaryRequest(requestId)) return;

      final funds = await _repository.fetchInitialMutualFunds();
      if (!_isCurrentBeneficiaryRequest(requestId)) return;

      final folios =
          await _repository.fetchFolios(investorProfileId, context.workspaceId);
      if (!_isCurrentBeneficiaryRequest(requestId)) return;

      _updateState(_state.copyWith(
        phase: OrderPhase.ready,
        draft: _state.stateDraftWithContext(context),
        funds: funds,
        folios: folios,
      ));
    } on OrderFailure catch (e) {
      if (!_isCurrentBeneficiaryRequest(requestId)) return;
      _updatePhaseForFailure(e);
    } catch (_) {
      if (!_isCurrentBeneficiaryRequest(requestId)) return;
      _updateState(_state.copyWith(
        phase: OrderPhase.recoverableFailure,
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
    final requestId = _nextBeneficiaryRequest();
    _initiatorProfileId = initiatorProfileId;
    _initiationRole = initiationRole;
    _initiationChannel = initiationChannel;

    _updateState(_state.copyWith(
      phase: OrderPhase.loadingReferenceData,
      clearSelectedFolio: true,
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
        if (!_isCurrentBeneficiaryRequest(requestId)) return;

        final funds = await _repository.fetchInitialMutualFunds();
        if (!_isCurrentBeneficiaryRequest(requestId)) return;

        final folios = await _repository.fetchFolios(
            preSelectedInvestorId, context.workspaceId);
        if (!_isCurrentBeneficiaryRequest(requestId)) return;

        _updateState(_state.copyWith(
          phase: OrderPhase.ready,
          draft: _state.stateDraftWithContext(context),
          funds: funds,
          folios: folios,
        ));
      } else {
        final assigned =
            await _repository.fetchAssignedInvestors(advisorProfileId);
        if (!_isCurrentBeneficiaryRequest(requestId)) return;

        if (assigned.isEmpty) {
          _updateState(_state.copyWith(
            phase: OrderPhase.emptyInvestors,
            assignedInvestors: const [],
          ));
          return;
        }

        final funds = await _repository.fetchInitialMutualFunds();
        if (!_isCurrentBeneficiaryRequest(requestId)) return;

        _updateState(_state.copyWith(
          phase: OrderPhase.ready,
          assignedInvestors: assigned,
          funds: funds,
        ));
      }
    } on OrderFailure catch (e) {
      if (!_isCurrentBeneficiaryRequest(requestId)) return;
      _updatePhaseForFailure(e);
    } catch (_) {
      if (!_isCurrentBeneficiaryRequest(requestId)) return;
      _updateState(_state.copyWith(
        phase: OrderPhase.recoverableFailure,
        errorMessage:
            'Unable to initialize the advisor session. Please try again.',
      ));
    }
  }

  /// Handle typed failures and update state phase accordingly
  void _updatePhaseForFailure(OrderFailure failure) {
    OrderPhase nextPhase = OrderPhase.recoverableFailure;
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
    final requestId = _nextBeneficiaryRequest();
    // Prevent setting workspaceId = investorProfileId
    if (workspaceId == investorProfileId) {
      _updateState(_state.copyWith(
        phase: OrderPhase.validationFailure,
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
        clearDestinationScheme: true,
      ),
      clearSelectedFolio: true,
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
      if (!_isCurrentBeneficiaryRequest(requestId)) return;

      final folios =
          await _repository.fetchFolios(investorProfileId, context.workspaceId);
      if (!_isCurrentBeneficiaryRequest(requestId)) return;

      _updateState(_state.copyWith(
        phase: OrderPhase.ready,
        draft: _state.stateDraftWithContext(context),
        folios: folios,
        holdings: const [],
      ));
    } on OrderFailure catch (e) {
      if (!_isCurrentBeneficiaryRequest(requestId)) return;
      _updatePhaseForFailure(e);
    } catch (_) {
      if (!_isCurrentBeneficiaryRequest(requestId)) return;
      _updateState(_state.copyWith(
        phase: OrderPhase.recoverableFailure,
        errorMessage: 'Unable to load the selected client. Please try again.',
      ));
    }
  }

  /// Update order type (Buy/Sell/Switch) and reset stale inputs
  Future<void> updateOrderType(OrderType type) async {
    _holdingsRequestId++;
    // Clear all stale financial fields on order type switch
    final newDraft = _state.draft.copyWith(
      type: type,
      schemeCode: '',
      clearAmount: true,
      clearUnits: true,
      clearFolio: true,
      clearDestinationScheme: true,
    );

    _updateState(_state.copyWith(
      draft: newDraft,
      holdings: const [],
      clearSelectedFolio: true,
      clearErrorMessage: true,
    ));
  }

  /// Update selected scheme
  void updateScheme(String schemeCode) {
    final shouldClearDestination = _state.draft.type == OrderType.switchOrder &&
        _state.draft.destinationSchemeCode == schemeCode;
    _updateState(_state.copyWith(
      draft: _state.draft.copyWith(
        schemeCode: schemeCode,
        clearDestinationScheme: shouldClearDestination,
      ),
      clearErrorMessage: true,
    ));
  }

  /// Update Switch destination scheme
  void updateDestinationScheme(String destinationSchemeCode) {
    _updateState(_state.copyWith(
      draft:
          _state.draft.copyWith(destinationSchemeCode: destinationSchemeCode),
      clearErrorMessage: true,
    ));
  }

  /// Update selected folio & clear incompatible schemes
  Future<void> updateFolio(OrderFolio folio) async {
    final requestId = ++_holdingsRequestId;
    final folioReferenceId = folio.folioReferenceId;
    var newDraft = _state.draft.copyWith(
      folioReferenceId: folioReferenceId,
      schemeCode: '',
      clearDestinationScheme: true,
    );
    final ctx = _state.draft.context;

    if (ctx != null &&
        (_state.draft.type == OrderType.sell ||
            _state.draft.type == OrderType.switchOrder)) {
      // List only source schemes actually held in the selected folio
      _updateState(_state.copyWith(
        phase: OrderPhase.loadingReferenceData,
        draft: newDraft,
        selectedFolio: folio,
        holdings: const [],
        clearErrorMessage: true,
      ));
      try {
        final holdings = await _repository.fetchHoldings(
          ctx.investorProfileId,
          ctx.workspaceId,
          folio.portfolioId,
          folioReferenceId,
        );

        if (requestId != _holdingsRequestId ||
            _state.selectedFolio?.portfolioId != folio.portfolioId ||
            _state.selectedFolio?.folioReferenceId != folioReferenceId) {
          return;
        }

        final nextPhase =
            holdings.isEmpty ? OrderPhase.emptyHoldings : OrderPhase.ready;

        _updateState(_state.copyWith(
          phase: nextPhase,
          draft: newDraft,
          holdings: holdings,
        ));
      } on OrderFailure catch (e) {
        if (requestId != _holdingsRequestId) return;
        _updatePhaseForFailure(e);
      } catch (_) {
        if (requestId != _holdingsRequestId) return;
        _updateState(_state.copyWith(
          phase: OrderPhase.recoverableFailure,
          errorMessage: 'Unable to load folio holdings. Please try again.',
        ));
      }
    } else {
      _updateState(_state.copyWith(draft: newDraft, selectedFolio: folio));
    }
  }

  /// Update transaction amount
  void updateAmount(double? amount) {
    _updateState(_state.copyWith(
      draft: _state.draft.copyWith(
        amount: amount,
        clearAmount: amount == null,
        clearUnits: true,
      ),
      clearErrorMessage: true,
    ));
  }

  /// Update transaction units
  void updateUnits(double? units) {
    _updateState(_state.copyWith(
      draft: _state.draft.copyWith(
        units: units,
        clearUnits: units == null,
        clearAmount: true,
      ),
      clearErrorMessage: true,
    ));
  }

  /// Submit order intent
  Future<void> submitOrder() async {
    // 1. Validation
    final errors = _state.draft.validate();
    if (errors != null && errors.isNotEmpty) {
      _updateState(_state.copyWith(
        phase: OrderPhase.validationFailure,
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
        phase: OrderPhase.recoverableFailure,
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
