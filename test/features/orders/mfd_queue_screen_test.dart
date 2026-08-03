import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mutual_fund_portfolio_app/features/authentication/services/identity_verification_service.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_account.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/models/user_profile.dart';
import 'package:mutual_fund_portfolio_app/features/investor_identity/presentation/screens/mfd_queue_screen.dart';
import 'package:mutual_fund_portfolio_app/features/orders/data/qualification_queue_repository.dart';
import 'package:mutual_fund_portfolio_app/features/orders/data/supabase_qualification_queue_repository.dart';
import 'package:mutual_fund_portfolio_app/features/orders/domain/order_models.dart';
import 'package:mutual_fund_portfolio_app/features/orders/domain/qualification_queue_models.dart';
import 'package:mutual_fund_portfolio_app/features/orders/presentation/qualification_queue_controller.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'package:mutual_fund_portfolio_app/providers/language_provider.dart';
import 'package:mutual_fund_portfolio_app/providers/theme_provider.dart';

void main() {
  group('QualificationQueueItem', () {
    test('maps pending review display data without raw contact PII', () {
      final item = _queueItem();

      expect(item.status, OrderStatus.pendingReview);
      expect(item.orderTypeLabel, 'Buy');
      expect(item.schemeDisplay, 'HDFC Top 100 (SCH-001)');
      expect(item.isSameInitiator(_advisorId), isTrue);
      expect(item.isSameInitiator(_investorId), isFalse);
    });
  });

  group('QualificationQueueController', () {
    test('fetches pending review rows in source order without overlap',
        () async {
      final repository = _FakeQualificationQueueRepository(
        snapshots: [
          QualificationQueueSnapshot(
            items: [_queueItem(id: _orderB), _queueItem(id: _orderA)],
            fetchedAt: DateTime.utc(2026, 8, 4),
          ),
          QualificationQueueSnapshot(
            items: [_queueItem(id: _orderA)],
            fetchedAt: DateTime.utc(2026, 8, 4, 12),
          ),
        ],
        fetchCompleter: Completer<QualificationQueueSnapshot>(),
      );
      final controller = QualificationQueueController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
      );

      final start = controller.start();
      controller.refresh();
      expect(repository.maxConcurrentFetches, 1);

      repository.fetchCompleter!.complete(
        QualificationQueueSnapshot(
          items: [_queueItem(id: _orderA)],
          fetchedAt: DateTime.utc(2026, 8, 4, 12),
        ),
      );
      await start;
      await Future<void>.delayed(Duration.zero);

      expect(repository.fetchCalls, 2);
      expect(controller.items.map((item) => item.id), [_orderA]);
      controller.dispose();
    });

    test('realtime changes are debounced and fallback interval is <= 4s',
        () async {
      final oneShotCallbacks = <void Function()>[];
      Duration? periodicDuration;
      final controller = QualificationQueueController(
        repository: _FakeQualificationQueueRepository(),
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
        debounceDuration: const Duration(milliseconds: 250),
        periodicTimerFactory: (duration, callback) {
          periodicDuration = duration;
          return _FakeTimer();
        },
        oneShotTimerFactory: (duration, callback) {
          oneShotCallbacks.add(callback);
          return _FakeTimer();
        },
      );

      await controller.start();
      controller.realtimeChangedForTest();
      controller.realtimeChangedForTest();

      expect(oneShotCallbacks.length, 2);
      expect(periodicDuration, lessThanOrEqualTo(const Duration(seconds: 4)));
      oneShotCallbacks.last();
      await Future<void>.delayed(Duration.zero);

      expect(controller.items.length, 1);
      controller.dispose();
    });

    test('dispose cancels fallback, debounce and realtime subscriptions',
        () async {
      final repository = _FakeQualificationQueueRepository();
      final timers = <_FakeTimer>[];
      final controller = QualificationQueueController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
        periodicTimerFactory: (duration, callback) {
          final timer = _FakeTimer();
          timers.add(timer);
          return timer;
        },
        oneShotTimerFactory: (duration, callback) {
          final timer = _FakeTimer();
          timers.add(timer);
          return timer;
        },
      );

      await controller.start();
      controller.realtimeChangedForTest();
      controller.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(timers.every((timer) => timer.cancelled), isTrue);
      expect(repository.cancelledSubscriptions, 1);
    });

    test('network timeout reconciles a decision that actually succeeded',
        () async {
      final repository = _FakeQualificationQueueRepository(
        snapshots: [
          QualificationQueueSnapshot(
            items: [_queueItem()],
            fetchedAt: DateTime.utc(2026, 8, 4),
          ),
          QualificationQueueSnapshot(
            items: const [],
            fetchedAt: DateTime.utc(2026, 8, 4, 0, 0, 1),
          ),
        ],
        qualifyFailure: const QualificationQueueFailure(
          QualificationFailureKind.network,
          'The network connection is unavailable. Please try again.',
        ),
        statusResponses: [OrderStatus.approved],
      );
      final controller = QualificationQueueController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
      );

      await controller.start();
      await controller.approve(controller.items.single);

      expect(repository.qualifyCalls.length, 1);
      expect(repository.statusFetchCalls, 1);
      expect(controller.message, 'Order approved.');
      expect(controller.errorMessage, isNull);
      controller.dispose();
    });

    test('network timeout keeps pending order retry deliberate', () async {
      final repository = _FakeQualificationQueueRepository(
        qualifyFailure: const QualificationQueueFailure(
          QualificationFailureKind.network,
          'The network connection is unavailable. Please try again.',
        ),
        statusResponses: [OrderStatus.pendingReview],
      );
      final controller = QualificationQueueController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
      );

      await controller.start();
      await controller.approve(controller.items.single);

      expect(repository.qualifyCalls.length, 1);
      expect(repository.statusFetchCalls, 1);
      expect(controller.message, isNull);
      expect(controller.errorMessage, contains('not confirmed'));
      expect(controller.items, isNotEmpty);
      controller.dispose();
    });

    test('ambiguous response refreshes without automatic resubmission',
        () async {
      final repository = _FakeQualificationQueueRepository(
        qualifyFailure: const QualificationQueueFailure(
          QualificationFailureKind.unknown,
          'The order could not be qualified.',
        ),
        statusResponses: [OrderStatus.pendingReview],
      );
      final controller = QualificationQueueController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
      );

      await controller.start();
      await controller.reject(controller.items.single, '  Check offline  ');

      expect(repository.qualifyCalls.length, 1);
      expect(repository.qualifyCalls.single.rejectionReason, 'Check offline');
      expect(repository.statusFetchCalls, 1);
      expect(repository.fetchCalls, greaterThanOrEqualTo(2));
      expect(controller.errorMessage, contains('not confirmed'));
      controller.dispose();
    });

    test('tracks independent in-flight actions per order', () async {
      final approveA = Completer<QualificationOrderResult>();
      final rejectB = Completer<QualificationOrderResult>();
      final repository = _FakeQualificationQueueRepository(
        snapshots: [
          QualificationQueueSnapshot(
            items: [
              _queueItem(id: _orderA),
              _queueItem(id: _orderB),
            ],
            fetchedAt: DateTime.utc(2026, 8, 4),
          ),
        ],
        qualifyCompletersByOrder: {
          _orderA: approveA,
          _orderB: rejectB,
        },
      );
      final controller = QualificationQueueController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
      );

      await controller.start();
      final orderA = controller.items.firstWhere((item) => item.id == _orderA);
      final orderB = controller.items.firstWhere((item) => item.id == _orderB);

      final actionA = controller.approve(orderA);
      final actionB = controller.reject(orderB, 'Needs review');
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeDecisionFor(_orderA),
          QualificationDecision.approved);
      expect(controller.activeDecisionFor(_orderB),
          QualificationDecision.rejected);
      expect(controller.isOrderActionActive(_orderA), isTrue);
      expect(controller.isOrderActionActive(_orderB), isTrue);

      await controller.approve(orderA);
      expect(repository.qualifyCalls.where((call) => call.orderId == _orderA),
          hasLength(1));

      approveA.complete(
        const QualificationOrderResult(
          orderId: _orderA,
          status: OrderStatus.approved,
        ),
      );
      await actionA;
      expect(controller.isOrderActionActive(_orderA), isFalse);
      expect(controller.activeDecisionFor(_orderB),
          QualificationDecision.rejected);

      rejectB.complete(
        const QualificationOrderResult(
          orderId: _orderB,
          status: OrderStatus.rejected,
        ),
      );
      await actionB;

      expect(controller.isOrderActionActive(_orderB), isFalse);
      expect(repository.qualifyCalls.where((call) => call.orderId == _orderB),
          hasLength(1));
      expect(repository.qualifyCalls, hasLength(2));
      controller.dispose();
    });

    test('unknown RPC failure reconciles confirmed approved status', () async {
      final repository = _FakeQualificationQueueRepository(
        qualifyFailure: const QualificationQueueFailure(
          QualificationFailureKind.unknown,
          'The order could not be qualified.',
        ),
        statusResponses: [OrderStatus.approved],
        snapshots: [
          QualificationQueueSnapshot(
            items: [_queueItem()],
            fetchedAt: DateTime.utc(2026, 8, 4),
          ),
          QualificationQueueSnapshot(
            items: const [],
            fetchedAt: DateTime.utc(2026, 8, 4, 0, 0, 1),
          ),
        ],
      );
      final controller = QualificationQueueController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
      );

      await controller.start();
      await controller.approve(controller.items.single);

      expect(repository.qualifyCalls, hasLength(1));
      expect(repository.statusFetchCalls, 1);
      expect(controller.message, 'Order approved.');
      expect(controller.errorMessage, isNull);
      controller.dispose();
    });

    test('unknown RPC failure reconciles confirmed rejected status', () async {
      final repository = _FakeQualificationQueueRepository(
        qualifyFailure: const QualificationQueueFailure(
          QualificationFailureKind.unknown,
          'The order could not be qualified.',
        ),
        statusResponses: [OrderStatus.rejected],
        snapshots: [
          QualificationQueueSnapshot(
            items: [_queueItem()],
            fetchedAt: DateTime.utc(2026, 8, 4),
          ),
          QualificationQueueSnapshot(
            items: const [],
            fetchedAt: DateTime.utc(2026, 8, 4, 0, 0, 1),
          ),
        ],
      );
      final controller = QualificationQueueController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
      );

      await controller.start();
      await controller.reject(controller.items.single, 'Mismatch');

      expect(repository.qualifyCalls, hasLength(1));
      expect(repository.statusFetchCalls, 1);
      expect(controller.message, 'Order rejected.');
      expect(controller.errorMessage, isNull);
      controller.dispose();
    });

    test('unknown RPC failure keeps pending retry deliberate', () async {
      final repository = _FakeQualificationQueueRepository(
        qualifyFailure: const QualificationQueueFailure(
          QualificationFailureKind.unknown,
          'The order could not be qualified.',
        ),
        statusResponses: [OrderStatus.pendingReview],
      );
      final controller = QualificationQueueController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
      );

      await controller.start();
      await controller.approve(controller.items.single);

      expect(repository.qualifyCalls, hasLength(1));
      expect(repository.statusFetchCalls, 1);
      expect(controller.message, isNull);
      expect(controller.errorMessage, contains('not confirmed'));
      expect(controller.isOrderActionActive(_orderA), isFalse);
      controller.dispose();
    });

    test('unknown RPC failure reports a different terminal status', () async {
      final repository = _FakeQualificationQueueRepository(
        qualifyFailure: const QualificationQueueFailure(
          QualificationFailureKind.unknown,
          'The order could not be qualified.',
        ),
        statusResponses: [OrderStatus.rejected],
      );
      final controller = QualificationQueueController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
      );

      await controller.start();
      await controller.approve(controller.items.single);

      expect(repository.qualifyCalls, hasLength(1));
      expect(repository.statusFetchCalls, 1);
      expect(controller.message, contains('already resolved as rejected'));
      expect(controller.errorMessage, isNull);
      controller.dispose();
    });

    test('active state stays set during unknown failure reconciliation',
        () async {
      final statusCompleter = Completer<OrderStatus?>();
      final repository = _FakeQualificationQueueRepository(
        qualifyFailure: const QualificationQueueFailure(
          QualificationFailureKind.ambiguous,
          'The qualification result could not be confirmed.',
        ),
        statusCompleter: statusCompleter,
      );
      final controller = QualificationQueueController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
      );

      await controller.start();
      final action = controller.approve(controller.items.single);
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeDecisionFor(_orderA),
          QualificationDecision.approved);
      expect(repository.qualifyCalls, hasLength(1));

      statusCompleter.complete(OrderStatus.pendingReview);
      await action;

      expect(repository.qualifyCalls, hasLength(1));
      expect(controller.isOrderActionActive(_orderA), isFalse);
      expect(controller.errorMessage, contains('not confirmed'));
      controller.dispose();
    });

    test('access denied qualification does not reconcile as ambiguous',
        () async {
      final repository = _FakeQualificationQueueRepository(
        qualifyFailure: const QualificationQueueFailure(
          QualificationFailureKind.accessDenied,
          'You are not authorised to qualify this order.',
        ),
        statusResponses: [OrderStatus.approved],
      );
      final controller = QualificationQueueController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
      );

      await controller.start();
      await controller.approve(controller.items.single);

      expect(repository.qualifyCalls, hasLength(1));
      expect(repository.statusFetchCalls, 0);
      expect(controller.message, isNull);
      expect(controller.errorMessage,
          'You are not authorised to qualify this order.');
      controller.dispose();
    });

    test('count controller refreshes on realtime, bus, fallback and dispose',
        () async {
      final repository = _FakeQualificationQueueRepository(counts: [2, 1, 0]);
      final oneShotCallbacks = <void Function()>[];
      final periodicCallbacks = <void Function(Timer)>[];
      final timers = <_FakeTimer>[];
      final controller = QualificationQueueCountController(
        repository: repository,
        reviewerProfileId: _advisorId,
        isAuthorizedReviewer: true,
        periodicTimerFactory: (duration, callback) {
          periodicCallbacks.add(callback);
          final timer = _FakeTimer();
          timers.add(timer);
          return timer;
        },
        oneShotTimerFactory: (duration, callback) {
          final timer = _FakeTimer();
          oneShotCallbacks.add(() {
            timer.cancel();
            callback();
          });
          timers.add(timer);
          return timer;
        },
      );

      await controller.start();
      expect(controller.count, 2);

      controller.realtimeChangedForTest();
      oneShotCallbacks.removeLast()();
      await Future<void>.delayed(Duration.zero);
      expect(controller.count, 1);

      QualificationQueueRefreshBus.notifyChanged();
      await Future<void>.delayed(Duration.zero);
      oneShotCallbacks.removeLast()();
      await Future<void>.delayed(Duration.zero);
      expect(controller.count, 0);

      periodicCallbacks.single(_FakeTimer());
      await Future<void>.delayed(Duration.zero);
      expect(repository.countCalls, 4);

      controller.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(timers.every((timer) => timer.cancelled), isTrue);
      expect(repository.cancelledSubscriptions, 1);
    });
  });

  group('SupabaseQualificationQueueRepository', () {
    test('filters pending review orders, narrows workspaces and maps rows',
        () async {
      final client = _FakeSupabaseClient({
        'workspace_memberships': [
          {
            'workspace_id': _workspaceId,
            'profile_id': _advisorId,
            'role': 'advisor',
            'status': 'active',
            'ended_at': null,
          },
        ],
        'order_requests': [
          _orderRow(
            id: _orderA,
            workspaceId: _workspaceId,
            status: 'pending_review',
            createdAt: '2026-08-04T09:30:00Z',
          ),
          _orderRow(
            id: _orderB,
            workspaceId: _workspaceId,
            status: 'pending_review',
            createdAt: '2026-08-04T09:00:00Z',
          ),
          _orderRow(
            id: '35000000-0000-0000-0000-000000000103',
            workspaceId: _workspaceId,
            status: 'pending_qualification',
            createdAt: '2026-08-04T08:00:00Z',
          ),
          _orderRow(
            id: '35000000-0000-0000-0000-000000000104',
            workspaceId: '35000000-0000-0000-0000-000000000099',
            status: 'pending_review',
            createdAt: '2026-08-04T07:00:00Z',
          ),
        ],
        'profiles': [
          {
            'id': _investorId,
            'full_name': 'Ravi Investor',
          },
          {
            'id': _advisorId,
            'full_name': 'Ravi Advisor',
          },
        ],
        'mutual_funds': [
          {'scheme_code': 'SCH-001', 'scheme_name': 'HDFC Top 100'},
        ],
      });
      final repository = SupabaseQualificationQueueRepository(client);

      final snapshot = await repository.fetchQueue(
        reviewerProfileId: _advisorId,
      );

      expect(snapshot.items.map((item) => item.id), [_orderB, _orderA]);
      expect(
          snapshot.items.singleWhere((item) => item.id == _orderA).schemeName,
          'HDFC Top 100');
      expect(snapshot.items.map((item) => item.workspaceId).toSet(),
          {_workspaceId});
      expect(
          snapshot.items
              .every((item) => item.status == OrderStatus.pendingReview),
          isTrue);
      expect(client.selectCalls['profiles'], ['id, full_name']);
    });

    test('count fetch uses native count and no profile or fund data', () async {
      final client = _FakeSupabaseClient({
        'workspace_memberships': [
          {
            'workspace_id': _workspaceId,
            'profile_id': _advisorId,
            'role': 'advisor',
            'status': 'active',
            'ended_at': null,
          },
        ],
        'order_requests': [
          _orderRow(
            id: _orderA,
            workspaceId: _workspaceId,
            status: 'pending_review',
            createdAt: '2026-08-04T09:30:00Z',
          ),
        ],
      });
      final repository = SupabaseQualificationQueueRepository(client);

      final count = await repository.fetchPendingReviewCount(
        reviewerProfileId: _advisorId,
      );

      expect(count, 1);
      expect(client.countCallsByTable, ['order_requests']);
      expect(client.selectCalls.containsKey('order_requests'), isFalse);
      expect(client.selectCalls.containsKey('profiles'), isFalse);
      expect(client.selectCalls.containsKey('mutual_funds'), isFalse);
    });

    test('validates approved and rejected RPC responses', () async {
      final approvedClient = _FakeSupabaseClient(
        const {},
        rpcResponse: {'id': _orderA, 'status': 'approved'},
      );
      final approvedRepository =
          SupabaseQualificationQueueRepository(approvedClient);

      final approved = await approvedRepository.qualifyOrder(
        orderId: _orderA,
        decision: QualificationDecision.approved,
      );

      expect(approved.orderId, _orderA);
      expect(approved.status, OrderStatus.approved);

      final rejectedClient = _FakeSupabaseClient(
        const {},
        rpcResponse: {'id': _orderA, 'status': 'rejected'},
      );
      final rejectedRepository =
          SupabaseQualificationQueueRepository(rejectedClient);

      final rejected = await rejectedRepository.qualifyOrder(
        orderId: _orderA,
        decision: QualificationDecision.rejected,
        rejectionReason: 'Needs review',
      );

      expect(rejected.orderId, _orderA);
      expect(rejected.status, OrderStatus.rejected);
    });

    test('classifies null, wrong order and wrong status as ambiguous',
        () async {
      for (final response in [
        null,
        {'id': _orderB, 'status': 'approved'},
        {'id': _orderA, 'status': 'pending_review'},
      ]) {
        final repository = SupabaseQualificationQueueRepository(
          _FakeSupabaseClient(const {}, rpcResponse: response),
        );

        expect(
          () => repository.qualifyOrder(
            orderId: _orderA,
            decision: QualificationDecision.approved,
          ),
          throwsA(isA<QualificationQueueFailure>().having(
            (error) => error.kind,
            'kind',
            QualificationFailureKind.ambiguous,
          )),
        );
      }
    });

    test('classifies order not found as stale and not_authorized as denied',
        () async {
      final staleRepository = SupabaseQualificationQueueRepository(
        _FakeSupabaseClient(const {}, rpcError: Exception('Order not found')),
      );
      expect(
        () => staleRepository.qualifyOrder(
          orderId: _orderA,
          decision: QualificationDecision.approved,
        ),
        throwsA(isA<QualificationQueueFailure>().having(
          (error) => error.kind,
          'kind',
          QualificationFailureKind.stale,
        )),
      );

      final deniedRepository = SupabaseQualificationQueueRepository(
        _FakeSupabaseClient(const {}, rpcError: Exception('not_authorized')),
      );
      expect(
        () => deniedRepository.qualifyOrder(
          orderId: _orderA,
          decision: QualificationDecision.approved,
        ),
        throwsA(isA<QualificationQueueFailure>().having(
          (error) => error.kind,
          'kind',
          QualificationFailureKind.accessDenied,
        )),
      );
    });

    test('classifies generic qualification RPC errors as ambiguous', () async {
      final repository = SupabaseQualificationQueueRepository(
        _FakeSupabaseClient(
          const {},
          rpcError: Exception('XMLHttpRequest error'),
        ),
      );

      expect(
        () => repository.qualifyOrder(
          orderId: _orderA,
          decision: QualificationDecision.approved,
        ),
        throwsA(isA<QualificationQueueFailure>().having(
          (error) => error.kind,
          'kind',
          QualificationFailureKind.ambiguous,
        )),
      );
    });
  });

  group('MfdQueueScreen', () {
    testWidgets('renders advisor queue details, same-user marker and actions',
        (tester) async {
      final repository = _FakeQualificationQueueRepository();

      await _pumpQueue(tester, repository: repository);
      await tester.pump();

      expect(find.text('MFD qualification queue'), findsOneWidget);
      expect(find.text('Ravi Investor'), findsOneWidget);
      expect(find.text('Ravi Advisor'), findsOneWidget);
      expect(find.text('Advisor / Advisor console'), findsOneWidget);
      expect(find.text('Pending review'), findsOneWidget);
      expect(find.text('Buy'), findsOneWidget);
      expect(find.text('HDFC Top 100 (SCH-001)'), findsOneWidget);
      expect(find.text('Rs 25,000.00 / 42.5000 units'), findsOneWidget);
      expect(find.text('Initiated by you'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Reject'), findsOneWidget);
    });

    testWidgets('blocks investors and does not fetch queue rows',
        (tester) async {
      final repository = _FakeQualificationQueueRepository();
      await _pumpQueue(
        tester,
        repository: repository,
        profile: _profile(UserRole.investor, id: _investorId),
      );
      await tester.pump();

      expect(
        find.text('This queue is available only to authorised MFD users.'),
        findsWidgets,
      );
      expect(repository.fetchCalls, 0);
    });

    testWidgets('approve cancel performs no RPC', (tester) async {
      final repository = _FakeQualificationQueueRepository();
      await _pumpQueue(tester, repository: repository);
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Confirm approval'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(repository.qualifyCalls, isEmpty);
    });

    testWidgets('approve confirmation performs exactly one RPC',
        (tester) async {
      final repository = _FakeQualificationQueueRepository(
        qualifyCompleter: Completer<QualificationOrderResult>(),
      );
      await _pumpQueue(tester, repository: repository);
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm approval'));
      await tester.pump();

      expect(repository.qualifyCalls.length, 1);
      expect(repository.qualifyCalls.single.decision,
          QualificationDecision.approved);
      expect(repository.qualifyCalls.single.rejectionReason, isNull);

      repository.qualifyCompleter!.complete(
        const QualificationOrderResult(
          orderId: _orderA,
          status: OrderStatus.approved,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Order approved.'), findsOneWidget);
    });

    testWidgets('same-user order remains approvable after confirmation',
        (tester) async {
      final repository = _FakeQualificationQueueRepository();
      await _pumpQueue(tester, repository: repository);
      await tester.pump();

      expect(find.text('Initiated by you'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm approval'));
      await tester.pumpAndSettle();

      expect(repository.qualifyCalls.length, 1);
    });

    testWidgets('rapid approval confirmation taps submit once', (tester) async {
      final repository = _FakeQualificationQueueRepository(
        qualifyCompleter: Completer<QualificationOrderResult>(),
      );
      await _pumpQueue(tester, repository: repository);
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      final confirmButton =
          find.widgetWithText(FilledButton, 'Confirm approval');
      await tester.tap(confirmButton);
      await tester.tap(confirmButton, warnIfMissed: false);
      await tester.pump();

      expect(repository.qualifyCalls.length, 1);
      repository.qualifyCompleter!.complete(
        const QualificationOrderResult(
          orderId: _orderA,
          status: OrderStatus.approved,
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('reject trims blank reasons to null and refreshes',
        (tester) async {
      final repository = _FakeQualificationQueueRepository();
      await _pumpQueue(tester, repository: repository);
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();

      expect(repository.qualifyCalls.single.decision,
          QualificationDecision.rejected);
      expect(repository.qualifyCalls.single.rejectionReason, isNull);
      expect(find.text('Order rejected.'), findsOneWidget);
    });

    testWidgets('stale qualification errors are safe and refresh the queue',
        (tester) async {
      final repository = _FakeQualificationQueueRepository(
        qualifyFailure: const QualificationQueueFailure(
          QualificationFailureKind.stale,
          'This order was already resolved. The queue was refreshed.',
        ),
        snapshots: [
          QualificationQueueSnapshot(
            items: [_queueItem()],
            fetchedAt: DateTime.utc(2026, 8, 4),
          ),
          QualificationQueueSnapshot(
            items: const [],
            fetchedAt: DateTime.utc(2026, 8, 4, 0, 0, 1),
          ),
        ],
        statusResponses: const [null],
      );

      await _pumpQueue(tester, repository: repository);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm approval'));
      await tester.pumpAndSettle();

      expect(find.text('No orders awaiting qualification.'), findsOneWidget);
      expect(find.textContaining('already resolved'), findsWidgets);
    });

    testWidgets('shows safe access denied, network and unknown errors',
        (tester) async {
      for (final failure in const [
        QualificationQueueFailure(
          QualificationFailureKind.accessDenied,
          'You are not authorised to qualify this order.',
        ),
        QualificationQueueFailure(
          QualificationFailureKind.network,
          'The network connection is unavailable. Please try again.',
        ),
        QualificationQueueFailure(
          QualificationFailureKind.unknown,
          'The qualification queue is unavailable.',
        ),
      ]) {
        final repository =
            _FakeQualificationQueueRepository(fetchFailure: failure);
        await _pumpQueue(tester, repository: repository);
        await tester.pumpAndSettle();
        expect(find.text(failure.message), findsWidgets);
      }
    });

    testWidgets('renders in dark, narrow, and large text layouts',
        (tester) async {
      final theme = ThemeProvider()..setThemeMode(ThemeModeOption.dark);
      await _pumpQueue(
        tester,
        repository: _FakeQualificationQueueRepository(),
        themeProvider: theme,
        surfaceSize: const Size(390, 844),
        textScaler: const TextScaler.linear(1.6),
      );
      await tester.pumpAndSettle();

      expect(find.text('MFD qualification queue'), findsOneWidget);
      expect(find.text('Initiated by you'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('count badge uses lightweight count and resets by reviewer',
        (tester) async {
      final repository = _FakeQualificationQueueRepository(
        counts: [2, 5],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
              value: _FakeAuthProvider(
                isAuthenticated: true,
                userProfile: _profile(UserRole.advisor),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MfdQueueCountBadge(repository: repository),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(repository.countCalls, 1);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
              value: _FakeAuthProvider(
                isAuthenticated: true,
                userProfile: _profile(
                  UserRole.advisor,
                  id: '35000000-0000-0000-0000-000000000003',
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MfdQueueCountBadge(repository: repository),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('5'), findsOneWidget);
      expect(repository.countCalls, 2);
    });
  });
}

Future<void> _pumpQueue(
  WidgetTester tester, {
  required _FakeQualificationQueueRepository repository,
  UserProfile? profile,
  ThemeProvider? themeProvider,
  Size? surfaceSize,
  TextScaler? textScaler,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
          value: _FakeAuthProvider(
            isAuthenticated: true,
            userProfile: profile ?? _profile(UserRole.advisor),
          ),
        ),
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider ?? ThemeProvider(),
        ),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: surfaceSize ?? const Size(1024, 768),
            textScaler: textScaler ?? TextScaler.noScaling,
          ),
          child: MfdQueueScreen(
            repository: repository,
            periodicTimerFactory: (duration, callback) => _FakeTimer(),
          ),
        ),
      ),
    ),
  );
}

const _advisorId = '35000000-0000-0000-0000-000000000001';
const _investorId = '35000000-0000-0000-0000-000000000002';
const _workspaceId = '35000000-0000-0000-0000-000000000010';
const _orderA = '35000000-0000-0000-0000-000000000101';
const _orderB = '35000000-0000-0000-0000-000000000102';

QualificationQueueItem _queueItem({
  String id = _orderA,
  OrderStatus status = OrderStatus.pendingReview,
}) =>
    QualificationQueueItem(
      id: id,
      workspaceId: _workspaceId,
      investorProfileId: _investorId,
      investorName: 'Ravi Investor',
      initiatedByProfileId: _advisorId,
      initiatorName: 'Ravi Advisor',
      initiatedByRole: 'advisor',
      initiationChannel: 'advisor_console',
      status: status,
      type: OrderType.buy,
      schemeCode: 'SCH-001',
      schemeName: 'HDFC Top 100',
      amount: 25000,
      units: 42.5,
      createdAt: DateTime.utc(2026, 8, 4, 9, 30).toLocal(),
    );

Map<String, dynamic> _orderRow({
  required String id,
  required String workspaceId,
  required String status,
  required String createdAt,
}) =>
    {
      'id': id,
      'workspace_id': workspaceId,
      'investor_profile_id': _investorId,
      'initiated_by_profile_id': _advisorId,
      'initiated_by_role': 'advisor',
      'initiation_channel': 'advisor_console',
      'scheme_code': 'SCH-001',
      'destination_scheme_code': null,
      'type': 'buy',
      'amount': '25000',
      'units': '42.5',
      'status': status,
      'created_at': createdAt,
    };

UserProfile _profile(UserRole role, {String id = _advisorId}) => UserProfile(
      id: id,
      role: role,
      accountStatus: AccountStatus.active,
      fullName: 'Reviewer',
      createdAt: DateTime.utc(2026, 8, 4),
      updatedAt: DateTime.utc(2026, 8, 4),
    );

class _FakeQualificationQueueRepository
    implements QualificationQueueRepository {
  _FakeQualificationQueueRepository({
    List<QualificationQueueSnapshot>? snapshots,
    List<int>? counts,
    List<OrderStatus?>? statusResponses,
    this.fetchFailure,
    this.qualifyFailure,
    this.fetchCompleter,
    this.qualifyCompleter,
    this.statusCompleter,
    Map<String, Completer<QualificationOrderResult>>? qualifyCompletersByOrder,
    Map<String, QualificationQueueFailure>? qualifyFailuresByOrder,
  })  : snapshots = snapshots ??
            [
              QualificationQueueSnapshot(
                items: [_queueItem()],
                fetchedAt: DateTime.utc(2026, 8, 4),
              ),
            ],
        counts = counts ?? const [],
        statusResponses = statusResponses ?? const [],
        qualifyCompletersByOrder = qualifyCompletersByOrder ?? const {},
        qualifyFailuresByOrder = qualifyFailuresByOrder ?? const {};

  final List<QualificationQueueSnapshot> snapshots;
  final List<int> counts;
  final List<OrderStatus?> statusResponses;
  final QualificationQueueFailure? fetchFailure;
  final QualificationQueueFailure? qualifyFailure;
  final Completer<QualificationQueueSnapshot>? fetchCompleter;
  final Completer<QualificationOrderResult>? qualifyCompleter;
  final Completer<OrderStatus?>? statusCompleter;
  final Map<String, Completer<QualificationOrderResult>>
      qualifyCompletersByOrder;
  final Map<String, QualificationQueueFailure> qualifyFailuresByOrder;
  final qualifyCalls = <_QualifyCall>[];
  int fetchCalls = 0;
  int countCalls = 0;
  int statusFetchCalls = 0;
  int activeFetches = 0;
  int maxConcurrentFetches = 0;
  int cancelledSubscriptions = 0;

  @override
  Duration get fallbackRefreshInterval => const Duration(seconds: 4);

  @override
  Future<QualificationQueueSnapshot> fetchQueue({
    required String reviewerProfileId,
  }) async {
    fetchCalls += 1;
    activeFetches += 1;
    maxConcurrentFetches = activeFetches > maxConcurrentFetches
        ? activeFetches
        : maxConcurrentFetches;
    try {
      if (fetchFailure != null) throw fetchFailure!;
      if (fetchCompleter != null && fetchCalls == 1) {
        return await fetchCompleter!.future;
      }
      final index = fetchCalls - 1;
      if (index >= snapshots.length) return snapshots.last;
      return snapshots[index];
    } finally {
      activeFetches -= 1;
    }
  }

  @override
  Future<int> fetchPendingReviewCount({
    required String reviewerProfileId,
  }) async {
    countCalls += 1;
    if (counts.isNotEmpty) {
      final index = countCalls - 1;
      if (index >= counts.length) return counts.last;
      return counts[index];
    }
    final index = fetchCalls;
    if (index >= snapshots.length) return snapshots.last.items.length;
    return snapshots[index].items.length;
  }

  @override
  Future<OrderStatus?> fetchOrderStatus({
    required String orderId,
  }) async {
    statusFetchCalls += 1;
    if (statusCompleter != null) return statusCompleter!.future;
    if (statusResponses.isEmpty) return OrderStatus.pendingReview;
    final index = statusFetchCalls - 1;
    if (index >= statusResponses.length) return statusResponses.last;
    return statusResponses[index];
  }

  @override
  Future<QualificationOrderResult> qualifyOrder({
    required String orderId,
    required QualificationDecision decision,
    String? rejectionReason,
  }) async {
    qualifyCalls.add(_QualifyCall(orderId, decision, rejectionReason));
    final orderFailure = qualifyFailuresByOrder[orderId];
    if (orderFailure != null) throw orderFailure;
    if (qualifyFailure != null) throw qualifyFailure!;
    final orderCompleter = qualifyCompletersByOrder[orderId];
    if (orderCompleter != null) return orderCompleter.future;
    if (qualifyCompleter != null) return qualifyCompleter!.future;
    return QualificationOrderResult(
      orderId: orderId,
      status: decision == QualificationDecision.approved
          ? OrderStatus.approved
          : OrderStatus.rejected,
    );
  }

  @override
  QualificationQueueSubscription subscribeToOrderChanges(
    void Function() onChanged,
  ) =>
      _FakeQualificationQueueSubscription(
        onCancel: () => cancelledSubscriptions += 1,
      );
}

class _FakeSupabaseClient implements SupabaseClient {
  _FakeSupabaseClient(
    this.rowsByTable, {
    this.rpcResponse,
    this.rpcError,
  });

  final Map<String, List<Map<String, dynamic>>> rowsByTable;
  final Object? rpcResponse;
  final Object? rpcError;
  final selectCalls = <String, List<String>>{};
  final countCallsByTable = <String>[];

  @override
  SupabaseQueryBuilder from(String table) => _FakeSupabaseQueryBuilder(
        table,
        rowsByTable,
        selectCalls,
        countCallsByTable,
      );

  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    get = false,
  }) =>
      _FakeRpcFilterBuilder<T>(rpcResponse, rpcError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSupabaseQueryBuilder implements SupabaseQueryBuilder {
  _FakeSupabaseQueryBuilder(
    this.table,
    this.rowsByTable,
    this.selectCalls,
    this.countCallsByTable,
  );

  final String table;
  final Map<String, List<Map<String, dynamic>>> rowsByTable;
  final Map<String, List<String>> selectCalls;
  final List<String> countCallsByTable;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select(
      [String columns = '*']) {
    selectCalls.putIfAbsent(table, () => []).add(columns);
    return _FakePostgrestFilterBuilder(table, rowsByTable);
  }

  @override
  PostgrestFilterBuilder<int> count([CountOption option = CountOption.exact]) {
    countCallsByTable.add(table);
    return _FakePostgrestCountBuilder(table, rowsByTable);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePostgrestFilterBuilder
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _FakePostgrestFilterBuilder(this.table, this.rowsByTable);

  final String table;
  final Map<String, List<Map<String, dynamic>>> rowsByTable;
  final Map<String, Object?> filters = {};
  final orderColumns = <String>[];

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
  PostgrestFilterBuilder<List<Map<String, dynamic>>> order(
    String column, {
    bool ascending = true,
    bool nullsFirst = false,
    String? referencedTable,
  }) {
    orderColumns.add(column);
    return this;
  }

  List<Map<String, dynamic>> _filteredRows() {
    final rows = [...rowsByTable[table] ?? const <Map<String, dynamic>>[]];
    final filtered = rows.where((row) {
      for (final entry in filters.entries) {
        final expected = entry.value;
        if (expected is List) {
          if (!expected.contains(row[entry.key])) return false;
        } else if (row[entry.key] != expected) {
          return false;
        }
      }
      return true;
    }).toList();
    filtered.sort((left, right) {
      for (final column in orderColumns) {
        final comparison = '${left[column]}'.compareTo('${right[column]}');
        if (comparison != 0) return comparison;
      }
      return 0;
    });
    return filtered;
  }

  @override
  Future<T> then<T>(
    FutureOr<T> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) =>
      Future.value(_filteredRows()).then(onValue, onError: onError);

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() =>
      _FakePostgrestTransformBuilder<Map<String, dynamic>?>(() async {
        final rows = _filteredRows();
        if (rows.isEmpty) return null;
        return rows.first;
      }());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePostgrestTransformBuilder<T>
    implements PostgrestTransformBuilder<T> {
  _FakePostgrestTransformBuilder(this.future);

  final Future<T> future;

  @override
  Future<T2> then<T2>(
    FutureOr<T2> Function(T value) onValue, {
    Function? onError,
  }) =>
      future.then(onValue, onError: onError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePostgrestCountBuilder implements PostgrestFilterBuilder<int> {
  _FakePostgrestCountBuilder(this.table, this.rowsByTable);

  final String table;
  final Map<String, List<Map<String, dynamic>>> rowsByTable;
  final Map<String, Object?> filters = {};

  @override
  PostgrestFilterBuilder<int> eq(String column, Object value) {
    filters[column] = value;
    return this;
  }

  @override
  PostgrestFilterBuilder<int> inFilter(String column, List values) {
    filters[column] = values;
    return this;
  }

  @override
  PostgrestFilterBuilder<int> isFilter(String column, Object? value) {
    filters[column] = value;
    return this;
  }

  int _filteredCount() {
    final rows = rowsByTable[table] ?? const <Map<String, dynamic>>[];
    return rows.where((row) {
      for (final entry in filters.entries) {
        final expected = entry.value;
        if (expected is List) {
          if (!expected.contains(row[entry.key])) return false;
        } else if (row[entry.key] != expected) {
          return false;
        }
      }
      return true;
    }).length;
  }

  @override
  Future<T> then<T>(
    FutureOr<T> Function(int value) onValue, {
    Function? onError,
  }) =>
      Future.value(_filteredCount()).then(onValue, onError: onError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRpcFilterBuilder<T> implements PostgrestFilterBuilder<T> {
  _FakeRpcFilterBuilder(this.response, this.error);

  final Object? response;
  final Object? error;

  @override
  Future<T2> then<T2>(
    FutureOr<T2> Function(T value) onValue, {
    Function? onError,
  }) {
    final future = error == null
        ? Future<T>.value(response as T)
        : Future<T>.error(error!);
    return future.then(onValue, onError: onError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeQualificationQueueSubscription
    implements QualificationQueueSubscription {
  const _FakeQualificationQueueSubscription({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Future<void> cancel() async => onCancel();
}

class _QualifyCall {
  const _QualifyCall(this.orderId, this.decision, this.rejectionReason);

  final String orderId;
  final QualificationDecision decision;
  final String? rejectionReason;
}

class _FakeTimer implements Timer {
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  _FakeAuthProvider({
    required this.isAuthenticated,
    required this.userProfile,
  });

  @override
  final bool isAuthenticated;

  @override
  final UserProfile? userProfile;

  @override
  bool get isLoading => false;

  @override
  UserAccount? get userAccount => null;

  @override
  AccountState? get accountState => userAccount?.accountState;

  @override
  String? get errorMessage => null;

  @override
  User? get user => isAuthenticated
      ? User(
          id: userProfile?.id ?? '35000000-0000-0000-0000-000000000099',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime.utc(2026, 8, 4).toIso8601String(),
        )
      : null;

  @override
  List<VerificationMethodDescriptor> get verificationMethods => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
