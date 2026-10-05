import 'package:flutter/material.dart';

import '../models/loan_part_payment.dart';
import 'amortization_schedule_pager.dart';

/// Only one 12-month page is mounted, irrespective of total schedule length.
class LoanAmortizationSchedule extends StatefulWidget {
  const LoanAmortizationSchedule(
      {super.key, required this.result, required this.calculatedAt});
  final LoanPartPaymentResult result;
  final DateTime calculatedAt;

  @override
  State<LoanAmortizationSchedule> createState() =>
      _LoanAmortizationScheduleState();
}

class _LoanAmortizationScheduleState extends State<LoanAmortizationSchedule> {
  bool _reduceTenure = false;
  int _selectionRevision = 0;

  @override
  void didUpdateWidget(covariant LoanAmortizationSchedule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.result, widget.result)) {
      _reduceTenure = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schedule = _reduceTenure
        ? widget.result.sameEmi.schedule
        : widget.result.sameTenure.schedule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Month-wise repayment schedule',
            style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('The part payment is applied now, before the next EMI.'),
        const SizedBox(height: 8),
        const Text(
            'Calendar months are illustrative. This estimate assumes the part payment is applied before your next EMI; your lender’s actual EMI date may differ.'),
        const SizedBox(height: 16),
        if (schedule.isEmpty)
          const Text(
              'No future EMI schedule — the entered part payment fully repays the outstanding principal.')
        else ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final tenure in [false, true])
              Semantics(
                label: tenure
                    ? 'Show reduced tenure schedule'
                    : 'Show reduced EMI schedule',
                selected: _reduceTenure == tenure,
                child: ChoiceChip(
                  key: ValueKey(tenure ? 'schedule-tenure' : 'schedule-emi'),
                  label: Text(tenure ? 'Reduced tenure' : 'Reduced EMI'),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  selected: _reduceTenure == tenure,
                  onSelected: (_) => setState(() {
                    _reduceTenure = tenure;
                    _selectionRevision++;
                  }),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          AmortizationSchedulePager(
            key: ValueKey(_selectionRevision),
            schedule: schedule,
            calculatedAt: widget.calculatedAt,
          ),
        ],
      ],
    );
  }
}
