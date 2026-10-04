import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/models/platform_context.dart';
import 'package:mutual_fund_portfolio_app/features/platform_administration/presentation/platform_administration_screen.dart';
import 'authentication/route_guard_test.dart' show FakeAuthProvider;

void main() {
  for (final mfa in [false, true]) {
    testWidgets(
        'read-only platform shell works without business profile (MFA $mfa)',
        (tester) async {
      final auth = FakeAuthProvider(
          isAuthenticated: true,
          platformContext: PlatformContext(
              isPlatformAdmin: true,
              capabilities: const {'mfd_applications.review'},
              mfaEnrolled: mfa,
              stepUpVerified: mfa));
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: const MaterialApp(home: PlatformAdministrationScreen())));
      expect(find.text('MoneyBowl Platform Administration'), findsOneWidget);
      expect(find.textContaining('coming in the next phase'), findsOneWidget);
      expect(
          find.text(mfa
              ? 'MFA verified for this session.'
              : 'Enroll and verify MFA before sensitive platform actions.'),
          findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Advisor Dashboard'), findsNothing);
      auth.updatePlatformContext(const PlatformContext());
      await tester.pump();
      expect(find.text('Platform access unavailable'), findsOneWidget);
      auth.dispose();
    });
  }
}
