import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../providers/auth_provider.dart';
import '../data/mfd_application_repository.dart';
import '../models/mfd_application.dart';

MfdApplicationRepository _repository(MfdApplicationRepository? supplied) =>
    supplied ?? SupabaseMfdApplicationRepository(Supabase.instance.client);
String _date(DateTime value) =>
    DateFormat('dd MMM yyyy, HH:mm').format(value.toLocal());
bool _canReview(AuthProvider auth) =>
    auth.platformContext.isPlatformAdmin &&
    auth.platformContext.capabilities.contains('mfd_applications.review');

class MfdApplicantScreen extends StatefulWidget {
  const MfdApplicantScreen({super.key, this.repository});
  final MfdApplicationRepository? repository;
  @override
  State<MfdApplicantScreen> createState() => _MfdApplicantScreenState();
}

class _MfdApplicantScreenState extends State<MfdApplicantScreen> {
  late final MfdApplicationRepository _repo = _repository(widget.repository);
  List<MfdApplication> _applications = [];
  bool _loading = true, _eligible = false;
  String? _error;
  final Set<String> _refreshed = {};
  String? _openedBy;
  @override
  void initState() {
    super.initState();
    _openedBy = context.read<AuthProvider>().user?.id;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final applications = await _repo.list();
      final eligible = await _repo.canApply();
      if (!mounted) return;
      setState(() {
        _applications = applications;
        _eligible = eligible;
        _loading = false;
      });
      for (final app in applications.where((a) => a.status == 'approved')) {
        if (_refreshed.add(app.id)) {
          await context.read<AuthProvider>().refreshIdentity();
          if (!mounted) return;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = mfdErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _apply() async {
    final result = await Navigator.of(context).push<MfdApplication>(
        MaterialPageRoute(
            builder: (_) => MfdApplicationForm(
                repository: _repo, operation: MfdOperation.submit)));
    if (mounted && result != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isAuthenticated || auth.user?.id != _openedBy) {
      return const Scaffold(
          body: Center(
              child: Text(
                  'Your signed-in account changed. Close this page and refresh.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('MFD application'), actions: [
        IconButton(
            tooltip: 'Refresh application status',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh))
      ]),
      body: _Page(children: [
        const Text(
            'Applying does not create MFD authority. A MoneyBowl Platform reviewer must approve your application.'),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_error != null) Text(_error!, key: const Key('mfd-error')),
        if (!_loading && _error == null && _eligible)
          FilledButton(
              onPressed: _apply,
              child: Text(_applications.isEmpty
                  ? 'Apply as MFD'
                  : 'Start a new application')),
        if (!_loading && _error == null && !_eligible && _applications.isEmpty)
          const Text(
              'V1 supports verified Explorers without an existing business identity.'),
        for (final app in _applications)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(app.businessName,
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(app.statusLabel),
                        Text('Claimed ARN: ${app.claimedArn}'),
                        Text('Submitted ${_date(app.submittedAt)}'),
                        if (app.status == 'rejected')
                          Text('Reason: ${app.decisionNote ?? ''}'),
                        if (app.status == 'approved') ...[
                          const Text(
                              'Approved following manual registration review. Your workspace is ready.'),
                          TextButton(
                              onPressed: () async {
                                await context
                                    .read<AuthProvider>()
                                    .refreshIdentity();
                                if (context.mounted) {
                                  Navigator.of(context)
                                      .popUntil((route) => route.isFirst);
                                }
                              },
                              child: const Text('Continue to workspace')),
                        ],
                      ]))),
      ]),
    );
  }
}

class MfdReviewQueueScreen extends StatefulWidget {
  const MfdReviewQueueScreen({super.key, this.repository});
  final MfdApplicationRepository? repository;
  @override
  State<MfdReviewQueueScreen> createState() => _MfdReviewQueueScreenState();
}

class _MfdReviewQueueScreenState extends State<MfdReviewQueueScreen> {
  late final MfdApplicationRepository _repo = _repository(widget.repository);
  List<MfdApplication> _items = [];
  bool _loading = true, _more = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!_canReview(context.read<AuthProvider>())) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items =
          await _repo.list(review: true, offset: more ? _items.length : 0);
      if (mounted) {
        setState(() {
          _items = more ? [..._items, ...items] : items;
          _more = items.length == 50;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = mfdErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canReview(context.watch<AuthProvider>())) {
      return const Scaffold(
          body: Center(
              child: Text('Application review permission is required.')));
    }
    return Scaffold(
        appBar: AppBar(title: const Text('MFD applications'), actions: [
          IconButton(
              tooltip: 'Refresh applications',
              onPressed: _loading ? null : () => _load(),
              icon: const Icon(Icons.refresh))
        ]),
        body: _Page(children: [
          if (_error != null) Text(_error!),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && _items.isEmpty && _error == null)
            const Text('No MFD applications yet.'),
          for (final app in _items)
            Card(
                child: ListTile(
                    title: Text(app.businessName),
                    subtitle: Text(
                        'Claimed ARN: ${app.claimedArn}\n${app.statusLabel} · ${_date(app.submittedAt)}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push<void>(MaterialPageRoute(
                          builder: (_) => MfdReviewDetailScreen(
                              applicationId: app.id, repository: _repo)));
                      if (mounted) await _load();
                    })),
          if (_more)
            TextButton(
                onPressed: _loading ? null : () => _load(more: true),
                child: const Text('Load more')),
        ]));
  }
}

