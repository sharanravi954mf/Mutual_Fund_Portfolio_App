import 'package:flutter/material.dart';
import '../data/supabase_verification_repository.dart';
import '../data/verification_repository.dart';
import '../models/verification_models.dart';

class AdvisorVerificationRequestDetailScreen extends StatefulWidget {
  const AdvisorVerificationRequestDetailScreen({
    required this.requestId,
    super.key,
    this.repository,
  });

  final String requestId;
  final VerificationRepository? repository;

  @override
  State<AdvisorVerificationRequestDetailScreen> createState() =>
      _AdvisorVerificationRequestDetailScreenState();
}

class _AdvisorVerificationRequestDetailScreenState
    extends State<AdvisorVerificationRequestDetailScreen> {
  late final VerificationRepository _repository;
  late Future<AdvisorVerificationReview> _review;
  AdvisorVerificationCandidate? _selectedCandidate;
  bool _isDeciding = false;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? SupabaseVerificationRepository.fromDefaultClient();
    _review = _repository.getReview(widget.requestId);
  }

  void _reload() =>
      setState(() => _review = _repository.getReview(widget.requestId));

  Future<void> _findCandidate() async {
    final candidate = await showDialog<AdvisorVerificationCandidate>(
      context: context,
      builder: (_) => _CandidateSearchDialog(
        requestId: widget.requestId,
        repository: _repository,
      ),
    );
    if (candidate != null && mounted) {
      setState(() => _selectedCandidate = candidate);
    }
  }

  Future<void> _decide(
    AdvisorVerificationReview review,
    _Decision decision,
  ) async {
    if (decision == _Decision.approve && _selectedCandidate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an investor candidate first.')),
      );
      return;
    }

    final reason = await _DecisionDialog.show(
      context,
      decision: decision,
      candidateName: _selectedCandidate?.name,
    );
    if (reason == null || !mounted) return;

    setState(() => _isDeciding = true);
    try {
      switch (decision) {
        case _Decision.approve:
          if (review.request.method == VerificationMethod.pan) {
            await _repository.approvePanCandidate(
              review.request.id,
              _selectedCandidate!.token,
              review.request.version,
              reasonCode: reason.isEmpty ? null : reason,
            );
          } else {
            await _repository.approveCandidate(
              review.request.id,
              _selectedCandidate!.token,
              review.request.version,
              reasonCode: reason.isEmpty ? null : reason,
            );
          }
          break;
        case _Decision.reject:
          await _repository.reject(
            review.request.id,
            review.request.version,
            reasonCode: reason,
          );
          break;
        case _Decision.moreInformation:
          await _repository.requestMoreInformation(
            review.request.id,
            review.request.version,
            reasonCode: reason,
          );
          break;
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The request changed. Refresh it and try again.'),
          ),
        );
        _reload();
      }
    } finally {
      if (mounted) setState(() => _isDeciding = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<AdvisorVerificationReview>(
        future: _review,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Scaffold(
              appBar: AppBar(title: const Text('Verification request detail')),
              body: Center(
                child: OutlinedButton(
                  onPressed: _reload,
                  child: const Text('Retry request detail'),
                ),
              ),
            );
          }

          final review = snapshot.data!;
          final canDecide =
              review.request.status == VerificationStatus.pendingAdvisorReview;
          return Scaffold(
            appBar: AppBar(title: const Text('Verification request detail')),
            body: _ReviewContent(
              review: review,
              selectedCandidate: _selectedCandidate,
              isDeciding: _isDeciding,
              onFindCandidate: _findCandidate,
            ),
            bottomNavigationBar: canDecide
                ? _DecisionActions(
                    isDeciding: _isDeciding,
                    onDecision: (decision) => _decide(review, decision),
                  )
                : null,
          );
        },
      );
}

class _ReviewContent extends StatelessWidget {
  const _ReviewContent({
    required this.review,
    required this.selectedCandidate,
    required this.isDeciding,
    required this.onFindCandidate,
  });

  final AdvisorVerificationReview review;
  final AdvisorVerificationCandidate? selectedCandidate;
  final bool isDeciding;
  final VoidCallback onFindCandidate;

