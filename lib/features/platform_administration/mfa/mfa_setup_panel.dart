import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'mfa_models.dart';

class MfaSetupPanel extends StatefulWidget {
  const MfaSetupPanel({super.key, required this.setup, required this.enabled});
  final MfaSetup setup;
  final bool enabled;
  @override
  State<MfaSetupPanel> createState() => _MfaSetupPanelState();
}

class _MfaSetupPanelState extends State<MfaSetupPanel> {
  bool _revealed = false, _copied = false;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Scan this QR in your authenticator. Do not share the QR or setup key.'),
          Center(
              child: Semantics(
            label:
                'Authenticator setup QR. A manual setup key is available below.',
            child: ExcludeSemantics(
                child: QrImageView(
              data: widget.setup.uri,
              size: 232,
              padding: const EdgeInsets.all(16),
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square, color: Colors.black),
              dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black),
              errorStateBuilder: (_, __) =>
                  const Text('Use the manual setup key.'),
            )),
          )),
          const Text(
              'Using the same phone? Add a time-based account manually in your authenticator with the account label and setup key, then return here and enter its code.'),
          TextButton(
              onPressed: widget.enabled
                  ? () => setState(() => _revealed = !_revealed)
                  : null,
              child: Text(_revealed ? 'Hide setup key' : 'Reveal setup key')),
          if (_revealed)
            SelectableText(widget.setup.secret,
                key: const Key('mfa-manual-key')),
          OutlinedButton(
              onPressed: widget.enabled
                  ? () async {
                      try {
                        await Clipboard.setData(
                            ClipboardData(text: widget.setup.secret));
                        if (mounted) setState(() => _copied = true);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Clipboard unavailable. Reveal the setup key to enter it manually.')));
                        }
                      }
                    }
                  : null,
              child: const Text('Copy setup key')),
          if (_copied)
            const Text(
                'Setup key copied. Keep your clipboard private. MoneyBowl will not overwrite it.'),
        ],
      );
}