class MfdReviewDetailScreen extends StatefulWidget {
  const MfdReviewDetailScreen(
      {super.key, required this.applicationId, this.repository});
  final String applicationId;
  final MfdApplicationRepository? repository;
  @override
  State<MfdReviewDetailScreen> createState() => _MfdReviewDetailScreenState();
}

class _MfdReviewDetailScreenState extends State<MfdReviewDetailScreen> {
  late final MfdApplicationRepository _repo = _repository(widget.repository);
  MfdApplication? _app;
  List<MfdApplicationEvent> _events = [];
  bool _loading = true, _busy = false;
  String? _error;
  MfdRequest? _startRequest;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_canReview(context.read<AuthProvider>())) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final app = await _repo.load(widget.applicationId);
      final events = await _repo.events(widget.applicationId);
      if (mounted) {
        setState(() {
          _app = app;
          _events = events;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = mfdErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    _startRequest ??= MfdRequest(
        operation: MfdOperation.startReview,
        requestId: newMfdRequestId(),
        applicationId: _app!.id,
        expectedVersion: _app!.version);
    try {
      await _repo.mutate(_startRequest!);
      _startRequest = null;
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = mfdErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(MfdOperation operation) async {
    final result = await Navigator.of(context).push<MfdApplication>(
        MaterialPageRoute(
            builder: (_) => MfdApplicationForm(
                repository: _repo, operation: operation, application: _app)));
    if (mounted && result != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!_canReview(auth)) {
      return const Scaffold(
          body: Center(
              child: Text('Application review permission is required.')));
    }
    final app = _app;
    return Scaffold(
        appBar: AppBar(title: const Text('Review MFD application'), actions: [
          IconButton(
              tooltip: 'Refresh application',
              onPressed: _loading || _busy ? null : _load,
              icon: const Icon(Icons.refresh))
        ]),
        body: _Page(children: [
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null) Text(_error!, key: const Key('mfd-error')),
          if (app != null) ...[
            Text(app.businessName,
                style: Theme.of(context).textTheme.headlineSmall),
            Text('Applicant: ${app.email}'),
            Text('Claimed ARN: ${app.claimedArn}'),
            if (app.applicantNote != null)
              Text('Applicant note: ${app.applicantNote}'),
            Text('Submitted ${_date(app.submittedAt)}'),
            Text(app.statusLabel),
            if (app.status == 'submitted')
              FilledButton(
                  onPressed: _busy || _loading ? null : _start,
                  child: Text(_startRequest == null
                      ? 'Start review'
                      : 'Retry start review safely')),
            if (app.status == 'under_review') ...[
              if (!auth.platformContext.stepUpVerified)
                const Text(
                    'MFA verification is required before approving or rejecting an MFD application.'),
              Wrap(spacing: 12, children: [
                FilledButton(
                    onPressed: auth.platformContext.stepUpVerified &&
                            !_busy &&
                            !_loading
                        ? () => _decide(MfdOperation.approve)
                        : null,
                    child: const Text('Approve')),
                OutlinedButton(
                    onPressed: auth.platformContext.stepUpVerified &&
                            !_busy &&
                            !_loading
                        ? () => _decide(MfdOperation.reject)
                        : null,
                    child: const Text('Reject')),
              ]),
            ],
            if (app.isTerminal) ...[
              Text('Decision: ${app.decisionNote ?? ''}'),
              if (app.approvedArn != null)
                Text('Manually accepted ARN: ${app.approvedArn}'),
            ],
            const Divider(),
            Text('History', style: Theme.of(context).textTheme.titleMedium),
            for (final event in _events)
              Text('${event.label} · ${_date(event.occurredAt)}'),
          ],
        ]));
  }
}

/// The same form owns one frozen mutation across failures; no automatic new UUID.
class MfdApplicationForm extends StatefulWidget {
  const MfdApplicationForm(
      {super.key,
      required this.repository,
      required this.operation,
      this.application});
  final MfdApplicationRepository repository;
  final MfdOperation operation;
  final MfdApplication? application;
  @override
  State<MfdApplicationForm> createState() => _MfdApplicationFormState();
}

class _MfdApplicationFormState extends State<MfdApplicationForm> {
  final _form = GlobalKey<FormState>();
  final _business = TextEditingController(),
      _arn = TextEditingController(),
      _note = TextEditingController();
  bool _confirmed = false, _busy = false;
  String? _error;
  MfdRequest? _request;
  String? _openedBy;
  @override
  void initState() {
    super.initState();
    _openedBy = context.read<AuthProvider>().user?.id;
  }

  bool get _submit => widget.operation == MfdOperation.submit;
  bool get _approve => widget.operation == MfdOperation.approve;
  @override
  void dispose() {
    _business.dispose();
    _arn.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _required(String? value, int max) {
    if (value == null || value.trim().isEmpty) return 'This field is required.';
    if (value.trim().runes.length > max) return 'Use $max characters or fewer.';
    return null;
  }

  Future<void> _send() async {
    final session = context.read<AuthProvider>();
    if (!session.isAuthenticated || session.user?.id != _openedBy) return;
    if (_busy || !_form.currentState!.validate()) return;
    if (_approve && !_confirmed) {
      setState(() => _error =
          'Confirm that you manually reviewed the submitted registration claim.');
      return;
    }
    if (!_submit) {
      final auth = context.read<AuthProvider>();
      if (!_canReview(auth) || !auth.platformContext.stepUpVerified) return;
    }
    _request ??= MfdRequest(
        operation: widget.operation,
        requestId: newMfdRequestId(),
        applicationId: widget.application?.id,
        expectedVersion: widget.application?.version,
        businessName: _business.text.trim(),
        claimedArn: _arn.text.trim(),
        note: _note.text.trim());
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.mutate(_request!);
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = mfdErrorMessage(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isAuthenticated || auth.user?.id != _openedBy) {
      return const Scaffold(
          body: Center(
              child: Text(
                  'Your signed-in account changed. Close this page and refresh.')));
    }
    final permitted =
        _submit || (_canReview(auth) && auth.platformContext.stepUpVerified);
    return Scaffold(
        appBar: AppBar(
            title: Text(_submit
                ? 'Apply as MFD'
                : _approve
                    ? 'Approve MFD application'
                    : 'Reject MFD application')),
        body: _Page(children: [
          Form(
              key: _form,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_submit) ...[
                      const Text(
                          'These are application claims. Submission does not create MFD authority.'),
                      TextFormField(
                          key: const Key('mfd-business'),
                          controller: _business,
                          readOnly: _request != null,
                          decoration: const InputDecoration(
                              labelText: 'MFD / business name'),
                          maxLength: 200,
                          validator: (v) => _required(v, 200)),
                      TextFormField(
                          key: const Key('mfd-arn'),
                          controller: _arn,
                          readOnly: _request != null,
                          decoration:
                              const InputDecoration(labelText: 'Claimed ARN'),
                          maxLength: 100,
                          validator: (v) => _required(v, 100)),
                    ] else ...[
                      Text(widget.application!.businessName),
                      Text('Claimed ARN: ${widget.application!.claimedArn}'),
                      if (_approve)
                        const Text(
                            'Approval accepts the submitted registration claim following your manual review and creates an MFD workspace. No external ARN verification is performed.'),
                      const Text(
                          'This note is visible to the applicant. Include a useful reference; do not include secrets or other customers’ information.'),
                    ],
                    TextFormField(
                        key: const Key('mfd-note'),
                        controller: _note,
                        readOnly: _request != null,
                        decoration: InputDecoration(
                            labelText: _submit
                                ? 'Applicant note (optional)'
                                : _approve
                                    ? 'Review evidence / reference'
                                    : 'Rejection reason'),
                        maxLength: 2000,
                        minLines: 3,
                        maxLines: 6,
                        validator: (v) => _submit
                            ? ((v?.trim().runes.length ?? 0) > 2000
                                ? 'Use 2000 characters or fewer.'
                                : null)
                            : _required(v, 2000)),
                    if (_approve)
                      CheckboxListTile(
                          value: _confirmed,
                          onChanged: _request != null
                              ? null
                              : (v) => setState(() => _confirmed = v ?? false),
                          title: const Text(
                              'I have manually reviewed and accept the submitted ARN / registration claim.')),
                    if (!permitted)
                      const Text(
                          'MFA verification and current application review permission are required before this decision.'),
                    if (_error != null)
                      Text(_error!, key: const Key('mfd-error')),
                    if (_busy) const Center(child: CircularProgressIndicator()),
                    FilledButton(
                        onPressed: _busy || !permitted ? null : _send,
                        child: Text(_request != null
                            ? 'Retry safely'
                            : _submit
                                ? 'Submit application'
                                : _approve
                                    ? 'Confirm approval'
                                    : 'Confirm rejection')),
                  ]))
        ]));
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
      child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.all(24), children: [
                for (final child in children)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16), child: child)
              ]))));
}
