import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';

/// Every pushed MFD route belongs to one account lifetime, including A -> B -> A.
mixin MfdAccountScope<T extends StatefulWidget> on State<T>
    implements WidgetsBindingObserver {
  late final AuthProvider scopeAuth;
  late final String? _owner;
  late final int _generation;
  bool _lost = false;
  bool foreground = true;
  bool get scopeCurrent =>
      mounted &&
      !_lost &&
      scopeAuth.isAuthenticated &&
      scopeAuth.user?.id == _owner &&
      scopeAuth.accountGeneration == _generation;
  @override
  void initState() {
    super.initState();
    scopeAuth = context.read<AuthProvider>();
    _owner = scopeAuth.user?.id;
    _generation = scopeAuth.accountGeneration;
    scopeAuth.addListener(_accountChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _accountChanged() {
    if (!scopeCurrent && !_lost) {
      _lost = true;
      releaseAccountState();
      if (mounted) setState(() {});
    }
  }

  void releaseAccountState() {}
  Future<void> resumeAccountState() async {}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (mounted) setState(() {});
    if (foreground && scopeCurrent) resumeAccountState();
  }

  @override
  void dispose() {
    scopeAuth.removeListener(_accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

const mfdAccountChanged = Scaffold(
    body: Center(
        child: Text(
            'Your signed-in account changed. Close this page and refresh.')));
