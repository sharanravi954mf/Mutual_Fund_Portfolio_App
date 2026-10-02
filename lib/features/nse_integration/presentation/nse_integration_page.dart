import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/nse_models.dart';
import 'nse_integration_controller.dart';

class NseIntegrationPage extends StatefulWidget {
  const NseIntegrationPage(
      {required this.controller,
      this.initialTarget,
      this.initialOperation,
      super.key});
  final NseIntegrationController controller;
  final String? initialTarget, initialOperation;
  @override
  State<NseIntegrationPage> createState() => _NseIntegrationPageState();
}

class _NseIntegrationPageState extends State<NseIntegrationPage>
    with WidgetsBindingObserver {
  NseIntegrationController get c => widget.controller;
  NseReadKind? _kind;
  String? _source;
  final Set<int> _rows = {};
  bool _optionalDates = false;
  final _from = TextEditingController(),
      _to = TextEditingController(),
      _date = TextEditingController();
  final _form = GlobalKey<FormState>();
  Uri? _lastRoute;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_syncRoute);
    final today = DateTime.now().toUtc().add(const Duration(minutes: 330));
    _to.text = _iso(today);
    _from.text = _iso(today.subtract(const Duration(days: 6)));
    _date.text = _to.text;
    unawaited(c.start(
        initialTarget: widget.initialTarget,
        initialOperation: widget.initialOperation));
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      c.setVisible(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    c.removeListener(_syncRoute);
    WidgetsBinding.instance.removeObserver(this);
    _from.dispose();
    _to.dispose();
    _date.dispose();
    super.dispose();
  }

  void _syncRoute() {
    if (!kIsWeb || c.phase != NseConsolePhase.ready || c.target == null) return;
    final route = Uri(path: '/nse-integration', queryParameters: {
      'target': c.target!.id,
      if (c.operation != null) 'operation': c.operation!.id,
    });
    if (route == _lastRoute) return;
    _lastRoute = route;
    unawaited(
        SystemNavigator.routeInformationUpdated(uri: route, replace: true));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: c,
      builder: (context, _) => Scaffold(
            appBar: AppBar(title: const Text('NSE Integration'), actions: [
              IconButton(
                  tooltip: 'Refresh status',
                  onPressed: c.isRefreshing ? null : () => c.refresh(),
                  icon: const Icon(Icons.refresh))
            ]),
            body: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text('DEV / UAT · Read-only reports',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text(
                            'Results are observations. A successful or empty report does not confirm an investment, payment, or cancellation.'),
                        if (c.isRefreshing ||
                            c.phase == NseConsolePhase.loading) ...[
                          const SizedBox(height: 16),
                          const LinearProgressIndicator()
                        ],
                        if (c.failure != null) _notice(c.failure!.message),
                        if (c.phase == NseConsolePhase.empty)
                          _notice('No assigned clients are available.'),
                        if (c.phase == NseConsolePhase.accessDenied)
                          _notice(
                              'Client access is unavailable. Return to the dashboard or refresh after access is restored.'),
                        if (c.targets.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                              key: ValueKey(c.target?.id),
                              initialValue:
                                  c.targets.any((x) => x.id == c.target?.id)
                                      ? c.target?.id
                                      : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Workspace / client',
                                  border: OutlineInputBorder()),
                              items: c.targets
                                  .map((t) => DropdownMenuItem(
                                      value: t.id,
                                      child: Text(
                                          '${t.workspaceLabel} / ${t.clientLabel}',
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged:
                                  c.isSubmitting || c.hasUnconfirmedRequest
                                      ? null
                                      : (id) {
                                          if (id == null) return;
                                          setState(() {
                                            _kind = null;
                                            _source = null;
                                            _rows.clear();
                                          });
                                          unawaited(c.selectTarget(c.targets
                                              .firstWhere((t) => t.id == id)));
                                        }),
                          if (c.targetCursor != null)
                            TextButton(
                                onPressed:
                                    c.isRefreshing ? null : c.moreTargets,
                                child: const Text('More clients')),
                        ],
                        if (c.hasUnconfirmedRequest)
                          _panel('Submission not yet confirmed', [
                            const Text(
                                'Check the saved request before starting another read. Retrying here reuses the same request reference.'),
                            Wrap(spacing: 8, children: [
                              TextButton(
                                  onPressed: c.isSubmitting ? null : c.recover,
                                  child: const Text('Check saved request')),
                              OutlinedButton(
                                  onPressed:
                                      c.isSubmitting ? null : c.retryPending,
                                  child: const Text('Retry same request'))
                            ]),
                          ]),
                        if (c.context != null &&
                            c.phase != NseConsolePhase.accessDenied) ...[
                          _panel('NSE account', [
                            Text(
                                'Registration: ${c.context!.accountState.replaceAll('_', ' ')}'),
                            Text(
                                'Client Master verification: ${c.context!.verificationStatus.replaceAll('_', ' ')}'),
                            if (c.context!.verificationOperationState != null)
                              Text(
                                  'Verification operation: ${c.context!.verificationOperationState!.replaceAll('_', ' ')}'),
                            Text(c.context!.deploymentVerified
                                ? 'Backend deployment verified for this release.'
                                : 'Backend deployment has not been enabled.'),
                            const Text(
                                'Commissioning and positive commissioning: unverified here. No certification is inferred from a result.'),
                          ]),
                          _panel('Read reports', [
                            for (final cap in c.context!.capabilities)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(cap.kind.api,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall),
                                        Text(nseReasonLabel(cap.reason)),
                                        OutlinedButton(
                                            onPressed: (!cap.available &&
                                                        !cap
                                                            .canSelectEvidence) ||
                                                    c.isSubmitting ||
                                                    c.hasUnconfirmedRequest
                                                ? null
                                                : () => setState(() {
                                                      _kind = cap.kind;
                                                      _source = null;
                                                      _rows.clear();
                                                      _optionalDates = false;
                                                    }),
                                            child: Text(cap.kind.isSettlement
                                                ? 'Select owned order evidence'
                                                : 'Prepare read')),
                                      ])),
                          ]),
                          if (_kind != null) _commandForm(_kind!),
                          if (c.operation != null) _operation(c.operation!),
                          _panel('Operation history', [
                            if (c.history.isEmpty)
                              const Text('No read operations yet.'),
                            for (final op in c.history)
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(op.kind.api),
                                  subtitle: Text(
                                      '${op.status.label} · ${op.createdAt.toLocal()}'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => c.selectOperation(op.id)),
                            if (c.historyCursor != null)
                              TextButton(
                                  onPressed:
                                      c.isRefreshing ? null : c.moreHistory,
                                  child: const Text('Older operations')),
                          ]),
                        ],
                      ],
                    ))),
          ));
  Widget _notice(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Semantics(liveRegion: true, child: Text(text)));
  Widget _panel(String title, List<Widget> children) => Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children
          ])));
  Widget _dateField(String label, TextEditingController controller) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
              labelText: label,
              hintText: 'YYYY-MM-DD',
              border: const OutlineInputBorder()),
          validator: (value) {
            final parsed = DateTime.tryParse(value ?? '');
            return parsed == null || _iso(parsed) != value
                ? 'Enter a real date as YYYY-MM-DD.'
                : null;
          }));
  Widget _commandForm(NseReadKind kind) {
    final sources = c.history
        .where((op) =>
            op.kind == NseReadKind.orderStatus &&
            op.status == NseDisplayStatus.success)
        .toList();
    return _panel('Prepare ${kind.api}', [
      Form(
          key: _form,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (kind.optionalDates) ...[
              const Text(
                  'The account selector overrides report dates. Dates do not narrow an account-selected report.'),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Supply optional dates'),
                  value: _optionalDates,
                  onChanged: (value) =>
                      setState(() => _optionalDates = value ?? false)),
            ],
            if (kind.singleDate)
              _dateField('Report date', _date)
            else if (!kind.noDates &&
                (!kind.optionalDates || _optionalDates)) ...[
              _dateField('From', _from),
              _dateField('To', _to)
            ],
            if (kind.isSettlement) ...[
              DropdownButtonFormField<String>(
                  key: ValueKey('${kind.wire}:$_source'),
                  initialValue:
                      sources.any((x) => x.id == _source) ? _source : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Owned ORDER_STATUS result',
                      border: OutlineInputBorder()),
                  items: sources
                      .map((op) => DropdownMenuItem(
                          value: op.id,
                          child: Text(
                              '${op.createdAt.toLocal()} · ${op.id.substring(0, 8)}',
                              overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: c.isRefreshing
                      ? null
                      : (value) {
                          setState(() {
                            _source = value;
                            _rows.clear();
                          });
                          if (value != null) {
                            unawaited(c.loadCandidates(kind, value));
                          }
                        },
                  validator: (value) =>
                      value == null ? 'Select an owned result.' : null),
              const SizedBox(height: 8),
              if (_source != null)
                for (final row in c.candidates)
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Report row ${row.index + 1}'),
                      subtitle: row.eligible
                          ? null
                          : Text(nseReasonLabel('ORDER_EVIDENCE_NOT_ELIGIBLE')),
                      value: _rows.contains(row.index),
                      onChanged: row.eligible
                          ? (selected) => setState(() {
                                if (selected == true) {
                                  _rows.add(row.index);
                                } else {
                                  _rows.remove(row.index);
                                }
                              })
                          : null),
              if (_source != null && c.candidateCursor != null)
                TextButton(
                    onPressed: c.isRefreshing
                        ? null
                        : () => c.loadCandidates(kind, _source!, more: true),
                    child: const Text('More report rows')),
              const Text(
                  'Select 1–50 eligible rows. Provider order and folio identifiers remain private.'),
            ],
            const SizedBox(height: 16),
            FilledButton(
                onPressed: c.isSubmitting ||
                        c.isRefreshing ||
                        c.hasUnconfirmedRequest
                    ? null
                    : () {
                        if (!_form.currentState!.validate()) return;
                        if (kind.isSettlement &&
                            (_rows.isEmpty || _rows.length > 50)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Select 1–50 eligible rows.')));
                          return;
                        }
                        unawaited(c.submit(NseReadCommand(
                            kind: kind,
                            from: !kind.noDates &&
                                    !kind.singleDate &&
                                    (!kind.optionalDates || _optionalDates)
                                ? _from.text
                                : null,
                            to: !kind.noDates &&
                                    !kind.singleDate &&
                                    (!kind.optionalDates || _optionalDates)
                                ? _to.text
                                : null,
                            date: kind.singleDate ? _date.text : null,
                            sourceOperationId:
                                kind.isSettlement ? _source : null,
                            rowIndices: _rows.toList()..sort())));
                      },
                child: Text(c.isSubmitting ? 'Submitting…' : 'Start read')),
          ]))
    ]);
  }

  Widget _operation(NseOperation op) =>
      _panel('${op.kind.api} · ${op.status.label}', [
        if (c.failure != null)
          const Text(
              'Showing the last known status; the latest status could not be confirmed.'),
        Text('Attempts: ${op.attempts}'),
        Text('Created: ${op.createdAt.toLocal()}'),
        if (op.submittedAt != null)
          Text('Submitted: ${op.submittedAt!.toLocal()}'),
        if (op.completedAt != null)
          Text('Last attempt completed: ${op.completedAt!.toLocal()}'),
        Text('Checked: ${op.fetchedAt.toLocal()}'),
        if (op.summary != null) ...[
          if (op.summary!.nativeStatus != null)
            Text('Native status: ${op.summary!.nativeStatus}'),
          Text('Category: ${op.summary!.category}'),
          if (op.summary!.recordCount != null)
            Text('Record count: ${op.summary!.recordCount}'),
          if (op.summary!.validCount != null)
            Text(
                'Valid: ${op.summary!.validCount} · Invalid: ${op.summary!.invalidCount} · Other: ${op.summary!.otherCount}'),
        ],
        if (c.takingLonger)
          const Text(
              'Taking longer than expected. The backend owns retries; refreshing only checks status.'),
        if (c.pollingPaused)
          TextButton(
              onPressed: () => c.refresh(),
              child: const Text('Automatic checking paused · Refresh status')),
      ]);
}
