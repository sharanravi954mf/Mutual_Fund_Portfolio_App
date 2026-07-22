import 'package:flutter/material.dart';
import '../data/supabase_verification_repository.dart';
import '../data/verification_repository.dart';
import '../models/verification_models.dart';
import 'advisor_verification_request_detail_screen.dart';

class AdvisorVerificationQueueScreen extends StatefulWidget {
  const AdvisorVerificationQueueScreen({super.key, this.repository});

  final VerificationRepository? repository;

  @override
  State<AdvisorVerificationQueueScreen> createState() =>
      _AdvisorVerificationQueueScreenState();
}

class _AdvisorVerificationQueueScreenState
    extends State<AdvisorVerificationQueueScreen> {
  late final VerificationRepository _repository;
  final TextEditingController _requestIdController = TextEditingController();
  VerificationQueueFilter _filter = const VerificationQueueFilter();
  late Future<List<VerificationRequest>> _queue;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? SupabaseVerificationRepository.fromDefaultClient();
    _queue = _loadQueue();
  }

  Future<List<VerificationRequest>> _loadQueue() =>
      _repository.reviewQueue(_filter);

  void _reload() => setState(() => _queue = _loadQueue());

  void _updateFilter(VerificationQueueFilter filter) {
    setState(() {
      _filter = filter;
      _queue = _loadQueue();
    });
  }

  Future<void> _openDetail(VerificationRequest request) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AdvisorVerificationRequestDetailScreen(
          requestId: request.id,
          repository: _repository,
        ),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  @override
  void dispose() {
    _requestIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Verification review queue')),
        body: Column(
          children: [
            _QueueFilters(
              requestIdController: _requestIdController,
              filter: _filter,
              onChanged: _updateFilter,
              onClear: () {
                _requestIdController.clear();
                _updateFilter(const VerificationQueueFilter());
              },
            ),
            Expanded(
              child: FutureBuilder<List<VerificationRequest>>(
                future: _queue,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _QueueMessage(
                      icon: Icons.error_outline,
                      message: 'The verification queue is unavailable.',
                      actionLabel: 'Retry',
                      onAction: _reload,
                    );
                  }
                  final queue = snapshot.data ?? const <VerificationRequest>[];
                  if (queue.isEmpty) {
                    return const _QueueMessage(
                      icon: Icons.inbox_outlined,
                      message: 'No verification requests match these filters.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: queue.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final request = queue[index];
                      return ListTile(
                        title: Text('Request ${_shortId(request.id)}'),
                        subtitle: Text(
                          [
                            _label(request.method.databaseValue),
                            _label(request.status.databaseValue),
                            if (request.panSummary != null)
                              request.panSummary!.maskedPan,
                            if (request.panSummary?.conflictReason != null &&
                                request.panSummary!.conflictReason !=
                                    VerificationConflictReason.none)
                              _conflictLabel(
                                request.panSummary!.conflictReason,
                              ),
                          ].join(' • '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openDetail(request),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );

  static String _shortId(String value) =>
      value.length <= 8 ? value : value.substring(0, 8);

  static String _label(String value) =>
      value.replaceAll('_', ' ').replaceFirstMapped(
            RegExp(r'^.'),
            (match) => match.group(0)!.toUpperCase(),
          );

  static String _conflictLabel(VerificationConflictReason reason) =>
      switch (reason) {
        VerificationConflictReason.none => 'No conflict',
        VerificationConflictReason.alreadyVerified => 'Already verified',
        VerificationConflictReason.pendingDuplicate => 'Pending duplicate',
        VerificationConflictReason.historicalMismatch => 'Historical mismatch',
        VerificationConflictReason.legacyInvalid =>
          'Legacy record needs review',
      };
}

class _QueueFilters extends StatelessWidget {
  const _QueueFilters({
    required this.requestIdController,
    required this.filter,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController requestIdController;
  final VerificationQueueFilter filter;
  final ValueChanged<VerificationQueueFilter> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                controller: requestIdController,
                decoration: const InputDecoration(
                  labelText: 'Request ID',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (value) => onChanged(
                  filter.copyWith(requestIdQuery: value.trim()),
                ),
              ),
            ),
            DropdownButton<VerificationStatus?>(
              value: filter.status,
              hint: const Text('All statuses'),
              items: [
                const DropdownMenuItem<VerificationStatus?>(
                  value: null,
                  child: Text('All statuses'),
                ),
                ...VerificationStatus.values.map(
                  (status) => DropdownMenuItem<VerificationStatus?>(
                    value: status,
                    child: Text(status.databaseValue.replaceAll('_', ' ')),
                  ),
                ),
              ],
              onChanged: (value) => onChanged(
                filter.copyWith(status: value, clearStatus: value == null),
              ),
            ),
            DropdownButton<VerificationMethod?>(
              value: filter.method,
              hint: const Text('All methods'),
              items: [
                const DropdownMenuItem<VerificationMethod?>(
                  value: null,
                  child: Text('All methods'),
                ),
                ...VerificationMethod.values.map(
                  (method) => DropdownMenuItem<VerificationMethod?>(
                    value: method,
                    child: Text(method.databaseValue.replaceAll('_', ' ')),
                  ),
                ),
              ],
              onChanged: (value) => onChanged(
                filter.copyWith(method: value, clearMethod: value == null),
              ),
            ),
            TextButton(onPressed: onClear, child: const Text('Clear filters')),
          ],
        ),
      );
}

class _QueueMessage extends StatelessWidget {
  const _QueueMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(message),
            if (onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      );
}
