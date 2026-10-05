import 'package:flutter/material.dart';

import 'loan_part_payment_screen.dart';
import 'emi_screen.dart';
import 'sip_screen.dart';
import '../income_tax/presentation/income_tax_screen.dart';

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
  CalculatorDefinition(
    id: 'emi',
    title: 'EMI Calculator',
    description:
        'Calculate your monthly EMI, total interest and complete repayment schedule.',
    icon: Icons.calculate_outlined,
    builder: (_) => const EmiScreen(),
  ),
  CalculatorDefinition(
    id: 'sip',
    title: 'SIP Calculator',
    description:
        'Estimate the growth of your monthly SIP, initial investment and optional lump sum.',
    icon: Icons.trending_up_outlined,
    builder: (_) => const SipScreen(),
  ),
  CalculatorDefinition(
    id: 'income-tax',
    title: 'Income Tax Calculator',
    description:
        'Compare Old and New Regime tax for supported resident-individual income. Unavailable combinations return no estimate.',
    icon: Icons.receipt_long_outlined,
    builder: (_) => const IncomeTaxScreen(),
  ),
]);
