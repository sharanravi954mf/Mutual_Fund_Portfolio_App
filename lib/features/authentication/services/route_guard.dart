import 'package:flutter/material.dart';
import '../../investor_identity/models/user_account.dart';
import '../../investor_identity/models/user_profile.dart';
import '../../../providers/auth_provider.dart';
import 'account_state_resolver.dart';

class RouteGuard {
  const RouteGuard({
    required this.loginBuilder,
    required this.loadingBuilder,
    required this.errorBuilder,
    required this.advisorBuilder,
    required this.investorBuilder,
    required this.explorerBuilder,
    required this.linkingBuilder,
  });

  final WidgetBuilder loginBuilder;
  final WidgetBuilder loadingBuilder;
  final Widget Function(String title, String message) errorBuilder;
  final WidgetBuilder advisorBuilder;
  final WidgetBuilder investorBuilder;
  final WidgetBuilder explorerBuilder;
  final WidgetBuilder linkingBuilder;

  /// Evaluates authentication state and roles to resolve the correct screen.
  Widget resolve(BuildContext context, AuthProvider authProvider) {
    // 1. Session Loading state check
    if (authProvider.isLoading) {
      return loadingBuilder(context);
    }

    // 2. Unauthenticated check
    if (!authProvider.isAuthenticated) {
      return loginBuilder(context);
    }

    // 3. UserAccount state availability check
    final AccountState? accountState = authProvider.accountState;
    if (accountState == null) {
      return errorBuilder(
        "Account Setup Unavailable",
        "Your account is authenticated, but its secure account state could not be loaded.",
      );
    }

    // 4. UserProfile availability check
    final UserProfile? profile = authProvider.userProfile;
    if (profile == null) {
      return errorBuilder(
        "Profile Setup Unavailable",
        "Your profile details are currently being initialized. Please contact support if this persists.",
      );
    }

    // 5. Account status restrictions (Inactive/Suspended check)
    if (profile.isSuspended) {
      return errorBuilder(
        "Account Suspended",
        "Your account has been suspended by Sharan Fincorp. Please contact support.",
      );
    }

    if (profile.isInactive) {
      return errorBuilder(
        "Account Inactive",
        "Your account is currently inactive. Please contact support.",
      );
    }

    // 6. Strongly-typed destination and role authorization checks
    final destination = const AccountStateResolver().resolve(accountState);

    switch (destination) {
      case ProtectedDestination.advisorDashboard:
        if (!profile.isAuthorizedForAdvisorDashboard) {
          return errorBuilder(
            "Access Denied",
            "You do not have authorization to access the Advisor Dashboard.",
          );
        }
        return advisorBuilder(context);

      case ProtectedDestination.investorDashboard:
        if (!profile.isAuthorizedForInvestorDashboard) {
          return errorBuilder(
            "Access Denied",
            "You do not have authorization to access the Investor Dashboard.",
          );
        }
        return investorBuilder(context);

      case ProtectedDestination.explorer:
        return explorerBuilder(context);

      case ProtectedDestination.portfolioLinking:
        return linkingBuilder(context);
    }
  }
}
