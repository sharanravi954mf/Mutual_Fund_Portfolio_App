import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../providers/auth_provider.dart';
import '../../investor_identity/models/user_account.dart';
import '../../investor_identity/models/user_profile.dart';
import '../data/nse_pending_storage.dart';
import '../data/supabase_nse_read_repository.dart';
import '../domain/nse_models.dart';
import 'nse_integration_controller.dart';
import 'nse_integration_page.dart';

class NseConsoleAccess {
  const NseConsoleAccess._();
  static const enabled = bool.fromEnvironment('NSE_CONSOLE_ENABLED') &&
      String.fromEnvironment('MONEYBOWL_ENV') == 'dev';
  static bool visible(AuthProvider auth) =>
      enabled &&
      auth.isAuthenticated &&
      auth.accountState == AccountState.advisor &&
      auth.userProfile?.isActive == true &&
      [UserRole.advisor, UserRole.admin].contains(auth.userProfile?.role);
}

class NseIntegrationEntry extends StatelessWidget {
  const NseIntegrationEntry({this.target, this.operation, super.key});
  final String? target, operation;
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!NseConsoleAccess.visible(auth) ||
        (target != null && !nseUuidPattern.hasMatch(target!)) ||
        (operation != null && !nseUuidPattern.hasMatch(operation!))) {
      return Scaffold(
          appBar: AppBar(title: const Text('NSE Integration')),
          body: Center(
              child: TextButton(
                  onPressed: () => Navigator.of(context)
                      .pushNamedAndRemoveUntil('/', (_) => false),
                  child: const Text(
                      'Console unavailable · Return to dashboard'))));
    }
    return ChangeNotifierProvider(
        key: ValueKey(auth.user!.id),
        create: (_) => NseIntegrationController(
            repository: SupabaseNseReadRepository(Supabase.instance.client),
            storage: NsePendingStorage(auth.user!.id)),
        child: Builder(
            builder: (context) => NseIntegrationPage(
                controller: context.read<NseIntegrationController>(),
                initialTarget: target,
                initialOperation: operation)));
  }
}

/// Clear tab-scoped pending requests on sign-out, even when the console is closed.
class NseSessionLifecycle extends StatefulWidget {
  const NseSessionLifecycle({required this.child, super.key});
  final Widget child;
  @override
  State<NseSessionLifecycle> createState() => _NseSessionLifecycleState();
}

class _NseSessionLifecycleState extends State<NseSessionLifecycle> {
  AuthProvider? _auth;
  String? _userId;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (identical(auth, _auth)) return;
    _auth?.removeListener(_changed);
    _auth = auth;
    _userId = auth.user?.id;
    auth.addListener(_changed);
  }

  void _changed() {
    final current = _auth?.user?.id;
    if (_userId != null && current != _userId) {
      NsePendingStorage(_userId!).clear();
    }
    _userId = current;
  }

  @override
  void dispose() {
    _auth?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
