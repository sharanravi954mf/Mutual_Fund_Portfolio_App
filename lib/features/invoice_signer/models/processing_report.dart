import '../processors/registrar_processor.dart';
import 'registrar_detection_result.dart';

/// User-facing summary of an Invoice Signer job.
///
/// Detection diagnostics stay within [detection]; the dashboard converts this
/// report into clear, business-friendly status messages.
class ProcessingReport {
  final RegistrarDetectionResult detection;
  final int invoicesSigned;
  final int trackerRowsUpdated;
  final int unmatchedInvoices;
  final List<String> warnings;
  final List<String> errors;

  const ProcessingReport({
    required this.detection,
    required this.invoicesSigned,
    required this.trackerRowsUpdated,
    required this.unmatchedInvoices,
    this.warnings = const [],
    this.errors = const [],
  });

  String get invoiceSourceLabel => switch (detection.registrar) {
        RegistrarType.cams => 'CAMS',
        RegistrarType.kfintech => 'KFintech',
        null => 'Unconfirmed',
      };
}
