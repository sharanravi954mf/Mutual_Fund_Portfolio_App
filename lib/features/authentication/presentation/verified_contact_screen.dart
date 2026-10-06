import '../application/verified_contact_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../data/verified_contact_repository.dart';

class VerifiedContactEntry extends StatelessWidget {
  const VerifiedContactEntry({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final id = auth.user?.id;
    if (id == null) return const SizedBox.shrink();
    return VerifiedContactScreen(
        key: ValueKey(id),
        repository: SupabaseVerifiedContactRepository(auth.client, id),
        onVerified: auth.refreshIdentity,
        onSignOut: auth.signOut);
  }
}

class VerifiedContactScreen extends StatefulWidget {
  const VerifiedContactScreen(
      {required this.repository,
      required this.onVerified,
      required this.onSignOut,
      super.key});
  final VerifiedContactRepository repository;
  final Future<void> Function() onVerified, onSignOut;
  @override
  State<VerifiedContactScreen> createState() => _VerifiedContactScreenState();
}

class _VerifiedContactScreenState extends State<VerifiedContactScreen> {
  final phone = TextEditingController(), token = TextEditingController();
  late final VerifiedContactController c;
  @override
  void initState() {
    super.initState();
    c = VerifiedContactController(widget.repository, widget.onVerified);
  }

  @override
  void dispose() {
    c.dispose();
    phone.dispose();
    token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: c,
      builder: (context, _) => Scaffold(
            appBar: AppBar(title: const Text('Verify your identity')),
            body: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(padding: const EdgeInsets.all(24), children: [
                    const Text(
                        'Verify your mobile to finish account setup. Your existing login is retained; MoneyBowl resolves your investor access securely.'),
                    const SizedBox(height: 16),
                    const Text(
                        'Use the mobile supplied for your investor onboarding. If your details differ, contact your MFD or platform support for reconciliation.'),
                    const SizedBox(height: 24),
                    if (c.busy) const LinearProgressIndicator(),
                    if (c.error != null)
                      Semantics(
                          liveRegion: true,
                          child: Text(c.error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    if (c.sentPhone == null) ...[
                      TextField(
                          controller: phone,
                          enabled: !c.busy,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                              labelText: 'Mobile with country code',
                              hintText: '+ country code and number')),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: c.busy || c.coolingDown
                              ? null
                              : () => c.send(phone.text),
                          child: const Text('Send verification code')),
                    ] else ...[
                      Text(
                          'Code sent to ••••${c.sentPhone!.substring(c.sentPhone!.length - 4)}'),
                      TextField(
                          controller: token,
                          enabled: !c.busy,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(
                              labelText: 'Verification code')),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: c.busy
                              ? null
                              : () async {
                                  if (await c.verify(token.text) && mounted) {
                                    token.clear();
                                  }
                                },
                          child: const Text('Verify and continue')),
                      TextButton(
                          onPressed: c.busy || c.coolingDown
                              ? null
                              : () {
                                  c.requestAnother();
                                  token.clear();
                                },
                          child: const Text('Request another code')),
                    ],
                    const SizedBox(height: 16),
                    OutlinedButton(
                        onPressed: c.busy ? null : widget.onVerified,
                        child: const Text('Refresh verified access')),
                    TextButton(
                        onPressed: c.busy ? null : widget.onSignOut,
                        child: const Text('Sign out')),
                  ]),
                )),
          ));
}
