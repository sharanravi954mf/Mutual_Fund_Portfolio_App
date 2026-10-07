import 'package:flutter/material.dart';

import 'dev_onboarding_preview_controller.dart';
import 'dev_onboarding_preview_gate.dart';

/// The route has its own guard so direct navigation in a production build fails.
class DevOnboardingPreviewPage extends StatelessWidget {
  const DevOnboardingPreviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!DevOnboardingPreviewGate.enabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Onboarding preview unavailable')),
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Return to onboarding'),
          ),
        ),
      );
    }
    return const DevOnboardingPreviewFlow();
  }
}

/// Synthetic UI only. This widget has no real case input or backend dependency.
class DevOnboardingPreviewFlow extends StatefulWidget {
  const DevOnboardingPreviewFlow({super.key});

  @override
  State<DevOnboardingPreviewFlow> createState() =>
      _DevOnboardingPreviewFlowState();
}

class _DevOnboardingPreviewFlowState extends State<DevOnboardingPreviewFlow> {
  final _draft = DevOnboardingPreviewController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _next() {
    if (!(_form.currentState?.validate() ?? false)) return;
    _draft.advance();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _draft,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Text('DEV onboarding preview'),
            actions: [
              IconButton(
                tooltip: 'Exit preview',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Text(
                    'DEV SIMULATION — NOT KYC VERIFIED',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => ListView(
                      padding:
                          EdgeInsets.all(constraints.maxWidth < 400 ? 16 : 24),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Form(
                              key: _form,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'This is a development preview using test data. Your investor\'s KYC remains pending. No details entered here are submitted or saved to the investor.',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Step ${_draft.step.index + 1} of ${DevPreviewStep.values.length}',
                                    style:
                                        Theme.of(context).textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: (_draft.step.index + 1) /
                                        DevPreviewStep.values.length,
                                  ),
                                  const SizedBox(height: 24),
                                  ..._content(context),
                                  if (_draft.error != null) ...[
                                    const SizedBox(height: 12),
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        _draft.error!,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 24),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      if (_draft.step.index > 0 &&
                                          _draft.step !=
                                              DevPreviewStep.complete)
                                        OutlinedButton(
                                          onPressed: _draft.back,
                                          child: const Text('Back'),
                                        ),
                                      if (_draft.step !=
                                          DevPreviewStep.complete)
                                        FilledButton(
                                          onPressed: _next,
                                          child: Text(
                                            _draft.step == DevPreviewStep.review
                                                ? 'Finish preview'
                                                : 'Next',
                                          ),
                                        ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        child: Text(
                                          _draft.step == DevPreviewStep.complete
                                              ? 'Close preview'
                                              : 'Exit preview',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  List<Widget> _content(BuildContext context) {
    final title = Theme.of(context).textTheme.headlineSmall;
    final hint = Theme.of(context).textTheme.bodyMedium;
    switch (_draft.step) {
      case DevPreviewStep.personal:
        return [
          Text('Remaining personal details', style: title),
          const SizedBox(height: 8),
          Text(
            'Use fictional details only. Provider-confirmed identity is not simulated.',
            style: hint,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('demo-name'),
            initialValue: _draft.demoName,
            readOnly: true,
            decoration: const InputDecoration(labelText: 'Fictional investor'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('demo-email'),
            initialValue: _draft.demoEmail,
            readOnly: true,
            decoration: const InputDecoration(labelText: 'Fictional email'),
          ),
          const SizedBox(height: 16),
          _field(
            key: 'date-of-birth',
            label: 'Fictional date of birth (YYYY-MM-DD)',
            value: _draft.dateOfBirth,
            onChanged: (value) => _draft.dateOfBirth = value,
            validator: _dateValidator,
          ),
          const SizedBox(height: 16),
          _field(
            key: 'occupation',
            label: 'Fictional occupation',
            value: _draft.occupation,
            onChanged: (value) => _draft.occupation = value,
            validator: _required,
          ),
        ];
      case DevPreviewStep.address:
        return [
          Text('Address information', style: title),
          const SizedBox(height: 8),
          Text('Preview layout only. No address is saved.', style: hint),
          const SizedBox(height: 16),
          _field(
            key: 'address-line',
            label: 'Fictional address line',
            value: _draft.addressLine,
            onChanged: (value) => _draft.addressLine = value,
            validator: _required,
          ),
          const SizedBox(height: 16),
          _field(
            key: 'city',
            label: 'Fictional city',
            value: _draft.city,
            onChanged: (value) => _draft.city = value,
            validator: _required,
          ),
          const SizedBox(height: 16),
          _field(
            key: 'postal-code',
            label: 'Fictional postal code',
            value: _draft.postalCode,
            onChanged: (value) => _draft.postalCode = value,
            validator: _required,
          ),
          const SizedBox(height: 16),
          _field(
            key: 'country',
            label: 'Fictional country',
            value: _draft.country,
            onChanged: (value) => _draft.country = value,
            validator: _required,
          ),
        ];
      case DevPreviewStep.nominee:
        return [
          Text('Nominee decision', style: title),
          const SizedBox(height: 8),
          Text(
            'Do you wish to add a nominee? Choose only for this simulation.',
            style: hint,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ChoiceChip(
                label: const Text('Yes'),
                selected: _draft.hasNominee == true,
                onSelected: (_) {
                  _draft.hasNominee = true;
                  _draft.changed();
                },
              ),
              ChoiceChip(
                label: const Text('No'),
                selected: _draft.hasNominee == false,
                onSelected: (_) {
                  _draft.hasNominee = false;
                  _draft.changed();
                },
              ),
            ],
          ),
          if (_draft.hasNominee == true) ...[
            const SizedBox(height: 16),
            _field(
              key: 'nominee-name',
              label: 'Fictional nominee name',
              value: _draft.nomineeName,
              onChanged: (value) => _draft.nomineeName = value,
              validator: _required,
            ),
            const SizedBox(height: 16),
            _field(
              key: 'nominee-relationship',
              label: 'Fictional relationship',
              value: _draft.nomineeRelationship,
              onChanged: (value) => _draft.nomineeRelationship = value,
              validator: _required,
            ),
            const SizedBox(height: 8),
            const Text(
              'Nominee provider submission and authentication are not implemented in this preview.',
            ),
          ],
        ];
      case DevPreviewStep.fatca:
        return [
          Text('FATCA declarations', style: title),
          const SizedBox(height: 8),
          Text(
            'Is this fictional investor tax resident in India? No answer is assumed or submitted.',
            style: hint,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ChoiceChip(
                label: const Text('Yes, India'),
                selected: _draft.taxResidentInIndia == true,
                onSelected: (_) {
                  _draft.taxResidentInIndia = true;
                  _draft.changed();
                },
              ),
              ChoiceChip(
                label: const Text('No / other country'),
                selected: _draft.taxResidentInIndia == false,
                onSelected: (_) {
                  _draft.taxResidentInIndia = false;
                  _draft.changed();
                },
              ),
            ],
          ),
          if (_draft.taxResidentInIndia == false) ...[
            const SizedBox(height: 16),
            _field(
              key: 'other-tax-country',
              label: 'Fictional other tax residence',
              value: _draft.otherTaxCountry,
              onChanged: (value) => _draft.otherTaxCountry = value,
              validator: _required,
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Preview only: provider FATCA schema, evidence and declaration capture remain production work.',
          ),
        ];
      case DevPreviewStep.bank:
        return [
          Text('Bank details', style: title),
          const SizedBox(height: 8),
          Text(
            'Fictional layout only. Do not enter a real account number or IFSC.',
            style: hint,
          ),
          const SizedBox(height: 16),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Fictional bank'),
            subtitle: Text('Example Test Bank'),
          ),
          DropdownButtonFormField<String>(
            key: const ValueKey('account-type'),
            initialValue:
                _draft.accountType.isEmpty ? null : _draft.accountType,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Demo account type'),
            items: const [
              DropdownMenuItem(value: 'Savings', child: Text('Savings')),
              DropdownMenuItem(value: 'Current', child: Text('Current')),
            ],
            onChanged: (value) => _draft.accountType = value ?? '',
            validator: (value) => _required(value),
          ),
          const SizedBox(height: 16),
          const Text(
            'Account number and IFSC are intentionally not captured. Bank verification is unavailable in this preview.',
          ),
        ];
      case DevPreviewStep.review:
        return [
          Text('Review and consent preview', style: title),
          const SizedBox(height: 8),
          Text(
            'Review these fictional, unsaved choices. This is not investor consent.',
            style: hint,
          ),
          const SizedBox(height: 16),
          _summary('Investor', _draft.demoName),
          _summary('Occupation', _draft.occupation),
          _summary('Address', '${_draft.addressLine}, ${_draft.city}'),
          _summary(
            'Nominee',
            _draft.hasNominee == true ? 'Yes (preview)' : 'No (preview)',
          ),
          _summary(
            'Tax residence',
            _draft.taxResidentInIndia == true
                ? 'India (preview)'
                : '${_draft.otherTaxCountry} (preview)',
          ),
          _summary(
            'Bank',
            'Example Test Bank · ${_draft.accountType} · unverified',
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _draft.previewAcknowledged,
            title: const Text(
              'I understand this preview records no investor consent or registration.',
            ),
            onChanged: (value) {
              _draft.previewAcknowledged = value ?? false;
              _draft.changed();
            },
          ),
        ];
      case DevPreviewStep.complete:
        return [
          Text('End of preview', style: title),
          const SizedBox(height: 16),
          const Text(
            'Preview complete. No real investor was verified, registered or made ready to transact.',
          ),
          const SizedBox(height: 16),
          const Text(
            'The real KYC case is unchanged. Return to its eKYC status to continue the provider flow.',
          ),
        ];
    }
  }

  Widget _summary(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('$label: $value'),
      );

  Widget _field({
    required String key,
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    required FormFieldValidator<String> validator,
  }) =>
      TextFormField(
        key: ValueKey(key),
        initialValue: value,
        maxLength: 80,
        autocorrect: false,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
        validator: validator,
      );

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? 'Required for this preview.'
      : null;

  String? _dateValidator(String? value) {
    if (_required(value) != null) return _required(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value!)) {
      return 'Use YYYY-MM-DD.';
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 10) != value ||
        !parsed.isBefore(DateTime.now())) {
      return 'Enter a valid fictional past date.';
    }
    return null;
  }
}
