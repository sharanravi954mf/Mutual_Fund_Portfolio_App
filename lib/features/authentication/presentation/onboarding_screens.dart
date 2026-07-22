import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../investor_verification/presentation/verification_status_screen.dart';

class ExplorerHomeScreen extends StatelessWidget {
  const ExplorerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const modules = [
      (Icons.article_outlined, 'Factsheets', 'Fund information and updates'),
      (Icons.search_outlined, 'Fund Search', 'Explore mutual fund schemes'),
      (Icons.school_outlined, 'Learn', 'Educational content and guidance'),
      (Icons.calculate_outlined, 'Calculators', 'Plan and compare investments'),
      (
        Icons.support_agent_outlined,
        'Contact Advisor',
        'Talk to Sharan Fincorp'
      ),
      (
        Icons.settings_outlined,
        'Settings & Profile',
        'Language, theme, and profile'
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sharan Fincorp'),
        actions: [
          TextButton.icon(
            onPressed: () => context.read<AuthProvider>().signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Welcome to Sharan Fincorp.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'You can explore the platform before linking any investments.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: modules
                      .map(
                        (module) => SizedBox(
                          width: 260,
                          child: Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ExplorerModuleScreen(
                                    title: module.$2,
                                    description: module.$3,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(module.$1, size: 30),
                                    const SizedBox(height: 16),
                                    Text(
                                      module.$2,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(module.$3),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ExplorerModuleScreen extends StatelessWidget {
  const ExplorerModuleScreen({
    required this.title,
    required this.description,
    super.key,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(description),
                const SizedBox(height: 24),
                const Text(
                  'This area is available without portfolio access. Your investments remain private until they are securely linked.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PortfolioLinkingScreen extends StatefulWidget {
  const PortfolioLinkingScreen({super.key});

  @override
  State<PortfolioLinkingScreen> createState() => _PortfolioLinkingScreenState();
}

class _PortfolioLinkingScreenState extends State<PortfolioLinkingScreen> {
  bool _showVerificationExplanation = false;

  Future<void> _chooseExplorer() async {
    await context.read<AuthProvider>().chooseExplorer();
    if (!mounted) return;
    _showErrorIfNeeded();
  }

  Future<void> _beginLinking() async {
    await context.read<AuthProvider>().beginPortfolioLinking();
    if (!mounted) return;
    setState(() => _showVerificationExplanation = true);
    _showErrorIfNeeded();
  }

  void _showErrorIfNeeded() {
    final message = context.read<AuthProvider>().errorMessage;
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio linking'),
        actions: [
          TextButton.icon(
            onPressed: authProvider.isLoading
                ? null
                : () => context.read<AuthProvider>().signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _showVerificationExplanation
                  ? const _VerificationExplanation()
                  : _ChoiceCard(
                      isLoading: authProvider.isLoading,
                      onExplorer: _chooseExplorer,
                      onLinking: _beginLinking,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.isLoading,
    required this.onExplorer,
    required this.onLinking,
  });

  final bool isLoading;
  final Future<void> Function() onExplorer;
  final Future<void> Function() onLinking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "We couldn't automatically locate your investments.",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              'Do you already invest through Sharan Fincorp?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: isLoading ? null : onLinking,
              icon: const Icon(Icons.account_balance_outlined),
              label: const Align(
                alignment: Alignment.centerLeft,
                child: Text('Yes, I already invest'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isLoading ? null : onExplorer,
              icon: const Icon(Icons.explore_outlined),
              label: const Align(
                alignment: Alignment.centerLeft,
                child: Text("No, I'm just exploring"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationExplanation extends StatelessWidget {
  const _VerificationExplanation();

  @override
  Widget build(BuildContext context) {
    return const VerificationStatusScreen();
  }
}
