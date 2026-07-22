import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/application/folio_verification_service.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/folio_verification_controller.dart';
import 'package:mutual_fund_portfolio_app/features/investor_verification/presentation/folio_verification_providers.dart';
import 'support/folio_verification_fakes.dart';

void main() {
  testWidgets('wires an injected service without cross-provider state',
      (tester) async {
    final a = FolioTestRepository(), b = FolioTestRepository();
    FolioVerificationController? first;
    await tester.pumpWidget(KeyedSubtree(
        key: const ValueKey('first-provider'),
        child: MultiProvider(
            providers: [
              FolioVerificationProviders.controller(
                  service: FolioVerificationService(a, a))
            ],
            child: Builder(builder: (context) {
              first = context.read<FolioVerificationController>();
              return const SizedBox();
            }))));
    await first!.refresh();
    expect(a.refreshCalls, 1);
    FolioVerificationController? second;
    await tester.pumpWidget(KeyedSubtree(
        key: const ValueKey('second-provider'),
        child: MultiProvider(
            providers: [
              FolioVerificationProviders.controller(
                  service: FolioVerificationService(b, b))
            ],
            child: Builder(builder: (context) {
              second = context.read<FolioVerificationController>();
              return const SizedBox();
            }))));
    await second!.refresh();
    expect(b.refreshCalls, 1);
    expect(a.refreshCalls, 1);
  });
}
