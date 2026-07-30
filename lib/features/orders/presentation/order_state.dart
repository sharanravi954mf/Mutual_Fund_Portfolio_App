import '../data/order_repository.dart';
import '../domain/order_models.dart';

class OrderState {
  final String
      phase; // 'initial', 'loadingReferenceData', 'ready', 'validating', 'submitting', 'submitted', 'failure'
  final OrderDraft draft;
  final List<Map<String, dynamic>> funds;
  final List<OrderFolio> folios;
  final List<OrderInvestor> assignedInvestors;
  final String? errorMessage;
  final String? submittedOrderId;

  const OrderState({
    required this.phase,
    required this.draft,
    this.funds = const [],
    this.folios = const [],
    this.assignedInvestors = const [],
    this.errorMessage,
    this.submittedOrderId,
  });

  factory OrderState.initial({
    required String workspaceId,
    required String investorProfileId,
  }) {
    return OrderState(
      phase: 'initial',
      draft: OrderDraft(
        workspaceId: workspaceId,
        investorProfileId: investorProfileId,
        schemeCode: '',
        type: OrderType.buy,
      ),
    );
  }

  OrderState copyWith({
    String? phase,
    OrderDraft? draft,
    List<Map<String, dynamic>>? funds,
    List<OrderFolio>? folios,
    List<OrderInvestor>? assignedInvestors,
    String? errorMessage,
    String? submittedOrderId,
  }) {
    return OrderState(
      phase: phase ?? this.phase,
      draft: draft ?? this.draft,
      funds: funds ?? this.funds,
      folios: folios ?? this.folios,
      assignedInvestors: assignedInvestors ?? this.assignedInvestors,
      errorMessage: errorMessage ?? this.errorMessage,
      submittedOrderId: submittedOrderId ?? this.submittedOrderId,
    );
  }
}
