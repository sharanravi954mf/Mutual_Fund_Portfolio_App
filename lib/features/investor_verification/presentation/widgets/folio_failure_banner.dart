import 'package:flutter/material.dart';

import '../../application/folio_verification_service.dart';

class FolioFailureBanner extends StatelessWidget {
  const FolioFailureBanner({
    super.key,
    required this.failure,
    required this.onRetry,
  });

  final FolioVerificationApplicationFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: 'Verification request error: ${_message(failure.code)}',
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _message(failure.code),
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _message(FolioVerificationApplicationFailureCode code) =>
      switch (code) {
        FolioVerificationApplicationFailureCode.unauthenticated =>
          'Please sign in again and try once more.',
        FolioVerificationApplicationFailureCode.permissionDenied =>
          'You do not have permission to complete this action.',
        FolioVerificationApplicationFailureCode.tokenInvalidOrExpired =>
          'Your folio verification session expired. Please submit again.',
        FolioVerificationApplicationFailureCode.staleVersion =>
          'This request changed. Refresh and try again.',
        FolioVerificationApplicationFailureCode.duplicate =>
          'A matching verification request already exists.',
        FolioVerificationApplicationFailureCode.validation =>
          'Check the information provided and try again.',
        FolioVerificationApplicationFailureCode.timeout ||
        FolioVerificationApplicationFailureCode.temporary =>
          'We could not complete that request. Please try again.',
        _ => 'We could not complete that request. Please try again.',
      };
}
