import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/orders/data/order_repository.dart';
import 'package:mutual_fund_portfolio_app/features/orders/domain/masking.dart';
import 'package:mutual_fund_portfolio_app/features/orders/domain/order_models.dart';
import 'package:mutual_fund_portfolio_app/features/orders/presentation/order_bloc.dart';
import 'package:mutual_fund_portfolio_app/features/orders/presentation/order_state.dart';

void main() {
  group('MaskingUtil Tests', () {
    test('masks PAN correctly', () {
      expect(MaskingUtil.maskPan('ABC123456F'), 'ABC••••56F');
      expect(MaskingUtil.maskPan('ABC'), '••••••••••'); // malformed
    });

    test('masks Phone correctly', () {
      expect(MaskingUtil.maskPhone('9876543210'), '••••••3210');
      expect(MaskingUtil.maskPhone('123'), '••••••••••'); // malformed
    });

    test('masks Email correctly', () {
      expect(MaskingUtil.maskEmail('ravi@example.com'), 'ra•••@example.com');
      expect(MaskingUtil.maskEmail('r@ex.com'), 'r•••@ex.com');
      expect(MaskingUtil.maskEmail('invalid-email'),
          '•••••@•••••.com'); // malformed
    });

    test('masks Folio correctly', () {
      expect(MaskingUtil.maskFolio('12345678'), '••••5678');
      expect(MaskingUtil.maskFolio('12'), '••••••••'); // malformed
    });
  });

  group('OrderDraft Validation Tests', () {
    const mockContext = OrderContext(
      workspaceId: 'workspace-1',
      investorProfileId: 'investor-1',
      investorFullName: 'John Doe',
      initiatorProfileId: 'initiator-1',
      initiationRole: 'investor',
      initiationChannel: 'investor_portal',
    );

    test('validates correct Buy order', () {
      const draft = OrderDraft(
        context: mockContext,
        schemeCode: 'SCH-1',
        type: OrderType.buy,
        amount: 5000,
      );
      expect(draft.validate(), isNull);
    });

    test('validates Sell order missing folio', () {
      const draft = OrderDraft(
        context: mockContext,
        schemeCode: 'SCH-1',
        type: OrderType.sell,
        amount: 1000,
      );
      final errors = draft.validate();
      expect(errors,
          contains('Folio selection is required for Sell/Switch orders.'));
    });

    test('validates Switch order identical schemes', () {
      const draft = OrderDraft(
        context: mockContext,
        schemeCode: 'SCH-1',
        type: OrderType.switchOrder,
        folioNumber: 'FOLIO-1',
        amount: 1000,
        destSchemeCode: 'SCH-1',
      );
      final errors = draft.validate();
      expect(
          errors,
          contains(
              'Source and destination schemes cannot be identical for Switch orders.'));
    });

    test('validates negative/zero amounts and units', () {
      const draft = OrderDraft(
        context: mockContext,
        schemeCode: 'SCH-1',
        type: OrderType.buy,
        amount: -100,
      );
      final errors = draft.validate();
      expect(
          errors, contains('A positive finite amount or units is required.'));
    });
  });

  group('OrderState copyWith Nullable Clearing Tests', () {
    test('copyWith clears errorMessage and submittedOrderId correctly', () {
      const state = OrderState(
        phase: OrderPhase.ready,
        draft: OrderDraft(schemeCode: 'SCH-1', type: OrderType.buy),
        errorMessage: 'Initial error message',
        submittedOrderId: 'order-123',
      );

      final clearedState = state.copyWith(
        clearErrorMessage: true,
        clearSubmittedOrderId: true,
      );

      expect(clearedState.errorMessage, isNull);
      expect(clearedState.submittedOrderId, isNull);
    });
  });

  group('OrderBloc Tests', () {
    late FakeOrderRepository repository;
    late OrderBloc bloc;

    setUp(() {
      repository = FakeOrderRepository();
      bloc = OrderBloc(repository);
    });

    tearDown(() {
      bloc.dispose();
    });

    test('initial state matches expected properties', () {
      expect(bloc.state.phase, OrderPhase.initial);
      expect(bloc.state.draft.type, OrderType.buy);
    });

    test('initiateForInvestor populates context and reference data correctly',
        () async {
      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      expect(bloc.state.phase, OrderPhase.ready);
      expect(bloc.state.draft.context, isNotNull);
      expect(bloc.state.draft.context!.workspaceId, 'workspace-1');
      expect(bloc.state.draft.context!.initiationRole, 'investor');
      expect(bloc.state.funds, isNotEmpty);
      expect(bloc.state.folios, isNotEmpty);
    });

    test('initiateForAdvisor populates assigned investors in general flow',
        () async {
      await bloc.initiateForAdvisor(
        advisorProfileId: 'advisor-1',
        initiatorProfileId: 'advisor-1',
        initiationRole: 'advisor',
        initiationChannel: 'advisor_portal',
      );

      expect(bloc.state.phase, OrderPhase.ready);
      expect(bloc.state.assignedInvestors, isNotEmpty);
      expect(bloc.state.draft.context, isNull); // waiting for selection
    });

    test(
        'updateBeneficiary clears stale financial fields and updates workspace context',
        () async {
      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      bloc.updateScheme('SCH-1');
      bloc.updateAmount(5000);

      await bloc.updateBeneficiary('investor-2', 'workspace-2');

      expect(bloc.state.draft.context!.investorProfileId, 'investor-2');
      expect(bloc.state.draft.context!.workspaceId, 'workspace-2');
      expect(bloc.state.draft.schemeCode, isEmpty);
      expect(bloc.state.draft.amount, isNull);
    });

    test('updateOrderType clears incompatible fields', () async {
      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      bloc.updateScheme('SCH-1');
      await bloc.updateFolio('12345678');
      bloc.updateAmount(5000);

      await bloc.updateOrderType(OrderType.buy);

      expect(bloc.state.draft.type, OrderType.buy);
      expect(bloc.state.draft.amount, isNull);
      expect(bloc.state.draft.folioNumber, isNull);
    });

    test('submitOrder succeeds for Buy order', () async {
      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      bloc.updateScheme('SCH-1');
      bloc.updateAmount(5000);

      await bloc.submitOrder();

      expect(bloc.state.phase, OrderPhase.submitted);
      expect(bloc.state.submittedOrderId, 'mock-order-id');
    });

    test(
        'submitOrder blocks Sell/Switch due to database schema contract limitation',
        () async {
      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      await bloc.updateOrderType(OrderType.sell);
      bloc.updateScheme('SCH-1');
      await bloc.updateFolio('12345678');
      bloc.updateAmount(5000);

      await bloc.submitOrder();

      expect(bloc.state.phase, OrderPhase.failure);
      expect(
          bloc.state.errorMessage,
          contains(
              'Database schema error: Sell and Switch orders cannot be persisted'));
    });

    test('submitOrder blocks duplicate calls while submitting', () async {
      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      bloc.updateScheme('SCH-1');
      bloc.updateAmount(5000);

      final p1 = bloc.submitOrder();
      final p2 = bloc.submitOrder();

      await Future.wait([p1, p2]);

      expect(bloc.state.phase, OrderPhase.submitted);
      expect(repository.submitCallCount, 1); // Should only call once
    });

    test('maps AccessDeniedFailure to accessDenied phase', () async {
      repository.shouldThrowAccessDenied = true;

      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      expect(bloc.state.phase, OrderPhase.accessDenied);
    });

    test('maps NetworkFailure to offline phase', () async {
      repository.shouldThrowNetworkError = true;

      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      expect(bloc.state.phase, OrderPhase.offline);
    });
  });
}

