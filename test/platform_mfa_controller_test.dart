import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/mfa_controller.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/mfa_models.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/mfa_repository.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/models/platform_context.dart';
import 'support/platform_mfa_fakes.dart';

void main() {
  late FakeMfaRepository repo;
  late MfaController c;
  setUp(() {
    repo = FakeMfaRepository();
    c = MfaController(repo);
  });
  tearDown(() => c.dispose());
  test('entry and repeated refresh never enroll; unknown is not empty',
      () async {
    await c.refresh();
    await c.refresh();
    expect(repo.enrollments, 0);
    expect(c.canEnroll, true);
    repo.inspectError = const MfaFailure(MfaError.uncertain);
    await c.refresh();
    expect(c.status, null);
    expect(c.canEnroll, false);
  });
  test('double tap and route recreation share one pending operation', () async {
    await c.refresh();
    repo.wait = Completer();
    final first = c.enroll();
    await Future<void>.delayed(Duration.zero);
    await c.enroll();
    final other = MfaController(repo);
    await other.refresh();
    expect(repo.enrollments, 1);
    expect(other.canAct, false);
    c.cancel();
    repo.wait!.complete();
    await first;
    expect(c.setup, null);
    expect(c.phase, MfaPhase.unavailable);
    await other.refresh();
    expect(other.status!.totp.single.verified, false);
    expect(repo.enrollments, 1);
    other.dispose();
  });
  test('fresh discovered verified factor stops explicit enrollment', () async {
    await c.refresh();
    repo.factors = [verifiedFactor];
    await c.enroll();
    expect(repo.enrollments, 0);
    expect(c.canEnroll, false);
  });
  test('multiple factors require explicit selection and preserve leading zeros',
      () async {
    repo.factors = [
      verifiedFactor,
      const MfaFactor(id: 'two', kind: MfaFactorKind.totp, verified: true)
    ];
    await c.refresh();
    expect(c.selectedId, null);
    c.select('two');
    await c.verify('001234');
    expect(repo.lastFactor, 'two');
    expect(repo.lastCode, '001234');
    expect(repo.enrollments, 0);
    expect(c.confirmed, true);
  });
  for (final code in ['', '12345', '1234567', '12 456', '１２３４５６', '12a456']) {
    test('malformed input $code never verifies', () async {
      repo.factors = [verifiedFactor];
      await c.refresh();
      await c.verify(code);
      expect(repo.verifications, 0);
    });
  }
  test('pending factor can be finished after reload without a recovered secret',
      () async {
    repo.factors = [pendingFactor];
    await c.refresh();
    expect(c.setup, null);
    await c.enroll();
    expect(repo.enrollments, 0);
    await c.verify('001234');
    expect(c.confirmed, true);
    expect(repo.enrollments, 0);
  });
  test('restart requires acknowledgement and never removes pending factors',
      () async {
    repo.factors = [pendingFactor];
    await c.refresh();
    await c.enroll();
    expect(repo.enrollments, 0);
    await c.enroll(restartAcknowledged: true);
    expect(repo.enrollments, 1);
    expect(repo.factors.length, 2);
  });
  test('unsupported-only factors fail closed even when unverified', () async {
    repo.factors = [
      const MfaFactor(
          id: 'phone', kind: MfaFactorKind.unsupported, verified: false)
    ];
    await c.refresh();
    expect(c.error, MfaError.unsupported);
    await c.enroll();
    expect(repo.enrollments, 0);
    expect(c.canVerify, false);
  });
  test('enrollment alone does not confirm and diagnostics redact setup',
      () async {
    await c.refresh();
    await c.enroll();
    expect(c.confirmed, false);
    expect(c.setup.toString(), 'MfaSetup(redacted)');
    expect(c.toString(), isNot(contains(syntheticSecret)));
  });
  for (final error in [
    MfaError.invalidCode,
    MfaError.expired,
    MfaError.rateLimited,
    MfaError.disabled,
    MfaError.uncertain,
    MfaError.factorLimit
  ]) {
    test('$error has no mutation retry or reenrollment', () async {
      repo.factors = [verifiedFactor];
      repo.verifyError = MfaFailure(error);
      await c.refresh();
      await c.verify('001234');
      expect(repo.verifications, 1);
      expect(repo.enrollments, 0);
      expect(c.confirmed, false);
      expect(c.error, error);
      expect(repo.inspections, lessThanOrEqualTo(3));
    });
  }
  test('uncertain enrollment reconciles the pending server factor exactly once',
      () async {
    repo.enrollError = TimeoutException('synthetic');
    await c.refresh();
    await c.enroll();
    expect(repo.enrollments, 1);
    expect(repo.inspections, 3);
    expect(c.status!.totp.single.verified, false);
    expect(c.setup, null);
  });
  test('server confirmation disagreement and revoked grant never succeed',
      () async {
    repo.factors = [verifiedFactor];
    repo.aal2 = true;
    await c.refresh();
    expect(c.error, MfaError.contextMismatch);
    expect(c.confirmed, false);
    repo.platform = const PlatformContext();
    await c.refresh();
    expect(c.phase, MfaPhase.unavailable);
    expect(c.canEnroll, false);
  });
  test('background obscures and resume waits for the existing operation',
      () async {
    await c.refresh();
    await c.enroll();
    c.suspend();
    expect(c.canAct, false);
    expect(c.setup, isNotNull);
    await c.resume();
    expect(repo.enrollments, 1);
    repo.wait = Completer();
    final pending = c.verify('001234');
    await Future<void>.delayed(Duration.zero);
    c.suspend();
    final before = repo.inspections;
    await c.resume();
    expect(repo.inspections, before);
    repo.wait!.complete();
    await pending;
    expect(c.confirmed, true);
  });
  test('account change clears setup and rejects late completion', () async {
    await c.refresh();
    repo.wait = Completer();
    final pending = c.enroll();
    await Future<void>.delayed(Duration.zero);
    repo.userId = 'B';
    repo.accountGeneration++;
    c.invalidateAccount();
    repo.wait!.complete();
    await pending;
    expect(c.setup, null);
    expect(c.confirmed, false);
    expect(c.canAct, false);
  });
  test('server retry guidance disables all retries without timer polling',
      () async {
    repo.factors = [verifiedFactor];
    await c.refresh();
    repo.retryNotBefore = DateTime.now().add(const Duration(minutes: 1));
    await c.verify('001234');
    await c.refresh();
    expect(repo.verifications, 0);
    expect(repo.inspections, 1);
  });
  test(
      'setup URI validation rejects remote/ambiguous/unsupported configuration',
      () {
    expect(
        validTotpSetup(syntheticUri, syntheticSecret, 'MoneyBowl DEV'), true);
    for (final bad in [
      'https://external.invalid/qr',
      '$syntheticUri&secret=$syntheticSecret',
      '$syntheticUri&digits=8',
      '$syntheticUri&algorithm=SHA256',
      '$syntheticUri#fragment'
    ]) {
      expect(validTotpSetup(bad, syntheticSecret, 'MoneyBowl DEV'), false);
    }
  });
}
