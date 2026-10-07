import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'onboarding_kyc_controller.dart';
import 'investor_onboarding_controller.dart';
import 'investor_onboarding_page.dart';
import 'dev_onboarding_preview_gate.dart';
import 'dev_onboarding_preview_page.dart';

class OnboardingKycPage extends StatefulWidget {
  const OnboardingKycPage(
      {required this.controller,
      this.startNew = true,
      this.openLink,
      super.key});
  final OnboardingKycController controller;
  final bool startNew;
  final Future<bool> Function(Uri)? openLink;
  @override
  State<OnboardingKycPage> createState() => _OnboardingKycPageState();
}

class _OnboardingKycPageState extends State<OnboardingKycPage> {
  final pan = TextEditingController(),
      email = TextEditingController(),
      mobile = TextEditingController();
  String? amc;
  OnboardingKycController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.load(startNew: widget.startNew);
  }

  @override
  void dispose() {
    pan.dispose();
    email.dispose();
    mobile.dispose();
    super.dispose();
  }

  Future<void> check() async {
    await c.check(pan.text);
    if (mounted && c.current != null && c.current!.state != 'DRAFT') {
      pan.clear();
    }
  }

  Future<void> initiate() async {
    await c.act('EKYC', email: email.text, mobile: mobile.text, amc: amc);
    if (mounted && c.current?.state == 'EKYC_INITIATION_PENDING') {
      email.clear();
      mobile.clear();
    }
  }

  Future<void> details() async {
    final controller = InvestorOnboardingController(c.repository.legacy);
    await controller.load();
    await controller.resume(c.current!.id);
    if (!mounted) {
      controller.dispose();
      return;
    }
    controller.edit();
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InvestorOnboardingPage(
            controller: controller, providerKyc: true, alreadyLoaded: true)));
    controller.dispose();
  }

  Widget button(String label, VoidCallback action) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child:
          FilledButton(onPressed: c.busy ? null : action, child: Text(label)));
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: c,
      builder: (context, _) => Scaffold(
            appBar: AppBar(title: const Text('Add Investor')),
            body: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(padding: const EdgeInsets.all(24), children: [
                    if (c.busy) const LinearProgressIndicator(),
                    if (c.error != null)
                      Semantics(liveRegion: true, child: Text(c.error!)),
                    if (!c.loaded)
                      const Text('Loading your workspace…')
                    else if (c.workspace == null)
                      const Text(
                          'An active approved MFD workspace is required to add investors.')
                    else
                      ...content(context),
                  ])),
            ),
          ));
  List<Widget> content(BuildContext context) {
    if (!c.editing) {
      return [
        button('Add Investor', c.start),
        const SizedBox(height: 24),
        const Text('Onboarding drafts'),
        for (final row in c.cases)
          ListTile(
              title: Text(row.name),
              subtitle: Text(row.maskedPan),
              onTap: c.busy ? null : () => c.resume(row.id)),
      ];
    }
    final current = c.current;
    if (current == null || current.state == 'DRAFT') {
      return [
        if (c.workspaces.length > 1)
          DropdownButtonFormField<String>(
              initialValue: c.workspace,
              decoration: const InputDecoration(labelText: 'MFD workspace'),
              items: c.workspaces
                  .map((w) =>
                      DropdownMenuItem(value: w['id'], child: Text(w['name']!)))
                  .toList(),
              onChanged: c.busy ? null : (v) => c.workspace = v),
        Text('Start with PAN',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text(
            'We’ll check the investor’s identity and KYC before asking for remaining details.'),
        const SizedBox(height: 24),
        TextField(
            controller: pan,
            enabled: !c.busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 10,
            decoration: const InputDecoration(
                labelText: 'PAN', border: OutlineInputBorder())),
        button('Continue / Check KYC', check),
      ];
    }
    final state = current.state;
    return [
      Text('KYC Status', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Text(current.onboarding.maskedPan),
      const SizedBox(height: 16),
      if (state == 'KYC_CHECK_REQUIRED') ...[
        const Text('Check KYC to continue.'),
        button('Check KYC', () => c.check(''))
      ] else if (state == 'KYC_CHECKING' ||
          state == 'EKYC_INITIATION_PENDING') ...[
        Text(state == 'KYC_CHECKING' ? 'Checking KYC…' : 'Preparing eKYC…'),
        button('Refresh progress', c.refreshView),
      ] else if (state == 'KYC_NOT_AVAILABLE' ||
          state == 'EKYC_DETAILS_REQUIRED') ...[
        const Text('Not available'),
        const SizedBox(height: 12),
        const Text(
            'To continue onboarding, the investor needs to complete eKYC.'),
        if ((current.onboarding.fields['email'] ?? '').isEmpty)
          TextField(
              controller: email,
              enabled: !c.busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email')),
        if ((current.onboarding.fields['mobile'] ?? '').isEmpty)
          TextField(
              controller: mobile,
              enabled: !c.busy,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile')),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
            initialValue: amc,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'AMC'),
            items: current.amcs
                .map((a) => DropdownMenuItem(
                    value: a['code'], child: Text(a['label']!)))
                .toList(),
            onChanged: c.busy ? null : (v) => setState(() => amc = v)),
        if (current.amcs.isEmpty)
          const Text(
              'No approved eKYC AMC selection is available. Contact support.'),
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: FilledButton(
                onPressed: c.busy || amc == null ? null : initiate,
                child: const Text('Proceed to eKYC'))),
      ] else if (state == 'EKYC_IN_PROGRESS') ...[
        const Text('eKYC in progress'),
        const SizedBox(height: 12),
        const Text('The investor must complete the provider verification.'),
        if (current.canOpen)
          button(
              'Open eKYC',
              () => c.open(widget.openLink ??
                  (uri) => launchUrl(uri,
                      mode: LaunchMode.externalApplication,
                      webOnlyWindowName: '_blank'))),
        button('Refresh KYC Status', () => c.act('REFRESH')),
        if (DevOnboardingPreviewGate.enabled) ...[
          const SizedBox(height: 24),
          const Text(
              'This is a development preview using test data. Your investor\'s KYC remains pending. No details entered here are submitted or saved to the investor.'),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton(
              onPressed: c.busy
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const DevOnboardingPreviewPage())),
              child: const Text('Preview remaining onboarding (DEV)'),
            ),
          ),
        ],
      ] else if (state == 'KYC_COMPLIANT') ...[
        const Text('KYC compliant'),
        button('Continue to remaining details', details),
      ] else ...[
        const Text('Review required'),
        const SizedBox(height: 12),
        const Text(
            'This onboarding case needs review before it can continue. Contact support with the case reference.'),
        SelectableText(current.id),
      ],
    ];
  }
}
