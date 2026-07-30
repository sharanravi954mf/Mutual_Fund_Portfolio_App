import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/orders/data/order_repository.dart';
import 'package:mutual_fund_portfolio_app/features/orders/domain/masking.dart';
import 'package:mutual_fund_portfolio_app/features/orders/domain/order_models.dart';
import 'package:mutual_fund_portfolio_app/features/orders/presentation/order_bloc.dart';

void main() {
  group('MaskingUtil Tests', () {
    test('masks PAN correctly', () {
      expect(MaskingUtil.maskPan('ABC123456F'), 'ABC••••56F');
      expect(MaskingUtil.maskPan('ABC'), 'ABC'); // too short
    });

    test('masks Phone correctly', () {
      expect(MaskingUtil.maskPhone('9876543210'), '••••••3210');
      expect(MaskingUtil.maskPhone('123'), '123'); // too short
    });

    test('masks Email correctly', () {
      expect(MaskingUtil.maskEmail('ravi@example.com'), 'ra•••@example.com');
      expect(MaskingUtil.maskEmail('r@ex.com'), 'r•••@ex.com');
      expect(MaskingUtil.maskEmail('invalid-email'), 'invalid-email');
    });

    test('masks Folio correctly', () {
      expect(MaskingUtil.maskFolio('12345678'), '••••5678');
      expect(MaskingUtil.maskFolio('12'), '12'); // too short
    });
  });

  group('OrderDraft Validation Tests', () {
    test('validates correct Buy order', () {
      const draft = OrderDraft(
        workspaceId: 'workspace-1',
        investorProfileId: 'investor-1',
        schemeCode: 'SCH-1',
        type: OrderType.buy,
        amount: 5000,
      );
      expect(draft.validate(), isNull);
    });

    test('validates Sell order missing folio', () {
      const draft = OrderDraft(
        workspaceId: 'workspace-1',
        investorProfileId: 'investor-1',
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
        workspaceId: 'workspace-1',
        investorProfileId: 'investor-1',
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
        workspaceId: 'workspace-1',
        investorProfileId: 'investor-1',
        schemeCode: 'SCH-1',
        type: OrderType.buy,
        amount: -100,
      );
      final errors = draft.validate();
      expect(
          errors, contains('A positive finite amount or units is required.'));
    });
  });

  group('OrderBloc Tests', () {
    late FakeOrderRepository repository;
    late OrderBloc bloc;

    setUp(() {
      repository = FakeOrderRepository();
      bloc = OrderBloc(
        repository,
        workspaceId: 'workspace-1',
        investorProfileId: 'investor-1',
      );
    });

    tearDown(() {
      bloc.dispose();
    });

    test('initial state matches expected properties', () {
      expect(bloc.state.phase, 'initial');
      expect(bloc.state.draft.workspaceId, 'workspace-1');
      expect(bloc.state.draft.investorProfileId, 'investor-1');
      expect(bloc.state.draft.type, OrderType.buy);
    });

    test('loadReferenceData populates states correctly', () async {
      await bloc.loadReferenceData('advisor-1', isAdvisor: true);

      expect(bloc.state.phase, 'ready');
      expect(bloc.state.funds, isNotEmpty);
      expect(bloc.state.folios, isNotEmpty);
      expect(bloc.state.assignedInvestors, isNotEmpty);
    });

    test('updateOrderType clears incompatible fields', () {
      bloc.updateScheme('SCH-1');
      bloc.updateFolio('FOLIO-1');
      bloc.updateDestScheme('SCH-2');
      bloc.updateAmount(5000);

      bloc.updateOrderType(OrderType.buy);

      expect(bloc.state.draft.type, OrderType.buy);
      expect(bloc.state.draft.amount, isNull);
      expect(bloc.state.draft.folioNumber, isNull);
      expect(bloc.state.draft.destSchemeCode, isNull);
    });

    test('submitOrder succeeds and returns order id', () async {
      bloc.updateScheme('SCH-1');
      bloc.updateAmount(5000);

      await bloc.submitOrder(
        initiatedByProfileId: 'investor-1',
        initiatedByRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      expect(bloc.state.phase, 'submitted');
      expect(bloc.state.submittedOrderId, 'mock-order-id');
      expect(bloc.state.errorMessage, isNull);
    });

    test('submitOrder fails validation', () async {
      bloc.updateScheme(''); // empty

      await bloc.submitOrder(
        initiatedByProfileId: 'investor-1',
        initiatedByRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      expect(bloc.state.phase, 'failure');
      expect(bloc.state.errorMessage, contains('Scheme is required.'));
    });
  });
}

class FakeOrderRepository implements OrderRepository {
  @override
  Future<List<OrderInvestor>> fetchAssignedInvestors(
      String advisorProfileId) async {
    return const [
      OrderInvestor(
          id: 'investor-1', fullName: 'John Doe', email: 'john@example.com'),
      OrderInvestor(
          id: 'investor-2', fullName: 'Jane Smith', email: 'jane@example.com'),
    ];
  }

  @override
  Future<List<OrderFolio>> fetchFolios(String investorProfileId) async {
    return const [
      OrderFolio(
          normalizedFolioNumber: '12345678',
          sourceFolioMasked: '••••5678',
          registrar: 'CAMS'),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMutualFunds() async {
    return [
      {'scheme_code': 'SCH-1', 'scheme_name': 'HDFC Top 100'},
      {'scheme_code': 'SCH-2', 'scheme_name': 'SBI Bluechip'},
    ];
  }

  @override
  Future<String> submitOrder(
    OrderDraft draft, {
    required String initiatedByProfileId,
    required String initiatedByRole,
    required String initiationChannel,
  }) async {
    if (draft.schemeCode == 'FAIL-SCHEME') {
      throw Exception('DB Error: duplicate key constraint');
    }
    return 'mock-order-id';
  }
}
