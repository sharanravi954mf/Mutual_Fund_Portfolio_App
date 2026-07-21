import '../processors/registrar_processor.dart';

enum RegistrarDetectionStatus { unknown, candidate, confirmed }

/// Internal outcome of staged registrar detection.
///
/// This is deliberately separate from the user-facing processing report. The
/// [reason] field is for diagnostics and must not be shown directly in the
/// normal workflow.
class RegistrarDetectionResult {
  final RegistrarType? registrar;
  final RegistrarDetectionStatus status;
  final int trackerRows;
  final int invoicesFound;
  final String reason;

  const RegistrarDetectionResult({
    required this.registrar,
    required this.status,
    required this.trackerRows,
    required this.invoicesFound,
    required this.reason,
  });

  const RegistrarDetectionResult.unknown({
    this.trackerRows = 0,
    this.invoicesFound = 0,
    required this.reason,
  })  : registrar = null,
        status = RegistrarDetectionStatus.unknown;

  bool get isConfirmed => status == RegistrarDetectionStatus.confirmed;
}
