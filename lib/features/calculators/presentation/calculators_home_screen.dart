import 'package:flutter/material.dart';

import 'calculator_catalog.dart';

/// Shared entry point, independent of Explorer, Investor and Advisor roles.
class CalculatorsHomeScreen extends StatelessWidget {
  const CalculatorsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Calculators')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Plan with confidence',
                    style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Text(
                    'Explore estimates to help you understand your financial choices.'),
                const SizedBox(height: 24),
                for (final calculator in calculatorCatalog)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Semantics(
                      button: true,
                      child: InkWell(
                        key: ValueKey(calculator.id),
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: calculator.builder,
                        )),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(calculator.icon,
                                  size: 32, color: theme.colorScheme.primary),
                              const SizedBox(height: 16),
                              Text(calculator.title,
                                  style: theme.textTheme.titleLarge),
                              const SizedBox(height: 8),
                              Text(calculator.description),
                              const SizedBox(height: 16),
                              const Text('Open calculator →'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text('More calculators will be added here.',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
