import '../../investor_identity/models/user_account.dart';

enum IdentityResolution {
  reconciliationRequired,
  verifiedContactsRequired,
  platformContext,
  advisor,
  existingLink,
  automaticLink,
  noMatch,
  ambiguousMatch,
  explorerChoice,
  verificationPending;

  static IdentityResolution fromDatabase(String value) {
    switch (value) {
      case 'verified_contacts_required':
        return IdentityResolution.verifiedContactsRequired;
      case 'identity_reconciliation_required':
        return IdentityResolution.reconciliationRequired;
      case 'platform_context':
        return IdentityResolution.platformContext;
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
