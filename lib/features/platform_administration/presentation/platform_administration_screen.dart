import '../mfa/mfa_repository.dart';
import '../mfa/platform_security_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../mfd_applications/data/mfd_application_repository.dart';
import '../../mfd_applications/presentation/mfd_application_screens.dart';

/// Independent platform context; application review never loads tenant data.
class PlatformAdministrationScreen extends StatefulWidget {
  const PlatformAdministrationScreen(
      {super.key, this.mfdRepository, this.mfaRepository});

  final MfdApplicationRepository? mfdRepository;
  final MfaRepository? mfaRepository;

  @override
  State<PlatformAdministrationScreen> createState() =>
      _PlatformAdministrationScreenState();
}

class _PlatformAdministrationScreenState
    extends State<PlatformAdministrationScreen> {
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
            onPressed: auth.refreshPlatformContext),
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
                          repository: widget.mfdRepository,
                          mfaRepository: widget.mfaRepository)))
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
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPlatformSecurity(context,
                  repository: widget.mfaRepository),
              subtitle: Text(!auth.platformContextCurrent
                  ? 'Checking current security status.'
                  : platform.stepUpVerified
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
