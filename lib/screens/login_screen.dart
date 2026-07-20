import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import 'rupee_rain_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    authProvider.errorMessage ?? 'Authentication failed',
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode(context);
    final colors = AppThemeColors(isDark);

    return Scaffold(
      backgroundColor: colors.background,
      body: RupeeRainBackground(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: colors.background,
            gradient: isDark
                ? const LinearGradient(
                    colors: [
                      Color(0xFF0F0C20),
                      Color(0xFF151030),
                      Color(0xFF1E1747),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [
                      Color(0xFFF8F6F2),
                      Color(0xFFF2EEE7),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo Icon
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? null : colors.primary,
                            gradient: isDark
                                ? const LinearGradient(
                                    colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
                                  )
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: colors.primary.withValues(alpha: 0.25),
                                blurRadius: 20,
                                spreadRadius: 2,
                              )
                            ],
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                      ).premiumReveal(index: 0),
                      const SizedBox(height: 24),
                      
                      // Heading
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            "Sharan Fincorp",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Enter credentials to manage your investments",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ).premiumReveal(index: 1),
                      const SizedBox(height: 36),

                      // Card
                      Container(
                        padding: const EdgeInsets.all(28.0),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: AppRadius.cardBorder,
                          border: Border.all(
                            color: colors.border,
                            width: 1,
                          ),
                          boxShadow: AppShadows.card(isDark),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Email input label
                            Text(
                              "Email or Mobile Number",
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _emailController,
                              style: GoogleFonts.inter(color: colors.textPrimary),
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                hintText: "name@example.com or 9876543210",
                                hintStyle: GoogleFonts.inter(color: colors.textSecondary.withValues(alpha: 0.7)),
                                prefixIcon: Icon(Icons.person_outline, color: colors.textSecondary),
                                filled: true,
                                fillColor: isDark ? Colors.black.withValues(alpha: 0.2) : colors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: AppRadius.inputBorder,
                                  borderSide: BorderSide(color: colors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: AppRadius.inputBorder,
                                  borderSide: BorderSide(color: colors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: AppRadius.inputBorder,
                                  borderSide: BorderSide(color: colors.primary, width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return "Email or mobile number is required";
                                }
                                final trimmed = value.trim();
                                final isPhone = RegExp(r'^\d{3}').hasMatch(trimmed);
                                if (isPhone) {
                                  final cleanPhone = trimmed.replaceAll(RegExp(r'\D'), '');
                                  if (cleanPhone.length < 10) {
                                    return "Please enter a valid 10-digit mobile number";
                                  }
                                } else {
                                  if (!trimmed.contains('@')) {
                                    return "Email address must contain '@'";
                                  }
                                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(trimmed)) {
                                    return "Please enter a valid email address";
                                  }
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            // Password label
                            Text(
                              "Password",
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _passwordController,
                              style: GoogleFonts.inter(color: colors.textPrimary),
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                hintText: "••••••••",
                                hintStyle: GoogleFonts.inter(color: colors.textSecondary.withValues(alpha: 0.7)),
                                prefixIcon: Icon(Icons.lock_outlined, color: colors.textSecondary),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                    color: colors.textSecondary,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                filled: true,
                                fillColor: isDark ? Colors.black.withValues(alpha: 0.2) : colors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: AppRadius.inputBorder,
                                  borderSide: BorderSide(color: colors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: AppRadius.inputBorder,
                                  borderSide: BorderSide(color: colors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: AppRadius.inputBorder,
                                  borderSide: BorderSide(color: colors.primary, width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return "Password is required";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 32),

                            // Submit Button
                            ElevatedButton(
                              onPressed: authProvider.isLoading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppRadius.buttonBorder,
                                ),
                                backgroundColor: isDark ? Colors.transparent : colors.primary,
                                elevation: 0,
                              ).copyWith(
                                backgroundColor: WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.disabled)) {
                                    return colors.disabled;
                                  }
                                  return isDark ? Colors.transparent : colors.primary;
                                }),
                              ),
                              child: Ink(
                                decoration: (authProvider.isLoading || !isDark)
                                    ? null
                                    : BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
                                        ),
                                        borderRadius: AppRadius.buttonBorder,
                                      ),
                                child: Container(
                                  alignment: Alignment.center,
                                  child: authProvider.isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : Text(
                                          "Login",
                                          style: GoogleFonts.outfit(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ).premiumReveal(index: 2),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  }
}

extension PremiumRevealExtension on Widget {
  Widget premiumReveal({required int index, int staggerMs = 150}) {
    return this.animate(delay: Duration(milliseconds: index * staggerMs))
        .fadeIn(duration: 1000.ms, curve: Curves.easeInOutCubic)
        .blur(begin: const Offset(10, 10), end: Offset.zero, duration: 1000.ms, curve: Curves.easeInOutCubic)
        .slide(begin: const Offset(0, 0.2), end: Offset.zero, duration: 1000.ms, curve: Curves.easeInOutCubic);
  }
}
