import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/nse_integration/data/nse_pending_storage.dart';
import 'package:mutual_fund_portfolio_app/features/nse_integration/data/nse_read_repository.dart';
import 'package:mutual_fund_portfolio_app/features/nse_integration/data/supabase_nse_read_repository.dart';
import 'package:mutual_fund_portfolio_app/features/nse_integration/domain/nse_models.dart';
import 'package:mutual_fund_portfolio_app/features/nse_integration/presentation/nse_integration_controller.dart';
import 'package:mutual_fund_portfolio_app/features/nse_integration/presentation/nse_integration_entry.dart';
import 'package:mutual_fund_portfolio_app/features/nse_integration/presentation/nse_integration_page.dart';

const targetId = 'aa030000-0000-4000-8000-000000000004';
const opId = 'aa060000-0000-4000-8000-000000000001';
const requestId = 'aa070000-0000-4000-8000-000000000001';
final created = DateTime.utc(2026, 10, 2);
NseReadCommand command() => NseReadCommand(
    kind: NseReadKind.orderStatus, from: '2026-10-01', to: '2026-10-02');
NseOperation snapshot(
        {NseDisplayStatus status = NseDisplayStatus.queued,
        String target = targetId,
        String operationId = opId}) =>
    NseOperation(
        id: operationId,
        targetRef: target,
        kind: NseReadKind.orderStatus,
        status: status,
        terminal: ![
          NseDisplayStatus.queued,
          NseDisplayStatus.running,
          NseDisplayStatus.retryPending
        ].contains(status),
        attempts: 1,
        createdAt: created,
        updatedAt: created,
        fetchedAt: created,
        summary: status == NseDisplayStatus.success
            ? const NseSummary('S', 'order_status_no_records', 0, 0, 0, 0)
            : null);
Map<String, dynamic> operationJson() => {
      'operation_id': opId,
      'target_ref': targetId,
      'kind': 'read_order_status',
      'state': 'SUCCESS',
      'display_status': 'SUCCESS',
      'terminal': true,
      'attempt_count': 1,
      'created_at': created.toIso8601String(),
      'updated_at': created.toIso8601String(),
      'fetched_at': created.toIso8601String(),
      'summary': {
        'native_status': 'S',
        'category': 'order_status_no_records',
        'record_count': 0,
        'valid_count': 0,
        'invalid_count': 0,
        'other_count': 0
      },
    };

class FakeTimer implements Timer {
  FakeTimer(this.callback);
  final void Function() callback;
  bool active = true;
  void fire() {
    if (active) {
      active = false;
      callback();
    }
  }

  @override
  void cancel() => active = false;
  @override
  bool get isActive => active;
  @override
  int get tick => 0;
}

class FakeRepository implements NseReadRepository {
  String acceptedId = opId;
  NseFailure? submitFailure, queryFailure;
  bool loseAcceptance = false;
  int submits = 0, queries = 0;
  final List<String> requestIds = [];
  final List<Map<String, dynamic>> commands = [];
  Completer<NseAcceptance>? submitWait;
  Completer<NseReadContext>? contextWait;
  Completer<NseOperation>? operationWait;
  NseOperation current = snapshot();
  List<NseTarget> availableTargets = [
    const NseTarget(targetId, 'Synthetic client', 'Workspace')
  ];
  NseReadContext readContext =
      const NseReadContext(targetId, 'REGISTERED', 'CONFIRMED', true, [
    NseCapability(NseReadKind.orderStatus, true, null),
    NseCapability(NseReadKind.allotmentStatement, false,
        'POSITIVE_OWNED_ORDER_EVIDENCE_REQUIRED'),
  ]);
  @override
  Future<NsePage<NseTarget>> targets({String? after}) async =>
      NsePage(availableTargets, null);
  @override
  Future<NseReadContext> context(String target) async {
    if (queryFailure != null) throw queryFailure!;
    if (contextWait != null) return contextWait!.future;
    return readContext;
  }

