import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/presentation/onboarding_screens.dart';
import 'route_guard_test.dart' show FakeAuthProvider;

class ExplorerAuth extends FakeAuthProvider {
  int linkingRequests = 0;
  @override
  Future<void> beginPortfolioLinking() async {
    linkingRequests++;
  }
}

void main() {
  testWidgets('profile-free Explorer can enter existing portfolio linking',
      (tester) async {
    final auth = ExplorerAuth();
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth, child: const MaterialApp(home: ExplorerHomeScreen())));
    expect(auth.userProfile, isNull);
    await tester.tap(find.text('Link existing investments'));
    await tester.pump();
    expect(auth.linkingRequests, 1);
    expect(tester.takeException(), isNull);
  });
}
