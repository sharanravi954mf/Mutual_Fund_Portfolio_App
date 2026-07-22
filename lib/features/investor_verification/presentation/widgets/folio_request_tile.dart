import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/folio_verification_models.dart';
import '../folio_verification_presentation_models.dart';
import 'folio_status_badge.dart';

class FolioRequestTile extends StatelessWidget {
  const FolioRequestTile({
    super.key,
    required this.row,
    required this.onCancel,
    required this.onResubmit,
  });

  final FolioVerificationRow row;
  final VoidCallback? onCancel;
  final VoidCallback? onResubmit;

  @override
  Widget build(BuildContext context) {
    final display = row.display;
    final action = switch (display.status) {
      FolioVerificationStatus.pendingAdvisorReview => TextButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Cancel'),
        ),
      FolioVerificationStatus.moreInformationRequired => TextButton.icon(
          onPressed: onResubmit,
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Resubmit'),
        ),
      _ => null,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) => Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: Semantics(
                  label: '${display.registrarDisplay}, ${display.maskedFolio}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        display.registrarDisplay,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Folio ${display.maskedFolio}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (display.submittedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Submitted ${DateFormat.yMMMd().format(display.submittedAt!.toLocal())}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FolioStatusBadge(status: display.status),
                  if (action != null) action,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
