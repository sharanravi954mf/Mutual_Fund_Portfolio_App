import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import 'mfa_controller.dart';
import 'mfa_models.dart';
import 'mfa_repository.dart';
import 'mfa_setup_panel.dart';

Future<bool?> openPlatformSecurity(BuildContext context,
        {MfaRepository? repository,
        MfaDestination destination = const MfaDestination.account()}) =>
    Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PlatformSecurityScreen(
            repository: repository, destination: destination)));

class PlatformSecurityScreen extends StatefulWidget {
  const PlatformSecurityScreen(
      {super.key,
      this.repository,
      this.destination = const MfaDestination.account()});
  final MfaRepository? repository;
  final MfaDestination destination;
  @override
  State<PlatformSecurityScreen> createState() => _PlatformSecurityScreenState();
}

class _PlatformSecurityScreenState extends State<PlatformSecurityScreen>
    with WidgetsBindingObserver {
  late final AuthProvider _auth;
  late final MfaController _controller;
  final _code = TextEditingController();
  bool _restart = false;
  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _controller = MfaController(
        widget.repository ?? SupabaseMfaRepository(_auth.client, _auth));
    _auth.addListener(_accessChanged);
    _controller.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_controller.refresh());
  }

  void _changed() {
    if (!_controller.current ||
        _controller.confirmed ||
        !_controller.foreground) {
      _code.clear();
    }
    if (mounted) setState(() {});
  }

  void _accessChanged() {
    _controller.accessChanged(
        currentAccess: _auth.platformContextCurrent,
        admin: _auth.platformContext.isPlatformAdmin,
        stepUp: _auth.platformContext.stepUpVerified);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.resume());
    } else {
      _code.clear();
      _controller.suspend();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_accessChanged);
    _controller.removeListener(_changed);
    _controller.dispose();
    _code.clear();
    _code.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Leave account security?'),
              content: Text(_controller.busy
                  ? 'The current request may still finish. Leaving clears this screen; it does not undo verification or remove a pending factor. Check status when you return.'
                  : 'Leaving clears the setup key from this screen. A pending authenticator may remain. If you already added it, you can select it and verify later.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Stay')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Leave'))
              ],
            ));
    if (leave == true && mounted) {
      _controller.cancel();
      _code.clear();
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text;
    _code.clear();
    await _controller.verify(code);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final status = c.status;
    final choices = status?.totp ?? [];
    final reviewAllowed = widget.destination.applicationId == null ||
        _auth.platformContext.capabilities.contains('mfd_applications.review');
    return PopScope<bool>(
      canPop: c.setup == null && !c.busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_cancel());
      },
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Account security'),
            leading: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: _cancel)),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(24), children: [
            Text(c.repository.issuer,
                style: Theme.of(context).textTheme.headlineSmall),
            Text('Application account: ${c.repository.accountLabel}'),
            const Text(
                'This protects your MoneyBowl account. Read-only platform access remains available without step-up.'),
            const SizedBox(height: 16),
            if (!c.foreground)
              const Text('Security details hidden while the app is inactive.'),
            if (c.foreground) ...[
              if (c.busy) ...[
                const Center(child: CircularProgressIndicator()),
                Text(switch (c.phase) {
                  MfaPhase.enrolling => 'Setting up authenticator…',
                  MfaPhase.verifying =>
                    'Verifying and confirming server access…',
                  _ => 'Checking security status…',
                }),
              ],
              if (c.error != null)
                Text(c.error!.message,
                    key: const Key('mfa-error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (!reviewAllowed)
                const Text(
                    'Application review permission is unavailable. MFA does not grant that permission.'),
              if (reviewAllowed && c.confirmed) ...[
                const Text('Current platform session verified by the server.'),
                FilledButton(
                    onPressed: reviewAllowed
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: Text(widget.destination.applicationId == null
                        ? 'Done'
                        : 'Return to application')),
              ] else if (reviewAllowed && status != null && !c.busy) ...[
                if (status.factors.isEmpty)
                  const Text('No authenticator configured.'),
                if (choices.any((f) => !f.verified))
                  const Text(
                      'Incomplete setup exists. If you already added it to an authenticator, select that pending factor and verify. A page reload cannot recover its setup key.'),
                if (choices.any((f) => f.verified))
                  const Text(
                      'Verify MFA with an existing authenticator for this session.'),
                if (choices.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: ValueKey('mfa-factors-${c.selectedId}'),
                    initialValue: c.selectedId,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Authenticator'),
                    items: [
                      for (var i = 0; i < choices.length; i++)
                        DropdownMenuItem(
                            value: choices[i].id,
                            child: Text(
                                'Authenticator ${i + 1} · ${choices[i].verified ? 'Verified' : 'Pending'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: c.canAct ? c.select : null,
                  ),
                if (c.setup != null)
                  MfaSetupPanel(
                      key: ValueKey(c.setup!.factorId),
                      setup: c.setup!,
                      enabled: c.canAct),
                if (choices.isNotEmpty) ...[
                  TextField(
                    key: const Key('mfa-code'),
                    controller: _code,
                    enabled: c.canVerify,
                    keyboardType: TextInputType.number,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: true,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9]'))
                    ],
                    decoration: const InputDecoration(
                        labelText: 'Six-digit authenticator code',
                        helperText:
                            'Leading zeros are preserved. Paste is supported.'),
                  ),
                  FilledButton(
                      onPressed: c.canVerify ? _verify : null,
                      child: const Text('Verify MFA')),
                ],
                if (!status.hasVerified &&
                    c.setup == null &&
                    (status.factors.isEmpty || choices.isNotEmpty)) ...[
                  if (choices.isNotEmpty)
                    CheckboxListTile(
                        value: _restart,
                        onChanged: c.canAct
                            ? (value) =>
                                setState(() => _restart = value ?? false)
                            : null,
                        title: const Text(
                            'I cannot finish an existing setup and want a new one. Pending factors will remain; account limits may prevent another setup.')),
                  FilledButton(
                      onPressed: c.canEnroll && (choices.isEmpty || _restart)
                          ? () => c.enroll(restartAcknowledged: _restart)
                          : null,
                      child: Text(choices.isEmpty
                          ? 'Set up authenticator'
                          : 'Start new setup')),
                ],
              ],
              if (!c.busy && c.current)
                TextButton(
                    onPressed: c.canAct ? c.refresh : null,
                    child: const Text('Refresh security status')),
              const SizedBox(height: 16),
              const Text(
                  'Lost your authenticator? This release does not provide factor removal, replacement, recovery codes or account reset. Contact your platform administrator for an established recovery process; MFA cannot be bypassed here.'),
              TextButton(onPressed: _cancel, child: const Text('Cancel')),
            ],
          ]),
        ))),
      ),
    );
  }
}
