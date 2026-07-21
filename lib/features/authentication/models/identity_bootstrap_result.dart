import '../../investor_identity/models/user_account.dart';

enum IdentityResolution {
  advisor,
  existingLink,
  automaticLink,
  noMatch,
  ambiguousMatch,
  explorerChoice,
  verificationPending;

  static IdentityResolution fromDatabase(String value) {
    switch (value) {
      case 'advisor':
        return IdentityResolution.advisor;
      case 'existing_link':
        return IdentityResolution.existingLink;
      case 'automatic_link':
        return IdentityResolution.automaticLink;
      case 'no_match':
        return IdentityResolution.noMatch;
      case 'ambiguous_match':
        return IdentityResolution.ambiguousMatch;
      case 'explorer_choice':
        return IdentityResolution.explorerChoice;
      case 'verification_pending':
        return IdentityResolution.verificationPending;
      default:
        throw ArgumentError.value(
            value, 'value', 'Unknown identity resolution');
    }
  }
}

class IdentityBootstrapResult {
  const IdentityBootstrapResult({
    required this.account,
    required this.resolution,
  });

  final UserAccount account;
  final IdentityResolution resolution;
}
