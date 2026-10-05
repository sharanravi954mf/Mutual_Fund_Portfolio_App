import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/loan_part_payment_calculator.dart';
import '../models/loan_part_payment.dart';
import 'loan_part_payment_controller.dart';
import 'loan_amortization_schedule.dart';

class LoanPartPaymentScreen extends StatefulWidget {
  const LoanPartPaymentScreen({super.key, this.clock});
  final DateTime Function()? clock;

  @override
  State<LoanPartPaymentScreen> createState() => _LoanPartPaymentScreenState();
}

class _LoanPartPaymentScreenState extends State<LoanPartPaymentScreen> {
  late final _controller = LoanPartPaymentController(clock: widget.clock);
  final _fields = {
    for (final field in LoanInputField.values) field: TextEditingController()
  };
  final _focus = {
    for (final field in LoanInputField.values) field: FocusNode()
  };
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
    _focus[LoanInputField.principal]!.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Loan part payment')),
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
                    Text('Loan Part Payment Calculator',
                        style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    const Text(
                        'Estimate the impact of a one-time principal part payment.'),
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
                              first: _field(LoanInputField.principal,
                                  'Loan outstanding amount',
                                  prefix: '₹ '),
                              second: _field(LoanInputField.months,
                                  'Loan outstanding months',
                                  suffix: 'months'),
                            ),
                            const SizedBox(height: 16),
                            _ResponsivePair(
                              first: _field(LoanInputField.annualRate,
                                  'Rate of interest (% p.a.)',
                                  suffix: '% p.a.'),
                              second: _field(LoanInputField.partPayment,
                                  'Part payment amount',
                                  prefix: '₹ '),
                            ),
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
                            const Text(
                                'Current EMI is calculated from the outstanding amount, remaining tenure and interest rate entered above.'),
                            const SizedBox(height: 8),
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

  Widget _field(LoanInputField field, String label,
      {String? prefix, String? suffix}) {
    final isMonths = field == LoanInputField.months;
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
            keyboardType: TextInputType.numberWithOptions(decimal: !isMonths),
            textInputAction: field == LoanInputField.partPayment
                ? TextInputAction.done
                : TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (value) => _controller.update(field, value),
            onSubmitted: (_) {
              if (field == LoanInputField.partPayment) {
                _calculate();
              } else {
                _focus[LoanInputField.values[field.index + 1]]!.requestFocus();
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

  Widget _results(BuildContext context, LoanPartPaymentResult result) {
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
          key: const ValueKey('loan-summary'),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Current calculated EMI'),
                _amount(money(result.currentEmi)),
                const SizedBox(height: 16),
                Text(
                    'Estimated remaining interest without part payment: ${money(result.baselineRemainingInterest)}'),
                const Text(
                    'This is the comparison baseline for interest savings.'),
                const SizedBox(height: 8),
                Text(
                    'After part payment: Remaining principal ${money(result.remainingPrincipal)}'),
                if (result.isFullyRepaid) ...[
                  const SizedBox(height: 16),
                  const Text(
                      'Your entered part payment would fully repay the outstanding principal.'),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _ResponsivePair(
          first: _scenario(
            title: 'Reduce EMI',
            subtitle: 'Keep tenure same',
            label: 'Revised EMI',
            value: money(result.sameTenure.revisedEmi),
            interestSaved: result.sameTenure.interestSaved,
            details: [
              'Current calculated EMI: ${money(result.currentEmi)}',
              'Monthly EMI reduction: ${money(result.sameTenure.monthlyReduction)}',
              'Remaining tenure: ${result.isFullyRepaid ? 0 : result.input.months} months',
              'Estimated interest payable: ${money(result.sameTenure.totalInterest)}',
            ],
          ),
          second: _scenario(
            title: 'Reduce tenure',
            subtitle: 'Keep EMI same',
            label: 'Revised tenure',
            value: '${result.sameEmi.revisedMonths} months',
            interestSaved: result.sameEmi.interestSaved,
            details: [
              if (!result.isFullyRepaid)
                'EMI stays: ${money(result.currentEmi)}',
              if (result.isFullyRepaid) 'No further monthly payments.',
              'Tenure reduced by: ${result.sameEmi.monthsReduced} months',
              if (!result.isFullyRepaid &&
                  result.currentEmi - result.sameEmi.finalPayment >= 0.01)
                'Estimated final payment: ${money(result.sameEmi.finalPayment)}',
              'Estimated interest payable: ${money(result.sameEmi.totalInterest)}',
            ],
          ),
        ),
        const SizedBox(height: 24),
        LoanAmortizationSchedule(
          key: ObjectKey(result),
          result: result,
          calculatedAt: _controller.calculatedAt!,
        ),
        const SizedBox(height: 24),
        const Text(
            'Interest savings and month-wise schedules are estimates based on a monthly reducing-balance model. The part payment is assumed to be applied before the next EMI. Actual lender interest, EMI dates, rate resets, daily-interest calculation, fees, penalties and rounding may differ.'),
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

  Widget _scenario(
          {required String title,
          required String subtitle,
          required String label,
          required String value,
          required double interestSaved,
          required List<String> details}) =>
      Card(
        key: ValueKey(title),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(subtitle),
              const SizedBox(height: 24),
              Text(label),
              _amount(value),
              const SizedBox(height: 16),
              for (final detail in details)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(detail),
                ),
              const SizedBox(height: 8),
              Text('Interest saved: ${_currency.format(interestSaved)}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
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
