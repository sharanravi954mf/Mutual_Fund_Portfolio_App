import 'package:flutter/material.dart';

import 'loan_part_payment_screen.dart';

/// Presentation metadata only. Every calculator owns an independent domain.
class CalculatorDefinition {
  const CalculatorDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.builder,
  });
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final WidgetBuilder builder;
}

final calculatorCatalog = List<CalculatorDefinition>.unmodifiable([
  CalculatorDefinition(
    id: 'loan-part-payment',
    title: 'Loan Part Payment Calculator',
    description:
        'See how a loan part payment can reduce your EMI or remaining tenure.',
    icon: Icons.account_balance_outlined,
    builder: (_) => const LoanPartPaymentScreen(),
  ),
]);
