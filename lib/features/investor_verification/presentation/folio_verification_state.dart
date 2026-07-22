import 'package:flutter/foundation.dart';

import '../application/folio_verification_service.dart';
import '../models/folio_verification_models.dart';
import 'folio_verification_presentation_models.dart';

sealed class FolioVerificationState {
  const FolioVerificationState();
}

class FolioVerificationIdle extends FolioVerificationState {
  const FolioVerificationIdle();
}

class FolioVerificationLoading extends FolioVerificationState {
  const FolioVerificationLoading({this.previous});
  final FolioVerificationState? previous;
}

class FolioVerificationReady extends FolioVerificationState {
  const FolioVerificationReady({
    this.rows = const [],
    this.selectedRequest,
    this.message,
  });

  final List<FolioVerificationRow> rows;
  final FolioVerificationRequest? selectedRequest;
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is FolioVerificationReady &&
      listEquals(rows, other.rows) &&
      selectedRequest == other.selectedRequest &&
      message == other.message;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(rows),
        selectedRequest,
        message,
      );
}

class FolioVerificationFailureState extends FolioVerificationState {
  const FolioVerificationFailureState(this.failure, {this.previous});
  final FolioVerificationApplicationFailure failure;
  final FolioVerificationState? previous;
}
