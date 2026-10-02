import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/authentication/application/email_signup_controller.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.signupController});
  final EmailSignupController? signupController;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final EmailSignupController _signup;
  Timer? _cooldownTicker;
  bool _signUp = false;
  bool _obscure = true;
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    _signup = widget.signupController ??
        EmailSignupController(
            SupabaseEmailSignupGateway(Supabase.instance.client));
    _signup.addListener(_changed);
    _cooldownTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => _changed());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cooldownTicker?.cancel();
    _signup.removeListener(_changed);
    if (widget.signupController == null) _signup.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _switch(bool signUp) {
    if (_signup.busy || _signingIn) return;
    _formKey.currentState?.reset();
    _password.clear();
    _confirm.clear();
    setState(() {
      _signUp = signUp;
      _obscure = true;
    });
  }

  Future<void> _submit() async {
    if (_signup.busy || _signingIn || !_formKey.currentState!.validate()) {
      return;
    }
    if (_signUp) {
      await _signup.submit(_email.text, _password.text);
      if (!mounted) return;
      if (_signup.pendingEmail != null) {
        _password.clear();
        _confirm.clear();
      }
    } else {
      setState(() => _signingIn = true);
      await context
          .read<AuthProvider>()
          .signIn(_email.text.trim(), _password.text);
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode(context);
    final colors = AppThemeColors(isDark);
    final busy = _signup.busy || _signingIn;
    final pending = _signUp && _signup.pendingEmail != null;
    InputDecoration decoration(String label, IconData icon) => InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(borderRadius: AppRadius.inputBorder),
          filled: true,
          fillColor: colors.surface,
          errorMaxLines: 2,
        );

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 48, color: colors.primary),
            const SizedBox(height: 16),
            Text('MoneyBowl',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary)),
            const SizedBox(height: 8),
            Text('Your investments. Your next chapter.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary)),
            const SizedBox(height: 24),
            Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: AppRadius.cardBorder,
                    border: Border.all(color: colors.border),
                    boxShadow: AppShadows.card(isDark)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Sign In')),
                          ButtonSegment(value: true, label: Text('Sign Up'))
                        ],
                        selected: {_signUp},
                        showSelectedIcon: false,
                        onSelectionChanged:
                            busy ? null : (value) => _switch(value.single),
                      ),
                      const SizedBox(height: 24),
                      if (auth.errorMessage != null) ...[
                        Semantics(
                            liveRegion: true,
                            child: Text(auth.errorMessage!,
                                style: TextStyle(color: colors.textPrimary))),
                        const SizedBox(height: 16),
                      ],
                      if (pending) ...[
                        Icon(Icons.mark_email_unread_outlined,
                            size: 44, color: colors.primary),
                        const SizedBox(height: 16),
                        Text('Check your email',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        Text(
                            'If this address can be registered, we sent a verification link to '
                            '${_signup.maskedEmail}. Open it to confirm your email before signing in.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        const Text(
                            'Check your spam folder too. Already verified, or opened the link on another device? Return to Sign In.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        OutlinedButton(
                            onPressed: busy || _signup.secondsRemaining > 0
                                ? null
                                : _signup.resend,
                            child: Text(_signup.secondsRemaining > 0
                                ? 'Resend in ${_signup.secondsRemaining}s'
                                : 'Resend verification email')),
                        TextButton(
                            onPressed: busy ? null : _signup.changeEmail,
                            child: const Text('Change email')),
                        TextButton(
                            onPressed: busy ? null : () => _switch(false),
                            child: const Text('Return to Sign In')),
                      ] else
                        Form(
                            key: _formKey,
                            child: AutofillGroup(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                  TextFormField(
                                      key: const Key('auth-email'),
                                      controller: _email,
                                      enabled: !busy,
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [
                                        AutofillHints.username,
                                        AutofillHints.email
                                      ],
                                      textInputAction: TextInputAction.next,
                                      decoration: decoration(
                                          _signUp
                                              ? 'Email'
                                              : 'Email or Mobile Number',
                                          Icons.person_outline),
                                      validator: (value) {
                                        if (!_signUp &&
                                            RegExp(r'^\+?[0-9 ()-]{10,}$')
                                                .hasMatch(
                                                    value?.trim() ?? '')) {
                                          return null;
                                        }
                                        return EmailSignupController
                                            .validateEmail(value);
                                      }),
                                  const SizedBox(height: 20),
                                  TextFormField(
                                      key: const Key('auth-password'),
                                      controller: _password,
                                      enabled: !busy,
                                      obscureText: _obscure,
                                      enableSuggestions: false,
                                      autocorrect: false,
                                      autofillHints: [
                                        _signUp
                                            ? AutofillHints.newPassword
                                            : AutofillHints.password
                                      ],
                                      onFieldSubmitted: (_) {
                                        if (!_signUp) _submit();
                                      },
                                      decoration: decoration(
                                              'Password', Icons.lock_outline)
                                          .copyWith(
                                              suffixIcon: IconButton(
                                                  tooltip: _obscure
                                                      ? 'Show password'
                                                      : 'Hide password',
                                                  onPressed: () => setState(
                                                      () =>
                                                          _obscure = !_obscure),
                                                  icon: Icon(_obscure
                                                      ? Icons
                                                          .visibility_outlined
                                                      : Icons
                                                          .visibility_off_outlined))),
                                      validator: (value) => _signUp
                                          ? EmailSignupController
                                              .validatePassword(value)
                                          : (value == null || value.isEmpty
                                              ? 'Enter your password'
                                              : null)),
                                  if (_signUp) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                        'Use 12–128 characters. A long, unique passphrase works well.'),
                                    const SizedBox(height: 20),
                                    TextFormField(
                                        key: const Key('auth-confirm'),
                                        controller: _confirm,
                                        enabled: !busy,
                                        obscureText: true,
                                        enableSuggestions: false,
                                        autocorrect: false,
                                        autofillHints: const [
                                          AutofillHints.newPassword
                                        ],
                                        onFieldSubmitted: (_) => _submit(),
                                        decoration: decoration(
                                            'Confirm password',
                                            Icons.lock_outline),
                                        validator: (value) =>
                                            value == _password.text
                                                ? null
                                                : 'Passwords must match'),
                                    const SizedBox(height: 16),
                                    const Text(
                                        'Verify your email to explore MoneyBowl. Existing investments are linked only after secure identity checks.'),
                                  ],
                                  const SizedBox(height: 24),
                                  FilledButton(
                                      key: const Key('auth-submit'),
                                      onPressed: busy ||
                                              (_signUp &&
                                                  _signup.secondsRemaining > 0)
                                          ? null
                                          : _submit,
                                      style: FilledButton.styleFrom(
                                          backgroundColor: colors.primary,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 16)),
                                      child: busy
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))
                                          : Text(_signUp
                                              ? 'Create Account'
                                              : 'Sign In')),
                                  if (_signUp && _signup.secondsRemaining > 0)
                                    Text(
                                        'You can try again in ${_signup.secondsRemaining}s.',
                                        textAlign: TextAlign.center),
                                ]))),
                      if (_signUp && _signup.message != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                            liveRegion: true, child: Text(_signup.message!)),
                      ],
                    ])),
            const SizedBox(height: 20),
            Text('Powered by Sharan Fincorp',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.textSecondary)),
          ]),
        ),
      ))),
    );
  }
}

extension PremiumRevealExtension on Widget {
  Widget premiumReveal({required int index, int staggerMs = 150}) {
    return animate(delay: Duration(milliseconds: index * staggerMs))
        .fadeIn(duration: 1000.ms, curve: Curves.easeInOutCubic)
        .blur(
            begin: const Offset(10, 10),
            end: Offset.zero,
            duration: 1000.ms,
            curve: Curves.easeInOutCubic)
        .slide(
            begin: const Offset(0, 0.2),
            end: Offset.zero,
            duration: 1000.ms,
            curve: Curves.easeInOutCubic);
  }
}
