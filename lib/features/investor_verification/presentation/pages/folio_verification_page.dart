import 'dart:math';
import '../widgets/verification_workspace_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/folio_verification_service.dart';
import '../folio_verification_controller.dart';
import '../folio_verification_presentation_models.dart';
import '../folio_verification_state.dart';
import '../widgets/folio_failure_banner.dart';
import '../widgets/folio_request_list.dart';
import '../widgets/folio_submission_form.dart';

class FolioVerificationPage extends StatefulWidget {
  const FolioVerificationPage({super.key});

  @override
  State<FolioVerificationPage> createState() => _FolioVerificationPageState();
}

class _FolioVerificationPageState extends State<FolioVerificationPage> {
  var _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FolioVerificationController>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FolioVerificationController>();
    final state = controller.state;
    final ready = _readyState(state);
    final failure = state is FolioVerificationFailureState ? state : null;
    final loading = state is FolioVerificationLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Mutual Fund Folio')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth:
                      constraints.maxWidth > 1000 ? 1000 : double.infinity),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  FolioSubmissionForm(
                    isSubmitting: controller.isSubmitting,
                    onSubmit: (registrar, folio, relationship) async {
                      final workspaceId = await loadVerificationWorkspace(
                          context, controller.getWorkspaces);
                      if (workspaceId == null) return;
                      await controller.submitVisibleFolio(
                        workspaceId: workspaceId,
                        registrar: registrar,
                        folioNumber: folio,
                        relationship: relationship,
                        correlationId: _correlationId(),
                      );
                      if (mounted &&
                          controller.state is FolioVerificationReady) {
                        await controller.refresh();
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Your Verification Requests',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Tooltip(
                        message: 'Refresh verification requests',
                        child: IconButton(
                          onPressed: loading ? null : controller.refresh,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (failure != null) ...[
                    FolioFailureBanner(
                      failure: failure.failure,
                      onRetry: controller.retry,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (loading && ready == null)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    FolioRequestList(
                      rows: ready?.rows ?? const [],
                      onCancel: (row) => _cancel(controller, row),
                      onResubmit: (row) => _resubmit(controller, row),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  FolioVerificationReady? _readyState(FolioVerificationState state) =>
      switch (state) {
        FolioVerificationReady() => state,
        FolioVerificationLoading(previous: final previous)
            when previous is FolioVerificationReady =>
          previous,
        FolioVerificationFailureState(previous: final previous)
            when previous is FolioVerificationReady =>
          previous,
        _ => null,
      };

  Future<void> _cancel(
    FolioVerificationController controller,
    FolioVerificationRow row,
  ) async {
    await controller.cancel(
      FolioVerificationDecisionCommand(
        requestId: row.requestId,
        expectedVersion: row.version,
        correlationId: _correlationId(),
      ),
    );
    if (mounted && controller.state is FolioVerificationReady) {
      await controller.refresh();
    }
  }

  Future<void> _resubmit(
    FolioVerificationController controller,
    FolioVerificationRow row,
  ) async {
    await controller.resubmit(
      FolioVerificationDecisionCommand(
        requestId: row.requestId,
        expectedVersion: row.version,
        correlationId: _correlationId(),
      ),
    );
    if (mounted && controller.state is FolioVerificationReady) {
      await controller.refresh();
    }
  }
}

String _correlationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
