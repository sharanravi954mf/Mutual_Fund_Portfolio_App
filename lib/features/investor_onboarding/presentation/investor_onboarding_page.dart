import 'package:flutter/material.dart';
import '../models/onboarding_case.dart';
import 'investor_onboarding_controller.dart';

class InvestorOnboardingPage extends StatefulWidget {
  const InvestorOnboardingPage(
      {required this.controller,
      this.startNew = false,
      this.providerKyc = false,
      this.alreadyLoaded = false,
      super.key});
  final InvestorOnboardingController controller;
  final bool startNew, providerKyc, alreadyLoaded;
  @override
  State<InvestorOnboardingPage> createState() => _InvestorOnboardingPageState();
}

class _InvestorOnboardingPageState extends State<InvestorOnboardingPage> {
  int section = 0;
  InvestorOnboardingController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    if (widget.alreadyLoaded) return;
    c.load().then((_) {
      if (mounted && widget.startNew && c.phase == OnboardingPhase.directory) {
        c.start();
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Investor onboarding')),
          body: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                    key: ValueKey('${c.phase}:$section'),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (c.busy) const LinearProgressIndicator(),
                      if (c.error != null)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Semantics(
                                liveRegion: true,
                                child: Text(c.error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)))),
                      ..._content(context),
                    ]),
              )),
        ),
      );
  List<Widget> _content(BuildContext context) {
    switch (c.phase) {
      case OnboardingPhase.loading:
        return [
          const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Loading your workspace…')))
        ];
      case OnboardingPhase.failure:
        return [
          OutlinedButton(
              onPressed: c.busy ? null : c.load, child: const Text('Retry'))
        ];
      case OnboardingPhase.unavailable:
        return [
          const Text(
              'An active approved MFD workspace is required to add investors.')
        ];
      case OnboardingPhase.directory:
        if (widget.providerKyc) {
          return [
            OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Return to KYC'))
          ];
        }
        return _directory();
      case OnboardingPhase.editing:
        return _editor(context);
      case OnboardingPhase.review:
        return _review(context);
      case OnboardingPhase.saved:
        return _status(context);
    }
  }

  List<Widget> _directory() => [
        if (c.workspaces.length > 1)
          DropdownButtonFormField<String>(
            initialValue: c.workspace,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'MFD workspace'),
            items: c.workspaces
                .map((w) =>
                    DropdownMenuItem(value: w['id'], child: Text(w['name']!)))
                .toList(),
            onChanged: c.busy
                ? null
                : (v) {
                    if (v != null) c.selectWorkspace(v);
                  },
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: c.busy
                ? null
                : () {
                    section = 0;
                    c.start();
                  },
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add Investor')),
        const SizedBox(height: 24),
        const Text('Saved onboarding',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (c.cases.isEmpty)
          const Text('No onboarding drafts yet. Add an investor to begin.'),
        for (final item in c.cases)
          Card(
              child: ListTile(
            title: Text(item.name),
            subtitle: Text(OnboardingCase.label(item.status)),
            trailing: const Icon(Icons.chevron_right),
            onTap: c.busy ? null : () => c.resume(item.id),
          )),
      ];
  List<Widget> _editor(BuildContext context) {
    final entries = onboardingSections.entries.toList();
    final entry = entries[section];
    return [
      Text('Add Investor · ${section + 1} of ${entries.length}',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
          'Enter only known investor details. You can save incomplete information and resume later.'),
      const SizedBox(height: 16),
      Text(entry.key, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 16),
      for (final f in entry.value.where((f) =>
          !widget.providerKyc ||
          !['kyc_method', 'kyc_status', 'ckyc_number'].contains(f.key)))
        Padding(padding: const EdgeInsets.only(bottom: 16), child: _field(f)),
      if (section == 2 && !widget.providerKyc)
        const Text(
            'Reported KYC status is captured for review. It does not verify KYC. Joint holdings require additional provider support.'),
      if (section == 2 && widget.providerKyc)
        const Text('KYC type and CKYC require authoritative provider data.'),
      if (section == 4)
        const Text(
            'Record the investor’s actual consent and nomination choice. Nominee opt-in can be captured, but the existing NSE adapter currently supports opt-out only.'),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (section > 0)
          OutlinedButton(
              onPressed: c.busy ? null : () => setState(() => section--),
              child: const Text('Back')),
        if (section < entries.length - 1)
          FilledButton(
              onPressed: c.busy ? null : () => setState(() => section++),
              child: const Text('Next')),
        OutlinedButton(
            onPressed: c.busy ? null : () => c.save(),
            child: const Text('Save draft')),
        FilledButton(
            onPressed: c.busy ? null : c.review, child: const Text('Review')),
      ]),
    ];
  }

  Widget _field(OnboardingField f) {
    final resolved = c.current?.investorId != null;
    final locked = resolved &&
        (['legal_name', 'pan', 'email', 'mobile'].contains(f.key) ||
            (f.key == 'date_of_birth' &&
                (c.current?.fields[f.key] ?? '').isNotEmpty));
    if (f.choices != null) {
      return DropdownButtonFormField<String>(
        key: ValueKey('${c.current?.id}:$section:${f.key}'),
        initialValue:
            f.choices!.contains(c.fields[f.key]) ? c.fields[f.key] : null,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: f.label, border: const OutlineInputBorder()),
        items: [
          const DropdownMenuItem(value: '', child: Text('Not yet supplied')),
          ...f.choices!.map((v) =>
              DropdownMenuItem(value: v, child: Text(OnboardingCase.label(v))))
        ],
        onChanged: c.busy || locked ? null : (v) => c.fields[f.key] = v ?? '',
      );
    }
    return TextFormField(
      key: ValueKey('${c.current?.id}:$section:${f.key}'),
      initialValue: c.fields[f.key] ?? '',
      enabled: !c.busy && !locked,
      obscureText: f.secret,
      autocorrect: false,
      enableSuggestions: !f.secret,
      maxLength:
          f.key.endsWith('details') || f.key == 'declarations' ? 2000 : 150,
      decoration: InputDecoration(
          labelText: f.label,
          border: const OutlineInputBorder(),
          helperText: f.secret && c.current != null
              ? 'Captured value: ${f.key == 'pan' ? c.current!.maskedPan : c.current!.maskedAccount}. Leave blank to retain.'
              : locked
                  ? 'Resolved identity · changes require review'
                  : null,
          helperMaxLines: 3),
      onChanged: (v) => c.fields[f.key] = v,
    );
  }

  List<Widget> _review(BuildContext context) => [
        Text('Review investor details',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
            'Missing details remain incomplete. Continuing resolves the investor and your authorised relationship.'),
        const SizedBox(height: 16),
        for (final group in onboardingSections.entries) ...[
          Text(group.key, style: Theme.of(context).textTheme.titleMedium),
          for (final f in group.value.where((f) =>
              !widget.providerKyc ||
              !['kyc_method', 'kyc_status', 'ckyc_number'].contains(f.key)))
            if ((c.fields[f.key] ?? '').isNotEmpty ||
                (f.secret && c.current != null))
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('${f.label}: ${_reviewValue(f)}')),
          const Divider(),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
              onPressed: c.busy ? null : c.edit,
              child: const Text('Edit details')),
          FilledButton(
              onPressed: c.busy ? null : () => c.save(resolve: true),
              child: const Text('Continue onboarding')),
        ]),
      ];
  String _reviewValue(OnboardingField f) {
    final value = c.fields[f.key] ?? '';
    if (f.secret) {
      if (value.isEmpty) {
        return f.key == 'pan'
            ? c.current?.maskedPan ?? '••••'
            : c.current?.maskedAccount ?? '••••';
      }
      if (f.key == 'pan' &&
          !RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$')
              .hasMatch(value.trim().toUpperCase())) {
        return '••••';
      }
      return value.length >= 8
          ? '******${value.substring(value.length - 4)}'
          : '••••';
    }
    if ([
      'email',
      'mobile',
      'ckyc_number',
      'nominee_details',
      'holder_details',
      'declarations'
    ].contains(f.key)) {
      return value.isEmpty ? 'Not supplied' : 'Captured · hidden';
    }
    return value.isEmpty ? 'Not supplied' : value;
  }

  List<Widget> _status(BuildContext context) {
    final item = c.current!;
    return [
      Text(item.name, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      Semantics(
          liveRegion: true,
          child: Text(OnboardingCase.label(item.status),
              style: Theme.of(context).textTheme.titleMedium)),
      const SizedBox(height: 16),
      Text('MFD relationship: ${OnboardingCase.label(item.relationship)}'),
      if (!widget.providerKyc)
        Text('Account linkage: ${OnboardingCase.label(item.accountLink)}'),
      Text('KYC: ${OnboardingCase.label(item.kycState)}'),
      Text('UCC: ${OnboardingCase.label(item.uccState)}'),
      Text('NSE registration: ${OnboardingCase.label(item.nseState)}'),
      Text('PAN: ${item.maskedPan}'),
      Text('Bank account: ${item.maskedAccount}'),
      const SizedBox(height: 16),
      if (item.reconciliation)
        const Text(
            'Identity or relationship review is required. Contact platform support with the case reference below. Do not restart onboarding or reassign the investor.'),
      SelectableText('Case reference: ${item.id}'),
      if (item.operationId != null)
        SelectableText('NSE operation: ${item.operationId}'),
      const SizedBox(height: 16),
      const Text('Remaining prerequisites',
          style: TextStyle(fontWeight: FontWeight.bold)),
      if (item.missing.isEmpty)
        const Text(
            'Captured prerequisites are complete. Provider validation is required before submission.'),
      for (final field in item.missing)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('• ${OnboardingCase.label(field)}')),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (!item.reconciliation && item.nseState == 'NOT_REGISTERED')
          FilledButton(
              onPressed: c.busy
                  ? null
                  : () {
                      section = 0;
                      c.edit();
                    },
              child: const Text('Continue details')),
        OutlinedButton(
            onPressed: c.busy
                ? null
                : (widget.providerKyc
                    ? () => Navigator.of(context).pop()
                    : c.load),
            child: const Text('Back to investors')),
        OutlinedButton(
            onPressed: c.busy ? null : () => c.resume(item.id),
            child: const Text('Refresh status')),
      ]),
    ];
  }
}
