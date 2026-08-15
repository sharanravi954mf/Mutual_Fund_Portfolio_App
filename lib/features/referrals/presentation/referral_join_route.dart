import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../application/referral_attribution_controller.dart';

class ReferralJoinRoute {
  const ReferralJoinRoute._();

  static String? referralCodeFrom(String? routeName) {
    if (routeName == null) return null;
    final uri = Uri.tryParse(routeName);
    if (uri == null || uri.path != '/join') return null;

    final values = uri.queryParametersAll['ref'];
    if (values == null || values.length != 1) return null;
    final code = values.single;
    if (code.isEmpty || code.length > 512) return null;
    return code;
  }
}

class ReferralJoinEntry extends StatefulWidget {
  const ReferralJoinEntry({
    required this.referralCode,
    required this.child,
    super.key,
  });

  final String referralCode;
  final Widget child;

  @override
  State<ReferralJoinEntry> createState() => _ReferralJoinEntryState();
}

class _ReferralJoinEntryState extends State<ReferralJoinEntry> {
  bool _captured = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_captured) return;
    _captured = true;

    final attribution = context.read<ReferralAttributionController>();
    final auth = context.read<AuthProvider>();
    attribution.capture(widget.referralCode);
    unawaited(
      attribution.synchronize(
        userId: auth.user?.id,
        profile: auth.userProfile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class ReferralAttributionLifecycle extends StatefulWidget {
  const ReferralAttributionLifecycle({required this.child, super.key});

  final Widget child;

  @override
  State<ReferralAttributionLifecycle> createState() =>
      _ReferralAttributionLifecycleState();
}

class _ReferralAttributionLifecycleState
    extends State<ReferralAttributionLifecycle> {
  AuthProvider? _auth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (identical(auth, _auth)) return;
    _auth?.removeListener(_synchronize);
    _auth = auth..addListener(_synchronize);
    _synchronize();
  }

  void _synchronize() {
    final auth = _auth;
    if (auth == null || !mounted) return;
    unawaited(
      context.read<ReferralAttributionController>().synchronize(
            userId: auth.user?.id,
            profile: auth.userProfile,
          ),
    );
  }

  @override
  void dispose() {
    _auth?.removeListener(_synchronize);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
