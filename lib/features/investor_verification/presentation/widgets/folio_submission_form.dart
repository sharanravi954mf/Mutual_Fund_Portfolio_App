import 'package:flutter/material.dart';

import '../../models/folio_verification_models.dart';

class FolioSubmissionForm extends StatefulWidget {
  const FolioSubmissionForm({
    super.key,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final bool isSubmitting;
  final Future<void> Function(
    String registrar,
    String folioNumber,
    FolioHolderRelationship relationship,
  ) onSubmit;

  @override
  State<FolioSubmissionForm> createState() => _FolioSubmissionFormState();
}

class _FolioSubmissionFormState extends State<FolioSubmissionForm> {
  final _formKey = GlobalKey<FormState>();
  final _folioController = TextEditingController();
  String? _registrar;
  FolioHolderRelationship? _relationship;

  @override
  void dispose() {
    _folioController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await widget.onSubmit(
      _registrar!,
      _folioController.text.trim(),
      _relationship!,
    );
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                final fields = [
                  _registrarField(),
                  _folioField(),
                  _relationshipField(),
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verify a folio',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var index = 0; index < fields.length; index++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: index == fields.length - 1 ? 0 : 12,
                                ),
                                child: fields[index],
                              ),
                            ),
                        ],
                      )
                    else ...[
                      for (final field in fields) ...[
                        field,
                        const SizedBox(height: 12),
                      ],
                    ],
                    const SizedBox(height: 16),
                    Align(
                      alignment:
                          wide ? Alignment.centerRight : Alignment.centerLeft,
                      child: Tooltip(
                        message: 'Submit folio verification request',
                        child: ElevatedButton.icon(
                          onPressed: widget.isSubmitting ? null : _submit,
                          icon: widget.isSubmitting
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.verified_user_outlined),
                          label: Text(
                            widget.isSubmitting
                                ? 'Submitting…'
                                : 'Submit verification',
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

  Widget _registrarField() => DropdownButtonFormField<String>(
        key: const Key('folio-registrar-field'),
        initialValue: _registrar,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Registrar'),
        items: const [
          DropdownMenuItem(value: 'CAMS', child: Text('CAMS')),
          DropdownMenuItem(value: 'KFINTECH', child: Text('KFintech')),
        ],
        onChanged: widget.isSubmitting
            ? null
            : (value) => setState(() => _registrar = value),
        validator: (value) => value == null ? 'Select a registrar.' : null,
      );

  Widget _folioField() => TextFormField(
        key: const Key('folio-number-field'),
        controller: _folioController,
        enabled: !widget.isSubmitting,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Folio number'),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Enter a folio number.'
            : null,
      );

  Widget _relationshipField() =>
      DropdownButtonFormField<FolioHolderRelationship>(
        key: const Key('folio-relationship-field'),
        initialValue: _relationship,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Holder relationship'),
        items: const [
          DropdownMenuItem(
            value: FolioHolderRelationship.soleHolder,
            child: Text('Sole holder'),
          ),
          DropdownMenuItem(
            value: FolioHolderRelationship.jointHolder,
            child: Text('Joint holder'),
          ),
          DropdownMenuItem(
            value: FolioHolderRelationship.guardianForMinor,
            child: Text('Guardian for minor'),
          ),
        ],
        onChanged: widget.isSubmitting
            ? null
            : (value) => setState(() => _relationship = value),
        validator: (value) => value == null ? 'Select a relationship.' : null,
      );
}
