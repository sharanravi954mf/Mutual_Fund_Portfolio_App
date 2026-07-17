import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

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
                    authProvider.errorMessage ?? "Invalid credentials. Please try again.",
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
    final size = MediaQuery.of(context).size;
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0F0C20),
              Color(0xFF151030),
              Color(0xFF1E1747),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
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
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE94057).withOpacity(0.3),
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
                      ),
                      const SizedBox(height: 24),
                      
                      // Heading
                      Text(
                        "Fortress Wealth",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Enter credentials to manage your investments",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Glassmorphism Login Card
                      Container(
                        padding: const EdgeInsets.all(28.0),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Email input field
                            Text(
                              "Email Address",
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey.shade300,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _emailController,
                              style: GoogleFonts.inter(color: Colors.white),
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                hintText: "name@example.com",
                                hintStyle: GoogleFonts.inter(color: Colors.grey.shade600),
                                prefixIcon: Icon(Icons.mail_outline, color: Colors.grey.shade400),
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.2),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return "Email is required";
                                }
                                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                                  return "Please enter a valid email address";
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            // Password input field
                            Text(
                              "Password",
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey.shade300,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _passwordController,
                              style: GoogleFonts.inter(color: Colors.white),
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                hintText: "••••••••",
                                hintStyle: GoogleFonts.inter(color: Colors.grey.shade600),
                                prefixIcon: Icon(Icons.lock_outlined, color: Colors.grey.shade400),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                    color: Colors.grey.shade400,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.2),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
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
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                              ).copyWith(
                                backgroundColor: WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.disabled)) {
                                    return Colors.grey.shade800;
                                  }
                                  return null; // Handled by gradient container
                                }),
                              ),
                              child: Ink(
                                decoration: authProvider.isLoading
                                    ? null
                                    : BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
                                        ),
                                        borderRadius: BorderRadius.circular(14),
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
                      ),
                    ],
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
