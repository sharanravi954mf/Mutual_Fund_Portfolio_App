import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_verification_repository.dart';
import '../data/verification_repository.dart';
import '../models/verification_models.dart';

class VerificationStatusScreen extends StatefulWidget {
  const VerificationStatusScreen({super.key, this.repository});
  final VerificationRepository? repository;

  @override
  State<VerificationStatusScreen> createState() =>
      _VerificationStatusScreenState();
}

class _VerificationStatusScreenState extends State<VerificationStatusScreen> {
  late final VerificationRepository _repository = widget.repository ??
      SupabaseVerificationRepository(Supabase.instance.client);
  late Future<List<VerificationRequest>> _requests = _repository.getStatus();

  void _reload() => setState(() => _requests = _repository.getStatus());

  Future<void> _startAdvisorAssisted() async {
    await _repository.createRequest(VerificationMethod.advisorAssisted);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<VerificationRequest>>(
        future: _requests,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _StatusMessage(
              title: 'Verification status is unavailable',
              body:
                  'Please try again. Your investments remain protected until verification is complete.',
              action: () async => _reload(),
            );
          }
          final requests = snapshot.data ?? const <VerificationRequest>[];
          final request = requests.isEmpty ? null : requests.first;
          if (request == null) {
            return _StatusMessage(
              title: 'Verify your investment account',
              body:
                  'We could not automatically locate your investments. You can ask your advisor to help verify your account.',
              action: _startAdvisorAssisted,
              actionLabel: 'Request advisor verification',
            );
          }
          return _RequestStatus(
              request: request, repository: _repository, onChanged: _reload);
        },
      );
}

class _RequestStatus extends StatelessWidget {
  const _RequestStatus(
      {required this.request,
      required this.repository,
      required this.onChanged});
  final VerificationRequest request;
  final VerificationRepository repository;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Verification ${_label(request.status)}',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      Text(_message(request.status)),
                      const SizedBox(height: 12),
                      Text(
                          'Method: ${request.method.databaseValue.replaceAll('_', ' ')}'),
                      if (request.status.canCancel) ...[
                        const SizedBox(height: 20),
                        OutlinedButton(
                          onPressed: () async {
                            await repository.cancelRequest(
                                request.id, request.version);
                            onChanged();
                          },
                          child: const Text('Cancel request'),
                        ),
                      ],
                    ]),
              ),
            ),
          ),
        ),
      );

  static String _label(VerificationStatus status) =>
      status.databaseValue.replaceAll('_', ' ');
  static String _message(VerificationStatus status) => switch (status) {
        VerificationStatus.pendingAdvisorReview =>
          'Your request is awaiting advisor review. We will not show any portfolio data until it is approved.',
        VerificationStatus.approved =>
          'Your account has been verified. Refreshing your account will open your portfolio.',
        VerificationStatus.rejected =>
          'We could not complete this verification. Please contact your advisor to try again.',
        VerificationStatus.cancelled =>
          'This verification request was cancelled.',
        VerificationStatus.expired =>
          'This verification request has expired. Please start again.',
        VerificationStatus.draft =>
          'Your verification request is not yet submitted.',
      };
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage(
      {required this.title,
      required this.body,
      required this.action,
      this.actionLabel = 'Try again'});
  final String title;
  final String body;
  final Future<void> Function() action;
  final String actionLabel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(body),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: action, child: Text(actionLabel)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class AdvisorVerificationQueueScreen extends StatefulWidget {
  const AdvisorVerificationQueueScreen({super.key, this.repository});
  final VerificationRepository? repository;
  @override
  State<AdvisorVerificationQueueScreen> createState() =>
      _AdvisorVerificationQueueScreenState();
}

class _AdvisorVerificationQueueScreenState
    extends State<AdvisorVerificationQueueScreen> {
  late final VerificationRepository _repository = widget.repository ??
      SupabaseVerificationRepository(Supabase.instance.client);
  late Future<List<VerificationRequest>> _queue = _repository.reviewQueue();
  void _reload() => setState(() => _queue = _repository.reviewQueue());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Verification review queue')),
        body: FutureBuilder<List<VerificationRequest>>(
            future: _queue,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                    child: OutlinedButton(
                        onPressed: _reload, child: const Text('Retry queue')));
              }
              final queue = snapshot.data ?? const [];
              if (queue.isEmpty) {
                return const Center(
                    child: Text(
                        'No verification requests are waiting for review.'));
              }
              return ListView.separated(
                  itemCount: queue.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final request = queue[index];
                    return ListTile(
                      title: Text('Request ${request.id}'),
                      subtitle: Text(
                          '${request.method.databaseValue.replaceAll('_', ' ')} • ${request.status.databaseValue}'),
                      trailing: TextButton(
                          onPressed: () => _review(context, request),
                          child: const Text('Review')),
                    );
                  });
            }),
      );

  Future<void> _review(
      BuildContext context, VerificationRequest request) async {
    final profileController = TextEditingController();
    final reasonController = TextEditingController();
    final decision = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Review verification'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: profileController,
                    decoration: const InputDecoration(
                        labelText:
                            'Imported investor profile ID (approve only)')),
                TextField(
                    controller: reasonController,
                    decoration:
                        const InputDecoration(labelText: 'Reason code')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Reject')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Approve')),
              ],
            ));
    if (decision == null) return;
    if (decision) {
      await _repository.approve(
          request.id, profileController.text.trim(), request.version,
          reasonCode: reasonController.text.trim());
    } else {
      await _repository.reject(request.id, request.version,
          reasonCode: reasonController.text.trim());
    }
    if (mounted) _reload();
  }
}
