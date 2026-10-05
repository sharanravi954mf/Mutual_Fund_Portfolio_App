import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mutual_fund_portfolio_app/providers/auth_provider.dart';
import 'package:mutual_fund_portfolio_app/features/authentication/presentation/onboarding_screens.dart';
import 'package:mutual_fund_portfolio_app/features/calculators/presentation/calculators_home_screen.dart';
import 'route_guard_test.dart' show FakeAuthProvider;

class ExplorerAuth extends FakeAuthProvider {
  int linkingRequests = 0;
  int signOutRequests = 0;
  @override
  Future<void> signOut() async {
    signOutRequests++;
  }

  @override
  Future<void> beginPortfolioLinking() async {
    linkingRequests++;
  }
}

void main() {
  testWidgets('Calculators opens hub and back restores Explorer',
      (tester) async {
    final auth = ExplorerAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth, child: const MaterialApp(home: ExplorerHomeScreen())));
    expect(find.text('Calculators'), findsOneWidget);
    expect(find.text('Plan and compare investments'), findsOneWidget);
    await tester.ensureVisible(find.text('Calculators'));
    await tester.tap(find.text('Calculators'));
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorsHomeScreen), findsOneWidget);
    expect(find.byType(ExplorerModuleScreen), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ExplorerHomeScreen), findsOneWidget);
  });

  for (final title in [
    'Factsheets',
    'Fund Search',
    'Learn',
    'Contact Advisor',
    'Settings & Profile'
  ]) {
    testWidgets('$title retains its original module destination',
        (tester) async {
      final auth = ExplorerAuth();
      addTearDown(auth.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
          value: auth, child: const MaterialApp(home: ExplorerHomeScreen())));
      await tester.ensureVisible(find.text(title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ExplorerModuleScreen>(find.byType(ExplorerModuleScreen))
              .title,
          title);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ExplorerHomeScreen), findsOneWidget);
    });
  }

  testWidgets('Explorer sign out stays wired to auth', (tester) async {
    final auth = ExplorerAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth, child: const MaterialApp(home: ExplorerHomeScreen())));
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(auth.signOutRequests, 1);
  });

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