  @override
  Widget build(BuildContext context) {
    final request = review.request;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Request ${_shortId(request.id)}',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        _InfoCard(
          title: 'Request details',
          children: [
            _InfoRow('Status', _label(request.status.databaseValue)),
            _InfoRow('Method', _label(request.method.databaseValue)),
            _InfoRow('Created', _date(request.createdAt)),
            if (request.submittedAt != null)
              _InfoRow('Submitted', _date(request.submittedAt!)),
            if (request.retryOfRequestId != null)
              _InfoRow('Retry of', _shortId(request.retryOfRequestId!)),
          ],
        ),
        if (request.panSummary != null) ...[
          const SizedBox(height: 16),
          _InfoCard(
            title: 'PAN verification',
            children: [
              _InfoRow('PAN', request.panSummary!.maskedPan),
              _InfoRow(
                'Match result',
                _label(request.panSummary!.matchResult.databaseValue),
              ),
              _InfoRow(
                'Review note',
                _conflictLabel(request.panSummary!.conflictReason),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _InfoCard(
          title: 'Requester',
          children: [
            _InfoRow('Email', review.maskedEmail ?? 'Not available'),
            _InfoRow('Mobile', review.maskedMobile ?? 'Not available'),
          ],
        ),
        const SizedBox(height: 16),
        _Timeline(events: review.timeline),
        if (request.status == VerificationStatus.pendingAdvisorReview) ...[
          const SizedBox(height: 16),
          _InfoCard(
            title: 'Candidate selection',
            children: [
              if (selectedCandidate == null)
                const Text('Select an imported investor before approval.')
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(selectedCandidate!.name),
                  subtitle: Text(
                    [
                      selectedCandidate!.maskedEmail,
                      selectedCandidate!.maskedMobile,
                      selectedCandidate!.profileSummary,
                    ].whereType<String>().join(' • '),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: isDeciding ? null : onFindCandidate,
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('Find investor candidate'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _shortId(String value) =>
      value.length <= 8 ? value : value.substring(0, 8);
  static String _label(String value) => value.replaceAll('_', ' ');
  static String _date(DateTime value) =>
      value.toLocal().toString().split('.').first;

  static String _conflictLabel(VerificationConflictReason reason) =>
      switch (reason) {
        VerificationConflictReason.none => 'No conflict identified',
        VerificationConflictReason.alreadyVerified =>
          'Already linked to a verified investor',
        VerificationConflictReason.pendingDuplicate =>
          'Duplicate pending verification',
        VerificationConflictReason.historicalMismatch => 'Historical mismatch',
        VerificationConflictReason.legacyInvalid =>
          'Legacy record needs review',
      };
}

class _DecisionActions extends StatelessWidget {
  const _DecisionActions({
    required this.isDeciding,
    required this.onDecision,
  });

  final bool isDeciding;
  final ValueChanged<_Decision> onDecision;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed:
                      isDeciding ? null : () => onDecision(_Decision.approve),
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: isDeciding
                      ? null
                      : () => onDecision(_Decision.moreInformation),
                  child: const Text('Request more information'),
                ),
                OutlinedButton(
                  onPressed:
                      isDeciding ? null : () => onDecision(_Decision.reject),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('$label: $value'),
      );
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});
  final List<VerificationEvent> events;

  @override
  Widget build(BuildContext context) => _InfoCard(
        title: 'Request history',
        children: events.isEmpty
            ? const [Text('No request events are available.')]
            : events
                .map(
                  (event) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: Text(event.type.replaceAll('_', ' ')),
                    subtitle: Text(event.createdAt.toLocal().toString()),
                  ),
                )
                .toList(),
      );
}

class _CandidateSearchDialog extends StatefulWidget {
  const _CandidateSearchDialog({
    required this.requestId,
    required this.repository,
  });
  final String requestId;
  final VerificationRepository repository;

  @override
  State<_CandidateSearchDialog> createState() => _CandidateSearchDialogState();
}

class _CandidateSearchDialogState extends State<_CandidateSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  Future<List<AdvisorVerificationCandidate>>? _results;
  AdvisorVerificationCandidate? _selected;

  void _search() {
    setState(() {
      _selected = null;
      _results = widget.repository.searchCandidates(
        widget.requestId,
        _controller.text.trim(),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Find investor candidate'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Name, email, or mobile',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 12),
              if (_results != null)
                SizedBox(
                  height: 260,
                  child: FutureBuilder<List<AdvisorVerificationCandidate>>(
                    future: _results,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Candidate search is unavailable.'),
                        );
                      }
                      final candidates = snapshot.data ?? const [];
                      if (candidates.isEmpty) {
                        return const Center(
                          child: Text('No candidates found.'),
                        );
                      }
                      return ListView.builder(
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          final isSelected = _selected == candidate;
                          return ListTile(
                            selected: isSelected,
                            onTap: () => setState(() => _selected = candidate),
                            title: Text(candidate.name),
                            subtitle: Text(
                              [
                                candidate.maskedEmail,
                                candidate.maskedMobile,
                                candidate.profileSummary,
                              ].whereType<String>().join(' • '),
                            ),
                            trailing: Icon(
                              isSelected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _search, child: const Text('Search')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _selected == null
                ? null
                : () => Navigator.pop(context, _selected),
            child: const Text('Use selected'),
          ),
        ],
      );
}

enum _Decision { approve, reject, moreInformation }

class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog({required this.decision, this.candidateName});
  final _Decision decision;
  final String? candidateName;

  static Future<String?> show(
    BuildContext context, {
    required _Decision decision,
    String? candidateName,
  }) =>
      showDialog<String>(
        context: context,
        builder: (_) => _DecisionDialog(
          decision: decision,
          candidateName: candidateName,
        ),
      );

  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  final TextEditingController _reasonController = TextEditingController();

  bool get _requiresReason => widget.decision != _Decision.approve;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.decision) {
      _Decision.approve => 'Approve verification',
      _Decision.reject => 'Reject verification',
      _Decision.moreInformation => 'Request more information',
    };
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.decision == _Decision.approve
                ? 'Approve the selected investor candidate: ${widget.candidateName}?'
                : 'This action will be recorded in the request history.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            decoration: InputDecoration(
              labelText:
                  _requiresReason ? 'Reason code' : 'Reason code (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _reasonController.text.trim();
            if (_requiresReason && reason.isEmpty) return;
            Navigator.pop(context, reason);
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
