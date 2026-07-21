import '../../investor_identity/models/user_account.dart';
import '../models/identity_bootstrap_result.dart';

abstract class IdentityRepository {
  Future<IdentityBootstrapResult> bootstrap();

  Future<UserAccount> completeOnboardingChoice(AccountState accountState);
}
