import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mutual_fund_portfolio_app/features/orders/data/order_repository.dart';
import 'package:mutual_fund_portfolio_app/features/orders/data/supabase_order_repository.dart';
import 'package:mutual_fund_portfolio_app/features/orders/domain/masking.dart';
import 'package:mutual_fund_portfolio_app/features/orders/domain/order_models.dart';
import 'package:mutual_fund_portfolio_app/features/orders/presentation/order_bloc.dart';
import 'package:mutual_fund_portfolio_app/features/orders/presentation/order_state.dart';

void main() {
  // ---------------------------------------------------------------------------
  // MaskingUtil Tests — strict fail-closed validation
  // ---------------------------------------------------------------------------
  group('MaskingUtil Tests', () {
    group('maskPan', () {
      test('masks valid PAN (5 alpha + 4 digits + 1 alpha, uppercase)', () {
        expect(MaskingUtil.maskPan('ABCDE1234F'), 'ABC••••34F');
      });

      test(
          'returns fully masked for PAN with wrong structure (only 3 leading alpha)',
          () {
        // 'ABC123456F' has 3 leading letters, not 5 → malformed
        expect(MaskingUtil.maskPan('ABC123456F'), '••••••••••');
      });

      test('returns fully masked for PAN with lowercase', () {
        // lowercase letters should fail even if length=10
        expect(MaskingUtil.maskPan('abcde1234f'), '••••••••••');
      });

      test('returns fully masked for PAN shorter than 10', () {
        expect(MaskingUtil.maskPan('ABC'), '••••••••••');
      });

      test('returns fully masked for empty PAN', () {
        expect(MaskingUtil.maskPan(''), '••••••••••');
      });

      test('returns fully masked for PAN with special characters', () {
        expect(MaskingUtil.maskPan('ABCDE@234F'), '••••••••••');
      });
    });

    group('maskPhone', () {
      test('masks valid 10-digit phone showing last 4', () {
        expect(MaskingUtil.maskPhone('9876543210'), '••••••3210');
      });

      test('masks phone with dash formatting correctly (dash stripped)', () {
        // '98765-43210' stripped of '-' = '9876543210' (10 digits) → valid
        expect(MaskingUtil.maskPhone('98765-43210'), '••••••3210');
      });

      test('returns fully masked for phone with fewer than 10 digits', () {
        expect(MaskingUtil.maskPhone('123'), '••••••••••');
      });

      test('returns fully masked for phone with letters', () {
        expect(MaskingUtil.maskPhone('98765ABCDE'), '••••••••••');
      });

      test('returns fully masked for empty phone', () {
        expect(MaskingUtil.maskPhone(''), '••••••••••');
      });

      test('returns fully masked for phone with too many digits', () {
        // 11-digit number should fail
        expect(MaskingUtil.maskPhone('98765432101'), '••••••••••');
      });
    });

    group('maskEmail', () {
      test('masks valid email showing first 2 chars of local part', () {
        expect(MaskingUtil.maskEmail('ravi@example.com'), 'ra•••@example.com');
      });

      test('masks short local part email (2 chars)', () {
        expect(MaskingUtil.maskEmail('ra@example.com'), 'ra•••@example.com');
      });

      test('masks single-char local part email', () {
        expect(MaskingUtil.maskEmail('r@ex.com'), 'r•••@ex.com');
      });

      test('returns fully masked placeholder for email without @', () {
        expect(MaskingUtil.maskEmail('invalid-email'), '•••••@•••••.com');
      });

      test('returns fully masked placeholder for malformed email (double @)',
          () {
        expect(MaskingUtil.maskEmail('a@@example.com'), '•••••@•••••.com');
      });

      test('returns fully masked placeholder for empty email', () {
        expect(MaskingUtil.maskEmail(''), '•••••@•••••.com');
      });

      test('returns fully masked placeholder for domain without dot', () {
        expect(MaskingUtil.maskEmail('user@nodot'), '•••••@•••••.com');
      });
    });

    group('maskFolio', () {
      test('masks valid folio showing last 4 chars', () {
        expect(MaskingUtil.maskFolio('12345678'), '••••5678');
      });

      test('returns fully masked for folio shorter than 6 chars', () {
        expect(MaskingUtil.maskFolio('12'), '••••••••');
      });

      test('returns fully masked for empty folio', () {
        expect(MaskingUtil.maskFolio(''), '••••••••');
      });

      test('returns fully masked for folio with special characters', () {
        // forward slash is not alphanumeric
        expect(MaskingUtil.maskFolio('1234/56'), '••••••••');
      });

      test('masks alphanumeric folio correctly', () {
        expect(MaskingUtil.maskFolio('FOLIO12345'), '••••2345');
      });
    });
  });

  // ---------------------------------------------------------------------------
  // OrderDraft Validation Tests
  // ---------------------------------------------------------------------------
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
        folioReferenceId: 'folio-reference-1',
        amount: 1000,
        destinationSchemeCode: 'SCH-1',
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
      expect(errors, contains('Amount must be positive and finite.'));
    });

    test('rejects both amount and units', () {
      const draft = OrderDraft(
        context: mockContext,
        schemeCode: 'SCH-1',
        type: OrderType.buy,
        amount: 100,
        units: 10,
      );
      expect(draft.validate(),
          contains('Enter either amount or units, not both.'));
    });

    test('rejects missing amount and units', () {
      const draft = OrderDraft(
        context: mockContext,
        schemeCode: 'SCH-1',
        type: OrderType.buy,
      );
      expect(
        draft.validate(),
        contains('Enter a positive finite amount or units.'),
      );
    });

    test('rejects NaN and infinity values', () {
      const nanDraft = OrderDraft(
        context: mockContext,
        schemeCode: 'SCH-1',
        type: OrderType.buy,
        amount: double.nan,
      );
      const infinityDraft = OrderDraft(
        context: mockContext,
        schemeCode: 'SCH-1',
        type: OrderType.buy,
        units: double.infinity,
      );

      expect(
          nanDraft.validate(), contains('Amount must be positive and finite.'));
      expect(
        infinityDraft.validate(),
        contains('Units must be positive and finite.'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // OrderState copyWith Tests
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // OrderBloc Tests
  // ---------------------------------------------------------------------------
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

    test('advisor initiator context is preserved after investor selection',
        () async {
      // Step 1: Advisor initiates without a preselected investor
      await bloc.initiateForAdvisor(
        advisorProfileId: 'advisor-1',
        initiatorProfileId: 'advisor-1',
        initiationRole: 'advisor',
        initiationChannel: 'advisor_portal',
      );

      expect(bloc.state.draft.context, isNull);

      // Step 2: Advisor selects investor-2 in workspace-2
      await bloc.updateBeneficiary('investor-2', 'workspace-2');

      final ctx = bloc.state.draft.context;
      expect(ctx, isNotNull);
      // Initiator identity must be preserved from bloc-level fields, not cleared context
      expect(ctx!.initiatorProfileId, 'advisor-1',
          reason:
              'initiatorProfileId must remain the advisor after client selection');
      expect(ctx.initiationRole, 'advisor',
          reason: 'initiationRole must remain advisor');
      expect(ctx.initiationChannel, 'advisor_portal',
          reason: 'initiationChannel must remain advisor_portal');
      // Beneficiary must be the selected investor
      expect(ctx.workspaceId, 'workspace-2',
          reason:
              'workspace must be the one carried by the selected relationship');
      expect(ctx.investorProfileId, 'investor-2',
          reason: 'investor must be the selected investor');
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
      expect(bloc.state.draft.folioReferenceId, isNull);
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

    test('submitOrder succeeds for Sell order with folio reference', () async {
      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      await bloc.updateOrderType(OrderType.sell);
      await bloc.updateFolio('folio-a');
      bloc.updateScheme('SCH-A');
      bloc.updateAmount(5000);

      await bloc.submitOrder();

      expect(bloc.state.phase, OrderPhase.submitted);
      expect(repository.lastSubmittedDraft?.folioReferenceId, 'folio-a');
      expect(repository.lastSubmittedDraft?.type, OrderType.sell);
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

    test('relationship rules validation matches MFD authorization model', () {
      final repo = FakeOrderRepository();
      final results = repo.simulateFetchAssignedInvestors('adv-1');

      // 1. Active advisor membership verified (ws-1)
      final ws1Relationships = results.where((r) => r.workspaceId == 'ws-1');
      expect(ws1Relationships, isNotEmpty,
          reason:
              'Active advisor membership in ws-1 must produce relationships');

      // 2. Authorised workspace-owner/admin membership verified (ws-2)
      final ws2Relationships = results.where((r) => r.workspaceId == 'ws-2');
      expect(ws2Relationships, isNotEmpty,
          reason: 'Admin membership in ws-2 must produce relationships');

      // 3. Same investor in two workspaces remains two selectable relationships
      final inv1Relationships =
          results.where((r) => r.investorProfileId == 'inv-1');
      expect(inv1Relationships.length, 2,
          reason: 'inv-1 in ws-1 and ws-2 must remain two separate options');
      expect(inv1Relationships.any((r) => r.workspaceId == 'ws-1'), true);
      expect(inv1Relationships.any((r) => r.workspaceId == 'ws-2'), true);

      // 4. Inactive relationship excluded
      final hasInactive = results.any((r) => r.investorProfileId == 'inv-2');
      expect(hasInactive, false,
          reason: 'Inactive membership must be excluded');

      // 5. Ended relationship excluded
      final hasEnded = results.any((r) => r.investorProfileId == 'inv-3');
      expect(hasEnded, false,
          reason: 'Ended membership (ended_at != null) must be excluded');

      // 6. Unrelated investor excluded (in workspace where advisor has no membership)
      final hasUnrelated = results.any((r) => r.investorProfileId == 'inv-4');
      expect(hasUnrelated, false,
          reason: 'Investor in unrelated workspace must be excluded');

      // 7. No implicit cross-workspace selection: every result has an explicit workspaceId
      for (final r in results) {
        expect(r.workspaceId.isNotEmpty, true,
            reason: 'Every relationship must carry an explicit workspaceId');
      }
    });

    test(
        'source holdings scoped strictly to the selected folio and cleared on change',
        () async {
      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      await bloc.updateOrderType(OrderType.sell);

      // Select Folio A — only SCH-A should appear, never SCH-B
      await bloc.updateFolio('folio-a');
      expect(bloc.state.holdings.any((h) => h['scheme_code'] == 'SCH-A'), true,
          reason: 'SCH-A must appear in Folio A');
      expect(bloc.state.holdings.any((h) => h['scheme_code'] == 'SCH-B'), false,
          reason: 'SCH-B must not appear when Folio A is selected');

      bloc.updateScheme('SCH-A');
      expect(bloc.state.draft.schemeCode, 'SCH-A');

      // Select Folio B — SCH-B appears, SCH-A must be cleared
      await bloc.updateFolio('folio-b');
      expect(bloc.state.holdings.any((h) => h['scheme_code'] == 'SCH-B'), true,
          reason: 'SCH-B must appear in Folio B');
      expect(bloc.state.holdings.any((h) => h['scheme_code'] == 'SCH-A'), false,
          reason: 'SCH-A must not appear when Folio B is selected');
      expect(bloc.state.draft.schemeCode, isEmpty,
          reason:
              'Source scheme from Folio A must be cleared after moving to Folio B');
    });

    test('Sell order submits canonical source folio intent', () async {
      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      await bloc.updateOrderType(OrderType.sell);
      // Use folio-a and SCH-A so validation passes; repository block is what causes failure
      await bloc.updateFolio('folio-a');
      bloc.updateScheme('SCH-A');
      bloc.updateAmount(5000);

      await bloc.submitOrder();

      expect(bloc.state.phase, OrderPhase.submitted);
      expect(repository.submitCallCount, 1);
      expect(repository.lastSubmittedDraft?.folioReferenceId, 'folio-a');
      expect(repository.lastSubmittedDraft?.destinationSchemeCode, isNull);
    });

    test('Switch order submits canonical source folio and destination intent',
        () async {
      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      await bloc.updateOrderType(OrderType.switchOrder);
      // Use folio-a and SCH-A (source) → SCH-B (dest) so validation passes
      await bloc.updateFolio('folio-a');
      bloc.updateScheme('SCH-A');
      bloc.updateDestinationScheme('SCH-B');
      bloc.updateAmount(5000);

      await bloc.submitOrder();

      expect(bloc.state.phase, OrderPhase.submitted);
      expect(repository.submitCallCount, 1);
      expect(repository.lastSubmittedDraft?.folioReferenceId, 'folio-a');
      expect(repository.lastSubmittedDraft?.destinationSchemeCode, 'SCH-B');
    });

    test('initial loading calls the bounded method fetchInitialMutualFunds',
        () async {
      repository.fetchInitialCalled = false;
      await bloc.initiateForInvestor(
        investorProfileId: 'investor-1',
        initiatorProfileId: 'investor-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );
      expect(repository.fetchInitialCalled, isTrue);
    });

    test(
        'stale beneficiary success cannot overwrite the latest beneficiary folios',
        () async {
      final raceRepository = BeneficiaryRaceOrderRepository();
      final raceBloc = OrderBloc(raceRepository);
      addTearDown(raceBloc.dispose);

      await raceBloc.initiateForAdvisor(
        advisorProfileId: 'advisor-1',
        initiatorProfileId: 'advisor-1',
        initiationRole: 'advisor',
        initiationChannel: 'advisor_portal',
      );

      final staleA = raceBloc.updateBeneficiary('investor-a', 'workspace-a');
      raceRepository.completeContext(
        investorProfileId: 'investor-a',
        workspaceId: 'workspace-a',
        investorFullName: 'Investor A',
      );
      await Future<void>.delayed(Duration.zero);

      final freshB = raceBloc.updateBeneficiary('investor-b', 'workspace-b');
      raceRepository.completeContext(
        investorProfileId: 'investor-b',
        workspaceId: 'workspace-b',
        investorFullName: 'Investor B',
      );
      await Future<void>.delayed(Duration.zero);
      raceRepository.completeFolios(
        investorProfileId: 'investor-b',
        folios: const [
          OrderFolio(
            folioReferenceId: 'folio-b',
            portfolioId: 'portfolio-b',
            maskedFolioDisplay: '••••0002',
            registrar: 'KFINTECH',
          ),
        ],
      );
      await freshB;

      raceRepository.completeFolios(
        investorProfileId: 'investor-a',
        folios: const [
          OrderFolio(
            folioReferenceId: 'folio-a',
            portfolioId: 'portfolio-a',
            maskedFolioDisplay: '••••0001',
            registrar: 'CAMS',
          ),
        ],
      );
      await staleA;

      expect(raceBloc.state.phase, OrderPhase.ready);
      expect(raceBloc.state.draft.context?.investorProfileId, 'investor-b');
      expect(raceBloc.state.draft.context?.workspaceId, 'workspace-b');
      expect(raceBloc.state.folios.single.folioReferenceId, 'folio-b');
    });

    test('stale beneficiary failure after a fresh success leaves state intact',
        () async {
      final raceRepository = BeneficiaryRaceOrderRepository();
      final raceBloc = OrderBloc(raceRepository);
      addTearDown(raceBloc.dispose);

      await raceBloc.initiateForAdvisor(
        advisorProfileId: 'advisor-1',
        initiatorProfileId: 'advisor-1',
        initiationRole: 'advisor',
        initiationChannel: 'advisor_portal',
      );

      final staleA = raceBloc.updateBeneficiary('investor-a', 'workspace-a');
      final freshB = raceBloc.updateBeneficiary('investor-b', 'workspace-b');

      raceRepository.completeContext(
        investorProfileId: 'investor-b',
        workspaceId: 'workspace-b',
        investorFullName: 'Investor B',
      );
      await Future<void>.delayed(Duration.zero);
      raceRepository.completeFolios(
        investorProfileId: 'investor-b',
        folios: const [
          OrderFolio(
            folioReferenceId: 'folio-b',
            portfolioId: 'portfolio-b',
            maskedFolioDisplay: '••••0002',
            registrar: 'KFINTECH',
          ),
        ],
      );
      await freshB;

      raceRepository.failContext(
        investorProfileId: 'investor-a',
        failure: const NetworkFailure('Stale beneficiary failed'),
      );
      await staleA;

      expect(raceBloc.state.phase, OrderPhase.ready);
      expect(raceBloc.state.errorMessage, isNull);
      expect(raceBloc.state.draft.context?.investorProfileId, 'investor-b');
      expect(raceBloc.state.folios.single.folioReferenceId, 'folio-b');
    });
  });
  _registerSanitisationTests();
}

/// ---------------------------------------------------------------------------
/// FakeOrderRepository — deterministic test double with folio-scoped holdings
/// ---------------------------------------------------------------------------
class FakeOrderRepository implements OrderRepository {
  int submitCallCount = 0;
  bool shouldThrowAccessDenied = false;
  bool shouldThrowNetworkError = false;
  OrderDraft? lastSubmittedDraft;

  void _checkErrors() {
    if (shouldThrowAccessDenied) {
      throw const AccessDeniedFailure('Access is restricted');
    }
    if (shouldThrowNetworkError) {
      throw const NetworkFailure('Network Error');
    }
  }

  @override
  Future<List<OrderInvestor>> fetchAssignedInvestors(
      String advisorProfileId) async {
    _checkErrors();
    return const [
      OrderInvestor(
          investorProfileId: 'investor-1',
          investorFullName: 'John Doe',
          email: 'john@example.com',
          workspaceId: 'workspace-1'),
      OrderInvestor(
          investorProfileId: 'investor-2',
          investorFullName: 'Jane Smith',
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
        folioReferenceId: 'folio-a',
        portfolioId: 'portfolio-1',
        maskedFolioDisplay: '••••5678',
        registrar: 'CAMS',
      ),
      OrderFolio(
        folioReferenceId: 'folio-b',
        portfolioId: 'portfolio-2',
        maskedFolioDisplay: '••••9012',
        registrar: 'KFINTECH',
      ),
    ];
  }

  bool fetchInitialCalled = false;

  @override
  Future<List<Map<String, dynamic>>> fetchMutualFunds() async {
    _checkErrors();
    return [
      {'scheme_code': 'SCH-1', 'scheme_name': 'HDFC Top 100'},
      {'scheme_code': 'SCH-2', 'scheme_name': 'SBI Bluechip'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchInitialMutualFunds(
      {int limit = 20}) async {
    _checkErrors();
    fetchInitialCalled = true;
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

  /// Folio-scoped holdings:
  ///   - folio-a → SCH-A only
  ///   - folio-b → SCH-B only
  /// This deterministically proves that Folio A never shows Scheme B and
  /// vice-versa.
  @override
  Future<List<Map<String, dynamic>>> fetchHoldings(String investorProfileId,
      String workspaceId, String folioReferenceId) async {
    _checkErrors();
    if (folioReferenceId == 'folio-a') {
      return [
        {
          'scheme_code': 'SCH-A',
          'scheme_name': 'Scheme Alpha Fund',
          'units': 100.0
        },
      ];
    } else if (folioReferenceId == 'folio-b') {
      return [
        {
          'scheme_code': 'SCH-B',
          'scheme_name': 'Scheme Beta Fund',
          'units': 50.0
        },
      ];
    }
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
    String? selectedWorkspaceId,
  }) async {
    _checkErrors();
    return OrderContext(
      workspaceId: selectedWorkspaceId ??
          (investorProfileId == 'investor-2' ? 'workspace-2' : 'workspace-1'),
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
    lastSubmittedDraft = draft;
    return 'mock-order-id';
  }

  // -------------------------------------------------------------------------
  // Simulated database tables for membership verification testing
  // -------------------------------------------------------------------------
  // This in-memory table represents the canonical workspace_memberships schema
  // with the relevant columns for advisor relationship determination.
  static const List<Map<String, dynamic>> mockWorkspaceMemberships = [
    // Active advisor membership in ws-1
    {
      'id': 'm1',
      'workspace_id': 'ws-1',
      'profile_id': 'adv-1',
      'role': 'advisor',
      'status': 'active',
      'ended_at': null,
    },
    // Active admin (workspace-owner) membership in ws-2
    {
      'id': 'm2',
      'workspace_id': 'ws-2',
      'profile_id': 'adv-1',
      'role': 'admin',
      'status': 'active',
      'ended_at': null,
    },
    // Same investor (inv-1) active in both ws-1 and ws-2 (two separate tuples)
    {
      'id': 'm3',
      'workspace_id': 'ws-1',
      'profile_id': 'inv-1',
      'role': 'investor',
      'status': 'active',
      'ended_at': null,
    },
    {
      'id': 'm4',
      'workspace_id': 'ws-2',
      'profile_id': 'inv-1',
      'role': 'investor',
      'status': 'active',
      'ended_at': null,
    },
    // Inactive investor membership — must be excluded
    {
      'id': 'm5',
      'workspace_id': 'ws-1',
      'profile_id': 'inv-2',
      'role': 'investor',
      'status': 'inactive',
      'ended_at': null,
    },
    // Ended investor membership (ended_at != null) — must be excluded
    {
      'id': 'm6',
      'workspace_id': 'ws-1',
      'profile_id': 'inv-3',
      'role': 'investor',
      'status': 'active',
      'ended_at': '2026-07-29T10:00:00Z',
    },
    // Unrelated investor in ws-3 (advisor has no ws-3 membership) — must be excluded
    {
      'id': 'm7',
      'workspace_id': 'ws-3',
      'profile_id': 'inv-4',
      'role': 'investor',
      'status': 'active',
      'ended_at': null,
    },
  ];

  /// Simulate the database logic of fetchAssignedInvestors in memory.
  ///
  /// Step 1: Find workspaces where the advisor has an active membership
  ///         (role = advisor or admin, status = active, ended_at = null).
  /// Step 2: In those workspaces, find active investor memberships
  ///         (role = investor, status = active, ended_at = null).
  /// Step 3: Map each (workspace_id, investor_profile_id) tuple to an
  ///         OrderInvestor — preserving duplicates across workspaces.
  List<OrderInvestor> simulateFetchAssignedInvestors(String advisorProfileId) {
    final advisorWorkspaces = mockWorkspaceMemberships
        .where((m) =>
            m['profile_id'] == advisorProfileId &&
            ['advisor', 'admin'].contains(m['role']) &&
            m['status'] == 'active' &&
            m['ended_at'] == null)
        .map((m) => m['workspace_id'] as String)
        .toList();

    final investorMemberships = mockWorkspaceMemberships
        .where((m) =>
            advisorWorkspaces.contains(m['workspace_id']) &&
            m['role'] == 'investor' &&
            m['status'] == 'active' &&
            m['ended_at'] == null)
        .toList();

    return investorMemberships.map((m) {
      return OrderInvestor(
        investorProfileId: m['profile_id'] as String,
        workspaceId: m['workspace_id'] as String,
        investorFullName: 'Investor ${m['profile_id']}',
        email: 'investor@example.com',
      );
    }).toList();
  }
}

class BeneficiaryRaceOrderRepository extends FakeOrderRepository {
  final _contextCompleters = <String, Completer<OrderContext>>{};
  final _folioCompleters = <String, Completer<List<OrderFolio>>>{};

  @override
  Future<OrderContext> resolveInvestorContext({
    required String investorProfileId,
    required String initiatorProfileId,
    required String initiationRole,
    required String initiationChannel,
    String? selectedWorkspaceId,
  }) {
    final completer = Completer<OrderContext>();
    _contextCompleters[investorProfileId] = completer;
    return completer.future;
  }

  @override
  Future<List<OrderFolio>> fetchFolios(
      String investorProfileId, String workspaceId) {
    final completer = Completer<List<OrderFolio>>();
    _folioCompleters[investorProfileId] = completer;
    return completer.future;
  }

  void completeContext({
    required String investorProfileId,
    required String workspaceId,
    required String investorFullName,
  }) {
    _contextCompleters[investorProfileId]!.complete(OrderContext(
      workspaceId: workspaceId,
      investorProfileId: investorProfileId,
      investorFullName: investorFullName,
      initiatorProfileId: 'advisor-1',
      initiationRole: 'advisor',
      initiationChannel: 'advisor_portal',
    ));
  }

  void failContext({
    required String investorProfileId,
    required OrderFailure failure,
  }) {
    _contextCompleters[investorProfileId]!.completeError(failure);
  }

  void completeFolios({
    required String investorProfileId,
    required List<OrderFolio> folios,
  }) {
    _folioCompleters[investorProfileId]!.complete(folios);
  }
}

// -----------------------------------------------------------------------------
// New Focused Tests for workspace resolution, authorization and sanitisation
// -----------------------------------------------------------------------------
void _registerSanitisationTests() {
  group('SupabaseOrderRepository and Context Resolution / Sanitisation Tests',
      () {
    test('workspace mismatch and multi-workspace investors', () async {
      // Investor has active memberships in workspace-1 and workspace-2
      // and has portfolios in both workspaces.
      final client = FakeSupabaseClient(queryResponses: {
        'profiles': [
          {'id': 'inv-1', 'full_name': 'John Doe', 'email': 'john@example.com'}
        ],
        'workspace_memberships': [
          {
            'workspace_id': 'workspace-1',
            'profile_id': 'inv-1',
            'role': 'investor',
            'status': 'active',
            'ended_at': null,
          },
          {
            'workspace_id': 'workspace-2',
            'profile_id': 'inv-1',
            'role': 'investor',
            'status': 'active',
            'ended_at': null,
          }
        ],
        'portfolios': [
          {'workspace_id': 'workspace-1', 'client_id': 'inv-1'},
          {'workspace_id': 'workspace-2', 'client_id': 'inv-1'}
        ],
      });

      final repo = SupabaseOrderRepository(client);

      // 1. Success on workspace-1
      final ctx1 = await repo.resolveInvestorContext(
        investorProfileId: 'inv-1',
        initiatorProfileId: 'inv-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
        selectedWorkspaceId: 'workspace-1',
      );
      expect(ctx1.workspaceId, 'workspace-1');

      // 2. Success on workspace-2
      final ctx2 = await repo.resolveInvestorContext(
        investorProfileId: 'inv-1',
        initiatorProfileId: 'inv-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
        selectedWorkspaceId: 'workspace-2',
      );
      expect(ctx2.workspaceId, 'workspace-2');

      // 3. Fails on workspace-3 (no membership/portfolio)
      expect(
        () => repo.resolveInvestorContext(
          investorProfileId: 'inv-1',
          initiatorProfileId: 'inv-1',
          initiationRole: 'investor',
          initiationChannel: 'investor_portal',
          selectedWorkspaceId: 'workspace-3',
        ),
        throwsA(isA<AccessDeniedFailure>()),
      );

      // 4. Mismatch workspace case: portfolio in workspace-2 but resolution is requested for workspace-1 where no portfolio matches
      final mismatchedClient = FakeSupabaseClient(queryResponses: {
        'profiles': [
          {'id': 'inv-1', 'full_name': 'John Doe'}
        ],
        'workspace_memberships': [
          {
            'workspace_id': 'workspace-1',
            'profile_id': 'inv-1',
            'role': 'investor',
            'status': 'active',
            'ended_at': null,
          }
        ],
        'portfolios': [
          {'workspace_id': 'workspace-2', 'client_id': 'inv-1'}
        ],
      });
      final mismatchedRepo = SupabaseOrderRepository(mismatchedClient);
      expect(
        () => mismatchedRepo.resolveInvestorContext(
          investorProfileId: 'inv-1',
          initiatorProfileId: 'inv-1',
          initiationRole: 'investor',
          initiationChannel: 'investor_portal',
          selectedWorkspaceId: 'workspace-1',
        ),
        throwsA(isA<AccessDeniedFailure>().having(
          (e) => e.message,
          'message',
          contains('no portfolio in the selected workspace'),
        )),
      );
    });

    test('active advisor success', () async {
      final client = FakeSupabaseClient(queryResponses: {
        'profiles': [
          {'id': 'inv-1', 'full_name': 'John Doe'}
        ],
        'workspace_memberships': [
          {
            'workspace_id': 'workspace-1',
            'profile_id': 'inv-1',
            'role': 'investor',
            'status': 'active',
            'ended_at': null,
          },
          {
            'workspace_id': 'workspace-1',
            'profile_id': 'adv-1',
            'role': 'advisor',
            'status': 'active',
            'ended_at': null,
          }
        ],
        'portfolios': [
          {'workspace_id': 'workspace-1', 'client_id': 'inv-1'}
        ],
      });

      final repo = SupabaseOrderRepository(client);
      final ctx = await repo.resolveInvestorContext(
        investorProfileId: 'inv-1',
        initiatorProfileId: 'adv-1',
        initiationRole: 'advisor',
        initiationChannel: 'advisor_portal',
        selectedWorkspaceId: 'workspace-1',
      );

      expect(ctx.workspaceId, 'workspace-1');
      expect(ctx.initiatorProfileId, 'adv-1');
    });

    test('owner-admin success', () async {
      final client = FakeSupabaseClient(queryResponses: {
        'profiles': [
          {'id': 'inv-1', 'full_name': 'John Doe'}
        ],
        'workspace_memberships': [
          {
            'workspace_id': 'workspace-1',
            'profile_id': 'inv-1',
            'role': 'investor',
            'status': 'active',
            'ended_at': null,
          },
          {
            'workspace_id': 'workspace-1',
            'profile_id': 'admin-1',
            'role': 'admin',
            'status': 'active',
            'ended_at': null,
          }
        ],
        'workspaces': [
          {'id': 'workspace-1', 'owner_profile_id': 'admin-1'}
        ],
        'portfolios': [
          {'workspace_id': 'workspace-1', 'client_id': 'inv-1'}
        ],
      });

      final repo = SupabaseOrderRepository(client);
      final ctx = await repo.resolveInvestorContext(
        investorProfileId: 'inv-1',
        initiatorProfileId: 'admin-1',
        initiationRole: 'admin',
        initiationChannel: 'advisor_portal',
        selectedWorkspaceId: 'workspace-1',
      );

      expect(ctx.workspaceId, 'workspace-1');
      expect(ctx.initiatorProfileId, 'admin-1');
      expect(ctx.initiationRole, 'admin');
    });

    test('non-owner-admin rejection', () async {
      final client = FakeSupabaseClient(queryResponses: {
        'profiles': [
          {'id': 'inv-1', 'full_name': 'John Doe'}
        ],
        'workspace_memberships': [
          {
            'workspace_id': 'workspace-1',
            'profile_id': 'inv-1',
            'role': 'investor',
            'status': 'active',
            'ended_at': null,
          },
          {
            'workspace_id': 'workspace-1',
            'profile_id': 'admin-1',
            'role': 'admin',
            'status': 'active',
            'ended_at': null,
          }
        ],
        'workspaces': [
          {'id': 'workspace-1', 'owner_profile_id': 'admin-different'}
        ],
        'portfolios': [
          {'workspace_id': 'workspace-1', 'client_id': 'inv-1'}
        ],
      });

      final repo = SupabaseOrderRepository(client);

      expect(
        () => repo.resolveInvestorContext(
          investorProfileId: 'inv-1',
          initiatorProfileId: 'admin-1',
          initiationRole: 'admin',
          initiationChannel: 'advisor_portal',
          selectedWorkspaceId: 'workspace-1',
        ),
        throwsA(isA<AccessDeniedFailure>().having(
          (e) => e.message,
          'message',
          contains('Admin does not own the selected workspace'),
        )),
      );
    });

    test('inactive membership rejection', () async {
      final client = FakeSupabaseClient(queryResponses: {
        'profiles': [
          {'id': 'inv-1', 'full_name': 'John Doe'}
        ],
        'workspace_memberships': [
          {
            'workspace_id': 'workspace-1',
            'profile_id': 'inv-1',
            'role': 'investor',
            'status': 'inactive', // Inactive!
            'ended_at': null,
          }
        ],
        'portfolios': [
          {'workspace_id': 'workspace-1', 'client_id': 'inv-1'}
        ],
      });

      final repo = SupabaseOrderRepository(client);

      expect(
        () => repo.resolveInvestorContext(
          investorProfileId: 'inv-1',
          initiatorProfileId: 'inv-1',
          initiationRole: 'investor',
          initiationChannel: 'investor_portal',
          selectedWorkspaceId: 'workspace-1',
        ),
        throwsA(isA<AccessDeniedFailure>().having(
          (e) => e.message,
          'message',
          contains('No active membership found for the investor'),
        )),
      );
    });

    test(
        'proves the exact selected workspace reaches resolveInvestorContext via OrderBloc',
        () async {
      final client = FakeSupabaseClient(queryResponses: {
        'profiles': [
          {'id': 'inv-1', 'full_name': 'John Doe'}
        ],
        'workspace_memberships': [
          {
            'workspace_id': 'workspace-selected',
            'profile_id': 'inv-1',
            'role': 'investor',
            'status': 'active',
            'ended_at': null,
          },
          {
            'workspace_id': 'workspace-selected',
            'profile_id': 'advisor-1',
            'role': 'advisor',
            'status': 'active',
            'ended_at': null,
          }
        ],
        'portfolios': [
          {
            'id': 'portfolio-1',
            'workspace_id': 'workspace-selected',
            'client_id': 'inv-1'
          }
        ],
        'mutual_funds': [
          {'scheme_code': 'SCH-1', 'scheme_name': 'HDFC Top 100'}
        ],
        'rpc:list_order_folios': [],
      });

      final repo = SupabaseOrderRepository(client);
      final bloc = OrderBloc(repo);

      await bloc.initiateForAdvisor(
        advisorProfileId: 'advisor-1',
        initiatorProfileId: 'advisor-1',
        initiationRole: 'advisor',
        initiationChannel: 'advisor_portal',
      );

      await bloc.updateBeneficiary('inv-1', 'workspace-selected');

      expect(bloc.state.phase, OrderPhase.ready);
      expect(bloc.state.draft.context?.workspaceId, 'workspace-selected');
    });

    test('database exception sanitisation hides raw DB/SQL schema details',
        () async {
      final client = FakeSupabaseClient(
        errorToThrow: const PostgrestException(
          message: 'column "non_existent_column" does not exist',
          code: '42703',
          details: 'position 15, select * from portfolios...',
        ),
      );

      final repo = SupabaseOrderRepository(client);

      try {
        await repo.resolveInvestorContext(
          investorProfileId: 'inv-1',
          initiatorProfileId: 'inv-1',
          initiationRole: 'investor',
          initiationChannel: 'investor_portal',
        );
        fail('Should have thrown ConfigurationFailure');
      } catch (e) {
        expect(e, isA<ConfigurationFailure>());
        final msg = e.toString();
        expect(msg, isNot(contains('column')));
        expect(msg, isNot(contains('portfolios')));
        expect(msg, isNot(contains('non_existent_column')));
        expect(msg, contains('Failed to resolve investor context'));
      }
    });

    test('database exception sanitisation through OrderBloc', () async {
      final client = FakeSupabaseClient(
        errorToThrow: const PostgrestException(
          message: 'column "non_existent_column" does not exist',
          code: '42703',
          details: 'select * from portfolios...',
        ),
      );
      final repo = SupabaseOrderRepository(client);
      final bloc = OrderBloc(repo);

      await bloc.initiateForInvestor(
        investorProfileId: 'inv-1',
        initiatorProfileId: 'inv-1',
        initiationRole: 'investor',
        initiationChannel: 'investor_portal',
      );

      expect(bloc.state.phase, OrderPhase.recoverableFailure);
      expect(bloc.state.errorMessage, isNotNull);
      expect(bloc.state.errorMessage, isNot(contains('column')));
      expect(bloc.state.errorMessage, isNot(contains('portfolios')));
      expect(bloc.state.errorMessage,
          contains('Failed to resolve investor context'));
    });

    test(
        'owner-admin submit persists initiated_by_role=advisor and initiation_channel=advisor_portal',
        () async {
      final client = FakeSupabaseClient(queryResponses: {
        'order_requests': [
          {'id': 'order-1'}
        ]
      });
      final repo = SupabaseOrderRepository(client);

      const draft = OrderDraft(
        context: OrderContext(
          workspaceId: 'workspace-1',
          investorProfileId: 'inv-1',
          investorFullName: 'John Doe',
          initiatorProfileId: 'admin-1',
          initiationRole: 'admin',
          initiationChannel: 'advisor_portal',
        ),
        schemeCode: 'SCH-1',
        type: OrderType.buy,
        amount: 5000,
      );

      final orderId = await repo.submitOrder(draft);
      expect(orderId, 'order-1');
      expect(client.lastInsertedPayload, isNotNull);
      expect(client.lastInsertedPayload!['initiated_by_role'], 'advisor');
      expect(
          client.lastInsertedPayload!['initiation_channel'], 'advisor_portal');
    });

    test('Buy payload omits folio and destination scheme columns', () async {
      final client = FakeSupabaseClient(queryResponses: {
        'order_requests': [
          {'id': 'order-buy'}
        ]
      });
      final repo = SupabaseOrderRepository(client);

      await repo.submitOrder(const OrderDraft(
        context: OrderContext(
          workspaceId: 'workspace-1',
          investorProfileId: 'inv-1',
          investorFullName: 'Investor One',
          initiatorProfileId: 'inv-1',
          initiationRole: 'investor',
          initiationChannel: 'investor_portal',
        ),
        schemeCode: 'SCH-BUY',
        type: OrderType.buy,
        amount: 5000,
      ));

      expect(client.lastInsertedPayload!['type'], 'buy');
      expect(client.lastInsertedPayload!['status'], 'pending_qualification');
      expect(
          client.lastInsertedPayload!.containsKey('folio_reference_id'), false);
      expect(
        client.lastInsertedPayload!.containsKey('destination_scheme_code'),
        false,
      );
    });

    test('Sell payload includes exact folio reference id', () async {
      final client = FakeSupabaseClient(queryResponses: {
        'order_requests': [
          {'id': 'order-sell'}
        ]
      });
      final repo = SupabaseOrderRepository(client);

      await repo.submitOrder(const OrderDraft(
        context: OrderContext(
          workspaceId: 'workspace-1',
          investorProfileId: 'inv-1',
          investorFullName: 'Investor One',
          initiatorProfileId: 'inv-1',
          initiationRole: 'investor',
          initiationChannel: 'investor_portal',
        ),
        schemeCode: 'SCH-SOURCE',
        type: OrderType.sell,
        folioReferenceId: '11111111-1111-1111-1111-111111111111',
        units: 25,
      ));

      expect(client.lastInsertedPayload!['type'], 'sell');
      expect(client.lastInsertedPayload!['folio_reference_id'],
          '11111111-1111-1111-1111-111111111111');
      expect(
        client.lastInsertedPayload!.containsKey('destination_scheme_code'),
        false,
      );
    });

    test('Switch payload includes exact folio and destination scheme',
        () async {
      final client = FakeSupabaseClient(queryResponses: {
        'order_requests': [
          {'id': 'order-switch'}
        ]
      });
      final repo = SupabaseOrderRepository(client);

      await repo.submitOrder(const OrderDraft(
        context: OrderContext(
          workspaceId: 'workspace-1',
          investorProfileId: 'inv-1',
          investorFullName: 'Investor One',
          initiatorProfileId: 'advisor-1',
          initiationRole: 'advisor',
          initiationChannel: 'advisor_portal',
        ),
        schemeCode: 'SCH-SOURCE',
        type: OrderType.switchOrder,
        folioReferenceId: '22222222-2222-2222-2222-222222222222',
        destinationSchemeCode: 'SCH-DEST',
        amount: 1000,
      ));

      expect(client.lastInsertedPayload!['type'], 'switch');
      expect(client.lastInsertedPayload!['folio_reference_id'],
          '22222222-2222-2222-2222-222222222222');
      expect(
          client.lastInsertedPayload!['destination_scheme_code'], 'SCH-DEST');
      expect(
          client.lastInsertedPayload!['initiated_by_profile_id'], 'advisor-1');
      expect(client.lastInsertedPayload!['initiated_by_role'], 'advisor');
    });

    test('fetchHoldings uses exact folio scoping and switch direction math',
        () async {
      final client = FakeSupabaseClient(queryResponses: {
        'rpc:resolve_order_folio_portfolio': [
          {
            'portfolio_id': 'portfolio-1',
          },
        ],
        'transactions': [
          {
            'portfolio_id': 'portfolio-1',
            'folio_reference_id': 'folio-a',
            'transaction_type': 'BUY',
            'transaction_direction': null,
            'units': 100,
            'mutual_funds': {
              'scheme_code': 'SCH-A',
              'scheme_name': 'Scheme Alpha',
            },
          },
          {
            'portfolio_id': 'portfolio-1',
            'folio_reference_id': 'folio-a',
            'transaction_type': 'SELL',
            'transaction_direction': null,
            'units': 25,
            'mutual_funds': {
              'scheme_code': 'SCH-A',
              'scheme_name': 'Scheme Alpha',
            },
          },
          {
            'portfolio_id': 'portfolio-1',
            'folio_reference_id': 'folio-a',
            'transaction_type': 'SWITCH',
            'transaction_direction': 'INFLOW',
            'units': 10,
            'mutual_funds': {
              'scheme_code': 'SCH-A',
              'scheme_name': 'Scheme Alpha',
            },
          },
          {
            'portfolio_id': 'portfolio-1',
            'folio_reference_id': 'folio-a',
            'transaction_type': 'SWITCH',
            'transaction_direction': 'OUTFLOW',
            'units': 15,
            'mutual_funds': {
              'scheme_code': 'SCH-A',
              'scheme_name': 'Scheme Alpha',
            },
          },
          {
            'portfolio_id': 'portfolio-1',
            'folio_reference_id': 'folio-a',
            'transaction_type': 'SWITCH',
            'transaction_direction': null,
            'units': 999,
            'mutual_funds': {
              'scheme_code': 'SCH-BAD',
              'scheme_name': 'Bad Direction Fund',
            },
          },
          {
            'portfolio_id': 'portfolio-1',
            'folio_reference_id': 'folio-b',
            'transaction_type': 'BUY',
            'transaction_direction': null,
            'units': 200,
            'mutual_funds': {
              'scheme_code': 'SCH-B',
              'scheme_name': 'Other Folio Fund',
            },
          },
        ],
      });
      final repo = SupabaseOrderRepository(client);

      final holdings =
          await repo.fetchHoldings('inv-1', 'workspace-1', 'folio-a');

      expect(holdings.length, 1);
      expect(holdings.single['scheme_code'], 'SCH-A');
      expect(holdings.single['units'], 70);
      expect(holdings.any((h) => h['scheme_code'] == 'SCH-B'), false);
      expect(holdings.any((h) => h['scheme_code'] == 'SCH-BAD'), false);
      expect(client.rpcCalls, ['resolve_order_folio_portfolio']);
      expect(client.lastRpcParams, {
        'p_investor_profile_id': 'inv-1',
        'p_workspace_id': 'workspace-1',
        'p_folio_reference_id': 'folio-a',
      });
      expect(
          client.lastFilters['transactions']?['portfolio_id'], 'portfolio-1');
      expect(
          client.lastFilters['transactions']?['folio_reference_id'], 'folio-a');
    });

    test('fetchFolios maps the safe projection RPC without protected tables',
        () async {
      final client = FakeSupabaseClient(queryResponses: {
        'rpc:list_order_folios': [
          {
            'folio_reference_id': 'folio-safe',
            'portfolio_id': 'portfolio-safe',
            'registrar': 'KFINTECH',
            'masked_folio': 'KFI***321',
            'normalized_folio_number': 'SHOULD_NOT_BE_USED',
          },
        ],
      });
      final repo = SupabaseOrderRepository(client);

      final folios = await repo.fetchFolios('inv-1', 'workspace-1');

      expect(folios, hasLength(1));
      expect(folios.single.folioReferenceId, 'folio-safe');
      expect(folios.single.portfolioId, 'portfolio-safe');
      expect(folios.single.registrar, 'KFINTECH');
      expect(folios.single.maskedFolioDisplay, 'KFI***321');
      expect(client.rpcCalls, ['list_order_folios']);
      expect(client.lastRpcParams, {
        'p_investor_profile_id': 'inv-1',
        'p_workspace_id': 'workspace-1',
      });
      expect(client.tableCalls, isNot(contains('folio_references')));
      expect(client.tableCalls, isNot(contains('portfolio_folio_references')));
    });

    test('fetchHoldings returns empty when selected folio does not resolve',
        () async {
      final client = FakeSupabaseClient(queryResponses: {
        'rpc:resolve_order_folio_portfolio': [],
        'transactions': [
          {
            'portfolio_id': 'portfolio-1',
            'folio_reference_id': 'forged-folio',
            'transaction_type': 'BUY',
            'units': 10,
            'mutual_funds': {
              'scheme_code': 'SCH-A',
              'scheme_name': 'Scheme Alpha',
            },
          },
        ],
      });
      final repo = SupabaseOrderRepository(client);

      final holdings =
          await repo.fetchHoldings('inv-1', 'workspace-1', 'forged-folio');

      expect(holdings, isEmpty);
      expect(client.rpcCalls, ['resolve_order_folio_portfolio']);
      expect(client.tableCalls, isNot(contains('transactions')));
      expect(client.tableCalls, isNot(contains('portfolio_folio_references')));
    });

    test('fetchAssignedInvestors excludes a non-owner admin workspace',
        () async {
      final client = FakeSupabaseClient(queryResponses: {
        'workspace_memberships': [
          {
            'workspace_id': 'workspace-non-owned',
            'profile_id': 'admin-1',
            'role': 'admin',
            'status': 'active',
            'ended_at': null,
          },
          {
            'workspace_id': 'workspace-non-owned',
            'profile_id': 'inv-1',
            'role': 'investor',
            'status': 'active',
            'ended_at': null,
          }
        ],
        'workspaces': [
          {'id': 'workspace-non-owned', 'owner_profile_id': 'different-admin'}
        ],
        'profiles': [
          {'id': 'inv-1', 'full_name': 'John Doe'}
        ]
      });

      final repo = SupabaseOrderRepository(client);
      final list = await repo.fetchAssignedInvestors('admin-1');
      expect(list, isEmpty);
    });

    test(
        'preselected order initiation cannot launch without an exact workspace ID',
        () async {
      final client = FakeSupabaseClient(queryResponses: {
        'profiles': [
          {'id': 'inv-1', 'full_name': 'John Doe'}
        ],
        'workspace_memberships': [
          {
            'workspace_id': 'workspace-1',
            'profile_id': 'inv-1',
            'role': 'investor',
            'status': 'active',
            'ended_at': null,
          }
        ],
        'portfolios': [
          {
            'id': 'portfolio-1',
            'workspace_id': 'workspace-1',
            'client_id': 'inv-1'
          }
        ]
      });

      final repo = SupabaseOrderRepository(client);

      expect(
        () => repo.resolveInvestorContext(
          investorProfileId: 'inv-1',
          initiatorProfileId: 'adv-1',
          initiationRole: 'advisor',
          initiationChannel: 'advisor_portal',
          selectedWorkspaceId: null,
        ),
        throwsA(isA<ConfigurationFailure>().having(
          (e) => e.message,
          'message',
          contains('Selected workspace ID is required'),
        )),
      );
    });
  });
}

// Helper fake Supabase client classes for testing using implements and noSuchMethod
class FakeSupabaseClient implements SupabaseClient {
  final Map<String, List<Map<String, dynamic>>> queryResponses;
  final Object? errorToThrow;
  Map<String, dynamic>? lastInsertedPayload;
  final tableCalls = <String>[];
  final rpcCalls = <String>[];
  Map<String, dynamic>? lastRpcParams;
  final lastFilters = <String, Map<String, dynamic>>{};

  FakeSupabaseClient({
    this.queryResponses = const {},
    this.errorToThrow,
  });

  @override
  SupabaseQueryBuilder from(String table) {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    tableCalls.add(table);
    return FakeSupabaseQueryBuilder(
      table,
      queryResponses,
      onInsert: (payload) {
        lastInsertedPayload = payload;
      },
      onFilters: (filters) {
        lastFilters[table] = Map<String, dynamic>.from(filters);
      },
    );
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    get = false,
  }) {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    rpcCalls.add(fn);
    lastRpcParams = params;
    return FakePostgrestFilterBuilder('rpc:$fn', queryResponses)
        as PostgrestFilterBuilder<T>;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupabaseQueryBuilder implements SupabaseQueryBuilder {
  final String table;
  final Map<String, List<Map<String, dynamic>>> queryResponses;
  final void Function(Map<String, dynamic> payload)? onInsert;
  final void Function(Map<String, dynamic> filters)? onFilters;

  FakeSupabaseQueryBuilder(
    this.table,
    this.queryResponses, {
    this.onInsert,
    this.onFilters,
  });

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select(
      [String columns = '*']) {
    return FakePostgrestFilterBuilder(table, queryResponses,
        onFilters: onFilters);
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> insert(Object values,
      {Object? defaultToNull}) {
    if (onInsert != null && values is Map<String, dynamic>) {
      onInsert!(values);
    }
    return FakePostgrestFilterBuilder(table, queryResponses,
        onFilters: onFilters);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePostgrestFilterBuilder
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  final String table;
  final Map<String, List<Map<String, dynamic>>> queryResponses;
  final void Function(Map<String, dynamic> filters)? onFilters;
  final Map<String, dynamic> filters = {};

  FakePostgrestFilterBuilder(this.table, this.queryResponses, {this.onFilters});

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select(
      [String columns = '*']) {
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(
      String column, Object value) {
    filters[column] = value;
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> inFilter(
      String column, List values) {
    filters[column] = values;
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> isFilter(
      String column, Object? value) {
    filters[column] = value;
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> order(String column,
      {bool ascending = true,
      bool nullsFirst = false,
      String? referencedTable}) {
    return this;
  }

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> limit(int count,
      {String? referencedTable}) {
    return this;
  }

  List<Map<String, dynamic>> _applyFilters() {
    onFilters?.call(filters);
    final list = queryResponses[table] ?? [];
    if (filters.isEmpty) return list;
    return list.where((row) {
      for (final key in filters.keys) {
        final val = filters[key];
        if (val is List) {
          if (!val.contains(row[key])) return false;
        } else {
          if (row[key] != val) return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    return FakePostgrestTransformBuilder<Map<String, dynamic>?>(() async {
      final list = _applyFilters();
      if (list.isEmpty) return null;
      return list.first;
    }());
  }

  @override
  PostgrestTransformBuilder<Map<String, dynamic>> single() {
    return FakePostgrestTransformBuilder<Map<String, dynamic>>(() async {
      final list = _applyFilters();
      if (list.isEmpty) throw Exception("No rows found");
      return list.first;
    }());
  }

  @override
  Future<T> then<T>(
      FutureOr<T> Function(List<Map<String, dynamic>> value) onValue,
      {Function? onError}) {
    final list = _applyFilters();
    return Future.value(list).then(onValue, onError: onError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePostgrestTransformBuilder<T> implements PostgrestTransformBuilder<T> {
  final Future<T> _future;

  FakePostgrestTransformBuilder(this._future);

  @override
  Future<T2> then<T2>(FutureOr<T2> Function(T value) onValue,
      {Function? onError}) {
    return _future.then(onValue, onError: onError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
