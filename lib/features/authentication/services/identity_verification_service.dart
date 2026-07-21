enum VerificationMethod {
  pan,
  folio,
  advisorAssisted;
}

class VerificationMethodDescriptor {
  const VerificationMethodDescriptor({
    required this.method,
    required this.label,
    required this.available,
  });

  final VerificationMethod method;
  final String label;
  final bool available;
}

abstract class IdentityVerificationService {
  List<VerificationMethodDescriptor> supportedMethods();
}

class PlaceholderIdentityVerificationService
    implements IdentityVerificationService {
  const PlaceholderIdentityVerificationService();

  @override
  List<VerificationMethodDescriptor> supportedMethods() {
    return const [
      VerificationMethodDescriptor(
        method: VerificationMethod.pan,
        label: 'PAN verification',
        available: false,
      ),
      VerificationMethodDescriptor(
        method: VerificationMethod.folio,
        label: 'Folio number verification',
        available: false,
      ),
      VerificationMethodDescriptor(
        method: VerificationMethod.advisorAssisted,
        label: 'Advisor-assisted verification',
        available: false,
      ),
    ];
  }
}
