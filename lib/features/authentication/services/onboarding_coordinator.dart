import '../../investor_identity/models/user_account.dart';
import '../data/identity_repository.dart';
import 'identity_verification_service.dart';

class OnboardingCoordinator {
  const OnboardingCoordinator({
    required IdentityRepository repository,
    required IdentityVerificationService verificationService,
  })  : _repository = repository,
        _verificationService = verificationService;

  final IdentityRepository _repository;
  final IdentityVerificationService _verificationService;

  Future<UserAccount> chooseExplorer() {
    return _repository.completeOnboardingChoice(AccountState.explorer);
  }

  Future<UserAccount> choosePortfolioLinking() {
    return _repository.completeOnboardingChoice(AccountState.linkPending);
  }

  List<VerificationMethodDescriptor> verificationMethods() {
    return _verificationService.supportedMethods();
  }
}
