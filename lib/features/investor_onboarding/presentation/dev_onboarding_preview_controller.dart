import 'package:flutter/foundation.dart';

/// UI-only state. It has no repository, investor identifier, or serialization.
enum DevPreviewStep {
  personal,
  address,
  nominee,
  fatca,
  bank,
  review,
  complete,
}

class DevOnboardingPreviewController extends ChangeNotifier {
  DevPreviewStep step = DevPreviewStep.personal;
  String demoName = 'Demo Investor';
  String demoEmail = 'demo@example.test';
  String dateOfBirth = '';
  String occupation = '';
  String addressLine = '';
  String city = '';
  String postalCode = '';
  String country = '';
  bool? hasNominee;
  String nomineeName = '';
  String nomineeRelationship = '';
  bool? taxResidentInIndia;
  String otherTaxCountry = '';
  String accountType = '';
  bool previewAcknowledged = false;
  String? error;

  void changed() {
    error = null;
    notifyListeners();
  }

  bool advance() {
    switch (step) {
      case DevPreviewStep.nominee:
        if (hasNominee == null) {
          error = 'Choose Yes or No to continue.';
        }
        break;
      case DevPreviewStep.fatca:
        if (taxResidentInIndia == null) {
          error = 'Choose a tax residency answer to continue.';
        }
        break;
      case DevPreviewStep.review:
        if (!previewAcknowledged) {
          error = 'Acknowledge that this is only a preview.';
        }
        break;
      default:
        break;
    }
    if (error != null) {
      notifyListeners();
      return false;
    }
    if (step != DevPreviewStep.complete) {
      step = DevPreviewStep.values[step.index + 1];
      notifyListeners();
    }
    return true;
  }

  void back() {
    if (step.index == 0) return;
    error = null;
    step = DevPreviewStep.values[step.index - 1];
    notifyListeners();
  }

  @override
  void dispose() {
    // The only copy of editable values dies with the preview route.
    demoName = '';
    demoEmail = '';
    dateOfBirth = '';
    occupation = '';
    addressLine = '';
    city = '';
    postalCode = '';
    country = '';
    nomineeName = '';
    nomineeRelationship = '';
    otherTaxCountry = '';
    accountType = '';
    hasNominee = null;
    taxResidentInIndia = null;
    previewAcknowledged = false;
    error = null;
    super.dispose();
  }
}
