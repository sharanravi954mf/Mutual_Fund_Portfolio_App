import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../mfd_applications/data/mfd_application_repository.dart';
import '../../mfd_applications/presentation/mfd_application_screens.dart';

/// Independent platform context; application review never loads tenant data.
class PlatformAdministrationScreen extends StatefulWidget {
  const PlatformAdministrationScreen({super.key, this.mfdRepository});

  final MfdApplicationRepository? mfdRepository;

  @override
  State<PlatformAdministrationScreen> createState() =>
      _PlatformAdministrationScreenState();
}

class _PlatformAdministrationScreenState
    extends State<PlatformAdministrationScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AuthProvider>().refreshIdentity();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final platform = auth.platformContext;
    if (!platform.isPlatformAdmin) {
      return const Scaffold(
          body: Center(child: Text('Platform access unavailable')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Platform Administration'), actions: [
        IconButton(
            tooltip: 'Refresh access',
            icon: const Icon(Icons.refresh),
            onPressed: auth.refreshIdentity),
        IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: auth.signOut),
      ]),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text('MoneyBowl Platform Administration',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          const ListTile(
              leading: Icon(Icons.admin_panel_settings_outlined),
              title: Text('Platform status'),
              subtitle: Text('Platform administrator access is active.')),
          ListTile(
              leading: const Icon(Icons.business_outlined),
              title: const Text('MFD applications'),
              onTap: platform.capabilities.contains('mfd_applications.review')
                  ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => MfdReviewQueueScreen(
                          repository: widget.mfdRepository)))
                  : null,
              subtitle: Text(platform.capabilities
                      .contains('mfd_applications.review')
                  ? 'View applications and review submitted registration claims.'
                  : 'Applications and decisions are unavailable. Review permission has not been granted.')),
          ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Signed-in account'),
              subtitle: Text(auth.user?.email ?? 'Authenticated operator')),
          ListTile(
              leading: const Icon(Icons.security),
              title: const Text('Account security'),
              subtitle: Text(platform.stepUpVerified
                  ? 'MFA verified for this session.'
                  : platform.mfaEnrolled
                      ? 'Complete MFA verification before sensitive platform actions.'
                      : 'Enroll and verify MFA before sensitive platform actions.')),
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'MFD workspaces and investor data require separate authorization.')),
        ]),
      )),
    );
  }
}
