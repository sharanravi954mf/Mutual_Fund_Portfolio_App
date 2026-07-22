import 'package:flutter/material.dart';
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
  late final VerificationRepository _repository =
      widget.repository ?? SupabaseVerificationRepository.fromDefaultClient();
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
  const _RequestStatus({
    required this.request,
    required this.repository,
    required this.onChanged,
  });

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
                  ],
                ),
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
        VerificationStatus.moreInformationRequired =>
          'Your advisor needs more information before this request can continue.',
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
  const _StatusMessage({
    required this.title,
    required this.body,
    required this.action,
    this.actionLabel = 'Try again',
  });

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
