import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../data/investor_onboarding_repository.dart';
import 'investor_onboarding_controller.dart';
import 'investor_onboarding_page.dart';

class InvestorOnboardingEntry extends StatelessWidget {
  const InvestorOnboardingEntry({this.startNew = true, super.key});
  final bool startNew;
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isAuthenticated) {
      return const Scaffold(body: Center(child: Text('Sign in to continue.')));
    }
    return ChangeNotifierProvider(
      key: ValueKey(auth.user!.id),
      create: (_) => InvestorOnboardingController(
          SupabaseInvestorOnboardingRepository(auth.client)),
      child: Builder(
          builder: (context) => InvestorOnboardingPage(
              startNew: startNew,
              controller: context.read<InvestorOnboardingController>())),
    );
  }
}
