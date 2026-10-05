import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/emi_calculator.dart';
import '../models/emi.dart';
import 'emi_controller.dart';
import 'amortization_schedule_pager.dart';

class EmiScreen extends StatefulWidget {
  const EmiScreen({super.key, this.clock});
  final DateTime Function()? clock;

  @override
  State<EmiScreen> createState() => _EmiScreenState();
}

class _EmiScreenState extends State<EmiScreen> {
  late final _controller = EmiController(clock: widget.clock);
  final _fields = {
    for (final field in EmiInputField.values) field: TextEditingController()
  };
  final _focus = {for (final field in EmiInputField.values) field: FocusNode()};
  final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  final _resultsKey = GlobalKey();

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
    for (final field in _fields.values) {
      field.clear();
    }
    _controller.reset();
    _focus[EmiInputField.principal]!.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('EMI Calculator')),
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
                    Text('EMI Calculator',
                        style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    const Text(
                        'Estimate your monthly loan repayment and see how principal and interest change over time.'),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Your loan details',
                                style: theme.textTheme.titleLarge),
                            const SizedBox(height: 16),
                            _ResponsivePair(
                              first: _field(
                                  EmiInputField.principal, 'Loan amount',
                                  prefix: '₹ '),
                              second: _field(
                                  EmiInputField.tenure, 'Loan tenure',
                                  suffix: _controller.tenureUnit.name),
                            ),
                            const SizedBox(height: 16),
                            const Text('Tenure unit'),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final unit in TenureUnit.values)
                                Semantics(
                                  label: unit == TenureUnit.months
                                      ? 'Tenure in months'
                                      : 'Tenure in years',
                                  selected: _controller.tenureUnit == unit,
                                  child: ChoiceChip(
                                    key: ValueKey('tenure-${unit.name}'),
                                    label: Text(unit == TenureUnit.months
                                        ? 'Months'
                                        : 'Years'),
                                    selected: _controller.tenureUnit == unit,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.padded,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                                    onSelected: (_) {
                                      if (unit != _controller.tenureUnit) {
                                        _fields[EmiInputField.tenure]!.clear();
                                        _controller.changeTenureUnit(unit);
                                      }
                                    },
                                  ),
                                ),
                            ]),
                            const SizedBox(height: 16),
                            _field(EmiInputField.annualRate,
                                'Rate of interest (% p.a.)',
                                suffix: '% p.a.'),
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

  Widget _field(EmiInputField field, String label,
      {String? prefix, String? suffix}) {
    final isTenure = field == EmiInputField.tenure;
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
            keyboardType: TextInputType.numberWithOptions(decimal: !isTenure),
            textInputAction: field == EmiInputField.annualRate
                ? TextInputAction.done
                : TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (value) => _controller.update(field, value),
            onSubmitted: (_) {
              if (field == EmiInputField.annualRate) {
                _calculate();
              } else {
                _focus[EmiInputField.values[field.index + 1]]!.requestFocus();
              }
            },
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              prefixText: prefix,
              suffixText: suffix,
              errorText: _controller.errors[field],
              errorMaxLines: 8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _results(BuildContext context, EmiResult result) {
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
          key: const ValueKey('emi-summary'),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Monthly EMI'),
                _amount(money(result.monthlyEmi)),
                const SizedBox(height: 16),
                const Text('Total interest payable'),
                _amount(money(result.totalInterest)),
                const SizedBox(height: 16),
                const Text('Total repayment amount'),
                _amount(money(result.totalRepayment)),
                const SizedBox(height: 16),
                const Text('Loan tenure'),
                Text(result.input.tenureUnit == TenureUnit.years
                    ? '${result.input.tenure} ${result.input.tenure == 1 ? 'year' : 'years'} · ${result.normalizedMonths} months'
                    : '${result.normalizedMonths} months'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Month-wise repayment schedule',
            style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
            "Calendar months are illustrative. The first row represents the next monthly EMI; your lender's actual EMI date may differ."),
        const SizedBox(height: 16),
        AmortizationSchedulePager(
          key: ObjectKey(result),
          schedule: result.schedule,
          calculatedAt: _controller.calculatedAt!,
        ),
        const SizedBox(height: 24),
        const Text(
            "Estimate assumes a monthly reducing-balance loan with a constant interest rate. Your lender's actual EMI and schedule may differ because of payment dates, daily-interest methods, rate resets, fees, insurance, taxes and rounding."),
        const SizedBox(height: 8),
        Text(
            'This estimate is not lender advice or a binding repayment schedule.',
            style: theme.textTheme.bodySmall),
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
