import 'package:flutter/material.dart';

import '../folio_verification_presentation_models.dart';
import 'empty_state.dart';
import 'folio_request_tile.dart';

class FolioRequestList extends StatelessWidget {
  const FolioRequestList({
    super.key,
    required this.rows,
    required this.onCancel,
    required this.onResubmit,
  });

  final List<FolioVerificationRow> rows;
  final ValueChanged<FolioVerificationRow> onCancel;
  final ValueChanged<FolioVerificationRow> onResubmit;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const FolioEmptyState();
    return ListView.separated(
      primary: false,
      shrinkWrap: true,
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        return FolioRequestTile(
          row: row,
          onCancel: () => onCancel(row),
          onResubmit: () => onResubmit(row),
        );
      },
    );
  }
}