  @override
  Future<NseAcceptance> submit(
      String target, String id, NseReadCommand command) async {
    submits++;
    requestIds.add(id);
    commands.add(command.toJson());
    if (submitFailure != null) throw submitFailure!;
    if (loseAcceptance) {
      loseAcceptance = false;
      throw const NseFailure('NETWORK');
    }
    if (submitWait != null) return submitWait!.future;
    return NseAcceptance(id, acceptedId);
  }

  @override
  Future<NseOperation> operation(
      {String? operationId, String? requestId}) async {
    queries++;
    if (queryFailure != null) throw queryFailure!;
    if (operationWait != null) return operationWait!.future;
    return current;
  }

  @override
  Future<NsePage<NseOperation>> history(String target,
          {Object? cursor}) async =>
      NsePage([current], null);
  @override
  Future<NsePage<NseCandidate>> candidates(
          String target, NseReadKind kind, String source,
          {int after = -1}) async =>
      const NsePage([NseCandidate(0, true), NseCandidate(1, false)], null);
}

void main() {
  late FakeRepository repo;
  late NsePendingStorage storage;
  late List<FakeTimer> timers;
  late List<Duration> delays;
  late DateTime now;
  NseIntegrationController controller() => NseIntegrationController(
      repository: repo,
      storage: storage,
      uuid: () => requestId,
      now: () => now,
      jitter: () => .5,
      timerFactory: (duration, callback) {
        delays.add(duration);
        final t = FakeTimer(callback);
        timers.add(t);
        return t;
      });
  setUp(() {
    repo = FakeRepository();
    storage = NsePendingStorage('test-user')..clear();
    timers = [];
    delays = [];
    now = created;
  });
  test('console requires explicit DEV build flags',
      () => expect(NseConsoleAccess.enabled, false));
  test('all 25 commands round-trip without provider identifiers', () {
    expect(NseReadKind.values.length, 25);
    for (final kind in NseReadKind.values) {
      expect(NseReadKind.parse(kind.wire), kind);
    }
    expect(NseReadCommand.fromJson(command().toJson()).toJson(),
        command().toJson());
    expect(() => NseReadKind.parse('read_normal'), throwsFormatException);
  });
  test('operation DTO rejects unknown state and inconsistent terminal flag',
      () {
    expect(
        () => NseOperation.fromJson(
            {...operationJson(), 'display_status': 'RAW_PROVIDER_STATUS'}),
        throwsFormatException);
    expect(() => NseOperation.fromJson({...operationJson(), 'terminal': false}),
        throwsFormatException);
    final dto = NseOperation.fromJson(operationJson());
    expect(dto.summary!.recordCount, 0);
  });
  test('repository uses fixed RPC and checks request correlation', () async {
    final rpc = SupabaseNseReadRepository.withRpc((name, params) async {
      expect(name, 'submit_nse_read_v1');
      expect(params.keys,
          containsAll(['p_target_ref', 'p_request_id', 'p_command']));
      expect(params.toString(), isNot(contains('integration_account_id')));
      return {
        'schema_version': 1,
        'data': {
          'acceptance': 'ACCEPTED',
          'request_id': opId,
          'operation_id': opId
        }
      };
    });
    await expectLater(
        rpc.submit(targetId, requestId, command()),
        throwsA(isA<NseFailure>()
            .having((x) => x.code, 'code', 'INVALID_RESPONSE')));
  });
  test('unknown schema and raw SQL errors become safe failures', () async {
    for (final response in [
      {'schema_version': 2, 'data': operationJson()},
      {
        'schema_version': 1,
        'error': {'code': 'PRIVATE_SQL_SECRET'}
      }
    ]) {
      final rpc = SupabaseNseReadRepository.withRpc((_, __) async => response);
      try {
        await rpc.operation(operationId: opId);
        fail('must reject');
      } on NseFailure catch (e) {
        expect(e.message, isNot(contains('PRIVATE')));
      }
    }
    final rpc = SupabaseNseReadRepository.withRpc(
        (_, __) async => throw StateError('PRIVATE_PROVIDER_DIAGNOSTIC'));
    await expectLater(
        rpc.operation(operationId: opId),
        throwsA(isA<NseFailure>().having(
            (x) => x.message, 'safe message', isNot(contains('PRIVATE')))));
  });
  test('double press invokes once', () async {
    final c = controller();
    await c.start();
    repo.submitWait = Completer<NseAcceptance>();
    final first = c.submit(command());
    await c.submit(command());
    expect(repo.submits, 1);
    repo.submitWait!.complete(const NseAcceptance(requestId, opId));
    await first;
    expect(c.hasUnconfirmedRequest, false);
    c.dispose();
  });
  test('restored operation cannot appear under a different selected client',
      () async {
    final c = controller();
    await c.start();
    repo.current = snapshot(target: 'aa030000-0000-4000-8000-000000000005');
    await c.selectOperation(opId);
    expect(c.phase, NseConsolePhase.accessDenied);
    expect(c.operation, isNull);
    expect(timers.where((timer) => timer.isActive), isEmpty);
    c.dispose();
  });
  test('lost acceptance retains UUID; retry reuses exactly the same command',
      () async {
    final c = controller();
    await c.start();
    repo.loseAcceptance = true;
    await c.submit(command());
    expect(c.hasUnconfirmedRequest, true);
    expect(storage.read(), isNotNull);
    await c.retryPending();
    expect(repo.requestIds, [requestId, requestId]);
    expect(repo.commands[0], repo.commands[1]);
    expect(c.operation!.id, opId);
    expect(storage.read(), isNull);
    c.dispose();
  });
  test('acceptance during an older poll reliably starts a fresh watch',
      () async {
    final c = controller();
    await c.start(initialOperation: opId);
    final olderPoll = Completer<NseOperation>();
    const newId = 'aa060000-0000-4000-8000-000000000002';
    repo.acceptedId = newId;
    repo.operationWait = olderPoll;
    final refresh = c.refresh(automatic: true);
    final submit = c.submit(command());
    await Future<void>.delayed(Duration.zero);
    expect(c.isSubmitting, true);
    repo.operationWait = null;
    repo.current =
        snapshot(status: NseDisplayStatus.running, operationId: newId);
    olderPoll.complete(snapshot(status: NseDisplayStatus.success));
    await Future.wait([refresh, submit]);
    expect(c.operation!.status, NseDisplayStatus.running);
    expect(c.operation!.id, newId);
    expect(c.history.single.status, NseDisplayStatus.running);
    expect(timers.where((timer) => timer.isActive), hasLength(1));
    c.dispose();
  });
  test('rejected new read does not stop watching an earlier accepted read',
      () async {
    final c = controller();
    await c.start(initialOperation: opId);
    repo.submitFailure = const NseFailure('INVALID_COMMAND');
    await c.submit(command());
    expect(c.hasUnconfirmedRequest, false);
    expect(c.operation!.id, opId);
    expect(timers.where((timer) => timer.isActive), hasLength(1));
    c.dispose();
  });
  test('refresh recovers pending request without resubmitting', () async {
    storage.write(NsePendingRequest(targetId, requestId, command()).encode());
    final c = controller();
    await c.start();
    expect(repo.submits, 0);
    expect(c.operation!.id, opId);
    expect(c.hasUnconfirmedRequest, false);
    c.dispose();
  });
  test('definite rejection clears pending receipt and never retries transport',
      () async {
    final c = controller();
    await c.start();
    repo.submitFailure = const NseFailure('BLOCKED_PREREQUISITE');
    await c.submit(command());
    expect(c.hasUnconfirmedRequest, false);
    expect(storage.read(), isNull);
    expect(repo.submits, 1);
    c.dispose();
  });
  test('polling backs off and backend retry stays pending', () async {
    final c = controller();
    await c.start();
    await c.submit(command());
    expect(delays.last, const Duration(seconds: 2));
    repo.current = snapshot(status: NseDisplayStatus.retryPending);
    timers.last.fire();
    await Future<void>.delayed(Duration.zero);
    expect(c.operation!.terminal, false);
    expect(delays.last, const Duration(seconds: 4));
    timers.last.fire();
    await Future<void>.delayed(Duration.zero);
    expect(delays.last, const Duration(seconds: 8));
    repo.current = snapshot(status: NseDisplayStatus.success);
    timers.last.fire();
    await Future<void>.delayed(Duration.zero);
    expect(c.operation!.terminal, true);
    expect(timers.where((t) => t.active), isEmpty);
    expect(repo.submits, 1);
    c.dispose();
  });
  test('10-minute pause does not manufacture terminal failure', () async {
    final c = controller();
    await c.start();
    await c.submit(command());
    now = created.add(const Duration(minutes: 11));
    timers.last.fire();
    await Future<void>.delayed(Duration.zero);
    expect(c.pollingPaused, true);
    expect(c.operation!.terminal, false);
    expect(c.takingLonger, true);
    c.dispose();
  });
  test('background/dispose stop timers and reconnect only queries', () async {
    final c = controller();
    await c.start();
    await c.submit(command());
    c.setVisible(false);
    expect(timers.where((t) => t.active), isEmpty);
    c.setVisible(true);
    await Future<void>.delayed(Duration.zero);
    expect(repo.submits, 1);
    c.dispose();
    expect(timers.where((t) => t.active), isEmpty);
  });
  test('network failure retains last status; authorization failure clears it',
      () async {
    final c = controller();
    await c.start();
    await c.submit(command());
    repo.queryFailure = const NseFailure('NETWORK');
    await c.refresh(automatic: true);
    expect(c.operation, isNotNull);
    expect(c.failure, isNotNull);
    repo.queryFailure = const NseFailure('TARGET_UNAVAILABLE');
    await c.refresh(automatic: true);
    expect(c.operation, isNull);
    expect(c.history, isEmpty);
    c.dispose();
  });
  test('stale refresh cannot repopulate a signed-out session', () async {
    final c = controller();
    await c.start();
    repo.contextWait = Completer<NseReadContext>();
    final refreshing = c.refresh();
    c.clearSession();
    repo.contextWait!.complete(repo.readContext);
    await refreshing;
    expect(c.context, isNull);
    expect(c.phase, NseConsolePhase.accessDenied);
    c.dispose();
  });
  for (final width in [320.0, 1100.0]) {
    testWidgets('console fits width $width at large text scale in dark mode',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = controller();
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (_, child) => MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 900),
                  textScaler: const TextScaler.linear(1.8)),
              child: child!),
          home: NseIntegrationPage(controller: c)));
      await tester.pumpAndSettle();
      expect(find.text('NSE Integration'), findsOneWidget);
      expect(find.textContaining('DEV / UAT'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('ALLOTMENT_STATEMENT'), 200);
      expect(find.textContaining('Positive owned'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  testWidgets('success card shows safe counts and blocked reads cannot run',
      (tester) async {
    repo.current = snapshot(status: NseDisplayStatus.success);
    final c = controller();
    await tester.pumpWidget(MaterialApp(
        home: NseIntegrationPage(controller: c, initialOperation: opId)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Select owned order evidence'), 150);
    final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Select owned order evidence'));
    expect(button.onPressed, isNull);
    await tester.scrollUntilVisible(find.text('Record count: 0'), 150);
    expect(find.text('Native status: S'), findsOneWidget);
    expect(find.textContaining('PRIVATE_'), findsNothing);
    expect(repo.submits, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
