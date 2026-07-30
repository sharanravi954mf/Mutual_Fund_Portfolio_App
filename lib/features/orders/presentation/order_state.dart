import '../data/order_repository.dart';
import '../domain/order_models.dart';

class OrderState {
  final OrderPhase phase;
  final OrderDraft draft;
  final List<Map<String, dynamic>> funds;
  final List<OrderFolio> folios;
  final List<OrderInvestor> assignedInvestors;
  final List<Map<String, dynamic>> holdings;
  final String? errorMessage;
  final String? submittedOrderId;

  const OrderState({
    required this.phase,
    required this.draft,
    this.funds = const [],
    this.folios = const [],
    this.assignedInvestors = const [],
    this.holdings = const [],
    this.errorMessage,
    this.submittedOrderId,
  });

  OrderState copyWith({
    OrderPhase? phase,
    OrderDraft? draft,
    List<Map<String, dynamic>>? funds,
    List<OrderFolio>? folios,
    List<OrderInvestor>? assignedInvestors,
    List<Map<String, dynamic>>? holdings,
    String? errorMessage,
    String? submittedOrderId,
    bool clearErrorMessage = false,
    bool clearSubmittedOrderId = false,
  }) {
    return OrderState(
      phase: phase ?? this.phase,
      draft: draft ?? this.draft,
      funds: funds ?? this.funds,
      folios: folios ?? this.folios,
      assignedInvestors: assignedInvestors ?? this.assignedInvestors,
      holdings: holdings ?? this.holdings,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      submittedOrderId: clearSubmittedOrderId
          ? null
          : (submittedOrderId ?? this.submittedOrderId),
    );
  }
}
