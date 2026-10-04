import 'dart:async';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/mfa_models.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/mfa/mfa_repository.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/models/platform_context.dart';

const syntheticSecret = 'JBSWY3DPEHPK3PXP';
const syntheticUri =
    'otpauth://totp/MoneyBowl%20DEV:synthetic%40example.test?secret=$syntheticSecret&issuer=MoneyBowl%20DEV';
const pendingFactor =
    MfaFactor(id: 'pending-1', kind: MfaFactorKind.totp, verified: false);
const verifiedFactor =
    MfaFactor(id: 'verified-1', kind: MfaFactorKind.totp, verified: true);
const reviewContext = PlatformContext(
    isPlatformAdmin: true, capabilities: {'mfd_applications.review'});

class FakeMfaRepository implements MfaRepository {
  @override
  final operations = MfaOperationSlot();
  @override
  String? userId = 'user-id';
  @override
  int accountGeneration = 0;
  @override
  String get accountLabel => 'synthetic@example.test';
  @override
  String get issuer => 'MoneyBowl DEV';
  @override
  DateTime? retryNotBefore;
  List<MfaFactor> factors = [];
  bool aal2 = false;
  PlatformContext platform = reviewContext;
  int inspections = 0, enrollments = 0, verifications = 0;
  String? lastFactor, lastCode;
  Object? inspectError, enrollError, verifyError;
  Completer<void>? wait;
  void Function()? onVerified;
  @override
  Future<MfaStatus> inspect() async {
    inspections++;
    if (inspectError != null) throw inspectError!;
    return MfaStatus(factors: List.of(factors), aal2: aal2, platform: platform);
  }

  @override
  Future<MfaSetup> enroll() async {
    enrollments++;
    final factorId = factors.any((f) => f.id == 'pending-1')
        ? 'pending-new-$enrollments'
        : 'pending-1';
    factors = [
      ...factors,
      MfaFactor(id: factorId, kind: MfaFactorKind.totp, verified: false)
    ];
    if (wait != null) await wait!.future;
    if (enrollError != null) throw enrollError!;
    return MfaSetup(
        factorId: factorId, secret: syntheticSecret, uri: syntheticUri);
  }

  @override
  Future<void> verify(String factorId, String code) async {
    verifications++;
    lastFactor = factorId;
    lastCode = code;
    if (wait != null) await wait!.future;
    if (verifyError != null) throw verifyError!;
    factors = factors
        .map((f) => f.id == factorId
            ? MfaFactor(id: f.id, kind: f.kind, verified: true)
            : f)
        .toList();
    aal2 = true;
    platform = const PlatformContext(
        isPlatformAdmin: true,
        capabilities: {'mfd_applications.review'},
        stepUpVerified: true,
        mfaEnrolled: true);
    onVerified?.call();
  }
}
