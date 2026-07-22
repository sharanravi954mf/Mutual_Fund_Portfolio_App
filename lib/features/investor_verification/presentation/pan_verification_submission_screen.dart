import 'package:flutter/material.dart';

import '../data/supabase_verification_repository.dart';
import '../data/verification_repository.dart';

class PanVerificationSubmissionScreen extends StatefulWidget {
  const PanVerificationSubmissionScreen({super.key, this.repository});

  final VerificationRepository? repository;

  @override
  State<PanVerificationSubmissionScreen> createState() =>
      _PanVerificationSubmissionScreenState();
}

class _PanVerificationSubmissionScreenState
    extends State<PanVerificationSubmissionScreen> {
  late final VerificationRepository _repository =
      widget.repository ?? SupabaseVerificationRepository.fromDefaultClient();
  final TextEditingController _panController = TextEditingController();
  bool _submitting = false;
  String? _validationMessage;

  @override
  void dispose() {
    _panController.dispose();
    super.dispose();
  }

  bool get _hasValidFormat => RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(
        _panController.text.toUpperCase().replaceAll(RegExp(r'\s+'), ''),
      );

  Future<void> _submit() async {
    if (!_hasValidFormat) {
      setState(() =>
          _validationMessage = 'Enter a valid PAN in the format ABCDE1234F.');
      return;
    }
    setState(() {
      _submitting = true;
      _validationMessage = null;
    });
    try {
      final result = await _repository.submitPanVerification(
        _panController.text.toUpperCase().replaceAll(RegExp(r'\s+'), ''),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('PAN ${result.summary.maskedPan} submitted securely.')),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _validationMessage =
            'We could not submit your PAN. Check the format and try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Verify with PAN')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Confirm your investment account',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your PAN is used only to verify an existing investment record. '
                        'It is not used to sign in and is encrypted before storage.',
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _panController,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        enableSuggestions: false,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'PAN',
                          hintText: 'ABCDE1234F',
                          errorText: _validationMessage,
                        ),
                        onChanged: (_) {
                          if (_validationMessage != null) {
                            setState(() => _validationMessage = null);
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Submit securely'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