class FakeOrderRepository implements OrderRepository {
  int submitCallCount = 0;
  bool shouldThrowAccessDenied = false;
  bool shouldThrowNetworkError = false;

  void _checkErrors() {
    if (shouldThrowAccessDenied) {
      throw const AccessDeniedFailure("Access is restricted");
    }
    if (shouldThrowNetworkError) {
      throw const NetworkFailure("Network Error");
    }
  }

  @override
  Future<List<OrderInvestor>> fetchAssignedInvestors(
      String advisorProfileId) async {
    _checkErrors();
    return const [
      OrderInvestor(
          id: 'investor-1',
          fullName: 'John Doe',
          email: 'john@example.com',
          workspaceId: 'workspace-1'),
      OrderInvestor(
          id: 'investor-2',
          fullName: 'Jane Smith',
          email: 'jane@example.com',
          workspaceId: 'workspace-2'),
    ];
  }

  @override
  Future<List<OrderFolio>> fetchFolios(
      String investorProfileId, String workspaceId) async {
    _checkErrors();
    return const [
      OrderFolio(
        normalizedFolioNumber: '12345678',
        sourceFolioMasked: '••••5678',
        registrar: 'CAMS',
        portfolioId: 'portfolio-1',
      ),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMutualFunds() async {
    _checkErrors();
    return [
      {'scheme_code': 'SCH-1', 'scheme_name': 'HDFC Top 100'},
      {'scheme_code': 'SCH-2', 'scheme_name': 'SBI Bluechip'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> searchMutualFunds(String query) async {
    _checkErrors();
    return [
      {'scheme_code': 'SCH-1', 'scheme_name': 'HDFC Top 100'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchHoldings(
      String investorProfileId, String workspaceId) async {
    _checkErrors();
    return [
      {'scheme_code': 'SCH-1', 'scheme_name': 'HDFC Top 100', 'units': 100.0},
    ];
  }

  @override
  Future<OrderContext> resolveInvestorContext({
    required String investorProfileId,
    required String initiatorProfileId,
    required String initiationRole,
    required String initiationChannel,
  }) async {
    _checkErrors();
    return OrderContext(
      workspaceId: investorProfileId == 'investor-2' ? 'workspace-2' : 'workspace-1',
      investorProfileId: investorProfileId,
      investorFullName: 'John Doe',
      initiatorProfileId: initiatorProfileId,
      initiationRole: initiationRole,
      initiationChannel: initiationChannel,
    );
  }

  @override
  Future<String> submitOrder(OrderDraft draft) async {
    _checkErrors();
    submitCallCount++;
    if (draft.type == OrderType.sell || draft.type == OrderType.switchOrder) {
      throw const ConfigurationFailure(
          "Database schema error: Sell and Switch orders cannot be persisted");
    }
    return 'mock-order-id';
  }
}
