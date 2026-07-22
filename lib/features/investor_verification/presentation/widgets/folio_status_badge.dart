import 'package:flutter/material.dart';

import '../../models/folio_verification_models.dart';

class FolioStatusBadge extends StatelessWidget {
  const FolioStatusBadge({super.key, required this.status});

  final FolioVerificationStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final descriptor = switch (status) {
      FolioVerificationStatus.pendingAdvisorReview => (
          'Pending',
          Icons.schedule_outlined,
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
      FolioVerificationStatus.underReview => (
          'Under review',
          Icons.manage_search_outlined,
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
      FolioVerificationStatus.moreInformationRequired => (
          'More information required',
          Icons.info_outline,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      FolioVerificationStatus.approved => (
          'Approved',
          Icons.check_circle_outline,
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      FolioVerificationStatus.rejected => (
          'Rejected',
          Icons.cancel_outlined,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      FolioVerificationStatus.cancelled => (
          'Cancelled',
          Icons.remove_circle_outline,
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      FolioVerificationStatus.expired => (
          'Expired',
          Icons.timer_off_outlined,
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      FolioVerificationStatus.superseded => (
          'Superseded',
          Icons.swap_horiz_outlined,
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      FolioVerificationStatus.revoked => (
          'Revoked',
          Icons.block_outlined,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
    };

    return Semantics(
      label: 'Verification status: ${descriptor.$1}',
      child: Chip(
        avatar: Icon(descriptor.$2, size: 18, color: descriptor.$4),
        label: Text(descriptor.$1),
        backgroundColor: descriptor.$3,
        labelStyle: TextStyle(color: descriptor.$4),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
