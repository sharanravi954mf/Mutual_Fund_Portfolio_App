import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/amortization_row.dart';

/// Only one 12-month page is mounted, irrespective of total schedule length.
class AmortizationSchedulePager extends StatefulWidget {
  const AmortizationSchedulePager(
      {super.key, required this.schedule, required this.calculatedAt});
  final List<AmortizationRow> schedule;
  final DateTime calculatedAt;

  @override
  State<AmortizationSchedulePager> createState() =>
      _AmortizationSchedulePagerState();
}

class _AmortizationSchedulePagerState extends State<AmortizationSchedulePager> {
  static const _pageSize = 12;
  final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  // English month names use intl's bundled default date symbols; currency
  // retains en_IN grouping without needing asynchronous locale initialization.
  final _month = DateFormat('MMM yyyy', 'en_US');
  int _page = 0;

  @override
  void didUpdateWidget(covariant AmortizationSchedulePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.schedule, widget.schedule)) {
      _page = 0;
    }
  }

  String _label(AmortizationRow row) {
    final calculated = widget.calculatedAt;
    // Calendar arithmetic, not a duration or an invented lender due date.
    final month = DateTime(calculated.year, calculated.month + row.monthNumber);
    return 'Month ${row.monthNumber} · ${_month.format(month)}';
  }

  @override
  Widget build(BuildContext context) {
    final schedule = widget.schedule;
    if (schedule.isEmpty) return const SizedBox.shrink();
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, schedule.length);
    final visible =
        schedule.skip(start).take(_pageSize).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
            liveRegion: true,
            child: Text('Months ${start + 1}–$end of ${schedule.length}',
                key: const ValueKey('schedule-range'))),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 8, children: [
          Semantics(
            label: 'Previous schedule page',
            child: OutlinedButton(
              key: const ValueKey('schedule-previous'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed: _page == 0 ? null : () => setState(() => _page--),
              child: const Text('Previous'),
            ),
          ),
          Semantics(
            label: 'Next schedule page',
            child: OutlinedButton(
              key: const ValueKey('schedule-next'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
              onPressed:
                  end == schedule.length ? null : () => setState(() => _page++),
              child: const Text('Next'),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
          return constraints.maxWidth >= 900 * scale
              ? _table(visible)
              : Column(children: [for (final row in visible) _monthCard(row)]);
        }),
      ],
    );
  }

  List<(String, double)> _amounts(AmortizationRow row) => [
        ('Opening outstanding', row.openingOutstanding),
        ('EMI / payment', row.payment),
        ('Interest', row.interestComponent),
        ('Principal repaid', row.principalComponent),
        ('Closing outstanding', row.closingOutstanding),
      ];

  Widget _monthCard(AmortizationRow row) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_label(row),
                key: ValueKey('schedule-month-${row.monthNumber}'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final (label, value) in _amounts(row))
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('$label: ${_currency.format(value)}')),
          ]),
        ),
      );

  Widget _table(List<AmortizationRow> rows) => SingleChildScrollView(
        // Local overflow protection for unusually wide formatted amounts.
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 12,
          headingTextStyle: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontWeight: FontWeight.w600),
          dataTextStyle: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          columns: const [
            DataColumn(label: Text('Month')),
            DataColumn(label: Text('Opening\noutstanding'), numeric: true),
            DataColumn(label: Text('EMI /\npayment'), numeric: true),
            DataColumn(label: Text('Interest'), numeric: true),
            DataColumn(label: Text('Principal\nrepaid'), numeric: true),
            DataColumn(label: Text('Closing\noutstanding'), numeric: true),
          ],
          rows: [
            for (final row in rows)
              DataRow(cells: [
                DataCell(Text(_label(row),
                    key: ValueKey('schedule-month-${row.monthNumber}'))),
                for (final (label, value) in _amounts(row))
                  DataCell(
                    Semantics(
                        label: '$label: ${_currency.format(value)}',
                        excludeSemantics: true,
                        child: Text(_currency.format(value))),
                  ),
              ])
          ],
        ),
      );
}
