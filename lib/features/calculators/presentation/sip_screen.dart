import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/sip_calculator.dart';
import '../models/sip.dart';
import 'sip_controller.dart';

class SipScreen extends StatefulWidget {
  const SipScreen({super.key, this.clock});
  final DateTime Function()? clock;

  @override
  State<SipScreen> createState() => _SipScreenState();
}

class _SipScreenState extends State<SipScreen> {
  late final _controller = SipController(clock: widget.clock);
  late final _fields = {
    for (final field in SipInputField.values)
      field: TextEditingController(text: _controller.value(field))
  };
  final _focus = {for (final field in SipInputField.values) field: FocusNode()};
  final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  final _resultsKey = GlobalKey();
  final _date = DateFormat('dd MMM yyyy', 'en_US');

  @override
  void dispose() {
    _controller.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    for (final focus in _focus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  void _calculate() {
    _controller.calculate();
    if (_controller.errors.isNotEmpty) {
      _focus[_controller.errors.keys.first]!.requestFocus();
    } else if (_controller.result != null) {
      FocusScope.of(context).unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final resultContext = _resultsKey.currentContext;
        if (mounted && resultContext != null) {
          Scrollable.ensureVisible(resultContext,
              duration: const Duration(milliseconds: 200));
        }
      });
    }
  }

  void _reset() {
    _controller.reset();
    for (final entry in _fields.entries) {
      entry.value.text = _controller.value(entry.key);
    }
    _focus[SipInputField.initialInvestment]!.requestFocus();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate:
          SipController.parseDate(_fields[SipInputField.lumpSumDate]!.text) ??
              DateTime.now(),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: 'Lump sum investment date',
    );
    if (!mounted || selected == null) return;
    final value = DateFormat('yyyy-MM-dd').format(selected);
    _fields[SipInputField.lumpSumDate]!.text = value;
    _controller.update(SipInputField.lumpSumDate, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('SIP Calculator')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('SIP Calculator',
                        style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    const Text(
                        'Estimate how your initial investment, monthly SIP and optional lump sum could grow over time.'),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Investment Details',
                                style: theme.textTheme.titleLarge),
                            const SizedBox(height: 16),
                            _ResponsivePair(
                              first: _field(SipInputField.initialInvestment,
                                  'Initial Investment Amount',
                                  prefix: '₹ '),
                              second: _field(SipInputField.monthlySip,
                                  'Monthly SIP Amount',
                                  prefix: '₹ '),
                            ),
                            const SizedBox(height: 16),
                            _field(SipInputField.tenure, 'SIP Tenure',
                                suffix: _controller.tenureUnit.name),
                            const SizedBox(height: 16),
                            const Text('Tenure unit'),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final unit in SipTenureUnit.values)
                                Semantics(
                                  label: unit == SipTenureUnit.months
                                      ? 'Tenure in months'
                                      : 'Tenure in years',
                                  selected: _controller.tenureUnit == unit,
                                  child: ChoiceChip(
                                    key: ValueKey('tenure-${unit.name}'),
                                    label: Text(unit == SipTenureUnit.months
                                        ? 'Months'
                                        : 'Years'),
                                    selected: _controller.tenureUnit == unit,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.padded,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                                    onSelected: (_) {
                                      if (unit != _controller.tenureUnit) {
                                        _fields[SipInputField.tenure]!.clear();
                                        _controller.changeTenureUnit(unit);
                                      }
                                    },
                                  ),
                                ),
                            ]),
                            const SizedBox(height: 16),
                            _field(SipInputField.annualRoi,
                                'Expected ROI (% p.a.)',
                                suffix: '% p.a.'),
                            const SizedBox(height: 16),
                            _ResponsivePair(
                              first: _field(
                                  SipInputField.lumpSum, 'Lump Sum Amount',
                                  prefix: '₹ '),
                              second: _field(SipInputField.lumpSumDate,
                                  'Lump Sum Investment Date'),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                                'The plan starts on the calculation date. Its calendar month counts as month 1, and the plan ends on the last day of its final month. Initial investment is invested at plan start. Each monthly SIP is invested at the beginning of its period. A lump sum is added before the return in its selected calendar month. Each period earns one full monthly return; there is no daily proration.'),
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              children: [
                                FilledButton(
                                  key: const ValueKey('calculate'),
                                  style: FilledButton.styleFrom(
                                      minimumSize: const Size(120, 48)),
                                  onPressed: _calculate,
                                  child: const Text('Calculate'),
                                ),
                                OutlinedButton(
                                  key: const ValueKey('reset'),
                                  style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(80, 48)),
                                  onPressed: _reset,
                                  child: const Text('Reset'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                                'Your entries stay on this screen and are not saved or sent.',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                    if (_controller.calculationError case final error?)
                      Semantics(liveRegion: true, child: Text(error)),
                    if (_controller.result case final result?) ...[
                      const SizedBox(height: 24),
                      _results(context, result),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(SipInputField field, String label,
      {String? prefix, String? suffix}) {
    final isTenure = field == SipInputField.tenure;
    final isDate = field == SipInputField.lumpSumDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          child: TextField(
            key: ValueKey(field.name),
            controller: _fields[field],
            focusNode: _focus[field],
            keyboardType: isDate
                ? TextInputType.datetime
                : TextInputType.numberWithOptions(decimal: !isTenure),
            textInputAction:
                isDate ? TextInputAction.done : TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (value) => _controller.update(field, value),
            onSubmitted: (_) {
              if (isDate) {
                _calculate();
              } else {
                _focus[SipInputField.values[field.index + 1]]!.requestFocus();
              }
            },
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              prefixText: prefix,
              suffixText: suffix,
              hintText: isDate ? 'YYYY-MM-DD' : null,
              helperText: isDate
                  ? 'Required for a lump sum above 0. Ignored when lump sum is 0.'
                  : null,
              helperMaxLines: 5,
              suffixIcon: isDate
                  ? IconButton(
                      key: const ValueKey('choose-lump-date'),
                      tooltip: 'Choose lump sum investment date',
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                    )
                  : null,
              errorText: _controller.errors[field],
              errorMaxLines: 8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _results(BuildContext context, SipResult result) {
    final theme = Theme.of(context);
    final money = _currency.format;
    return Column(
      key: _resultsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child:
              Text('Your estimated results', style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 16),
        Card(
          key: const ValueKey('sip-summary'),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Total Fund Value'),
                _amount(money(result.totalFundValue)),
                const SizedBox(height: 16),
                const Text('Amount Invested'),
                _amount(money(result.amountInvested)),
                const SizedBox(height: 16),
                const Text('Estimated Returns'),
                _amount(money(result.estimatedReturns)),
                const SizedBox(height: 16),
                const Text('SIP tenure'),
                Text(result.input.tenureUnit == SipTenureUnit.years
                    ? '${result.input.tenure} ${result.input.tenure == 1 ? 'year' : 'years'} · ${result.normalizedMonths} months'
                    : '${result.normalizedMonths} months'),
                const SizedBox(height: 8),
                Text(
                    'Plan: ${_date.format(result.input.planStartDate)} – ${_date.format(result.input.planEndDate)}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
            'This estimate assumes constant monthly compounding with contributions before monthly returns. It excludes taxes, exit load and fees. Actual investment returns vary and are not guaranteed. This estimate is not investment advice.'),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _amount(String value) => Text(
        value,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        if (constraints.maxWidth >= 720 * scale) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: first),
            const SizedBox(width: 16),
            Expanded(child: second),
          ]);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              const SizedBox(height: 16),
              second,
            ]);
      });
}
