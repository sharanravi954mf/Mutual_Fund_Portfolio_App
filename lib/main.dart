import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/admin_dashboard.dart';
import 'screens/client_dashboard.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Retrieve environment variables via --dart-define (or fall back to placeholder values)
  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder-project.supabase.co',
  );
  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'placeholder-anonymous-key-here',
  );

  // Initialize Supabase. Catching errors silently in case variables aren't defined yet
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  } catch (e) {
    // Supabase can fail to initialize if placeholder values are used.
    // We continue so the app shell can run and display connection messages.
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode(context);
    final colors = AppThemeColors(isDark);

    return MaterialApp(
      title: 'Sharan Fincorp',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.getThemeMode(),
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: colors.primary,
        scaffoldBackgroundColor: colors.background,
        colorScheme: ColorScheme.light(
          primary: colors.primary,
          secondary: colors.secondary,
          background: colors.background,
          surface: colors.surface,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: colors.primary,
        scaffoldBackgroundColor: const Color(0xFF0F0C20),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE94057),
          secondary: Color(0xFF8A2387),
          background: Color(0xFF0F0C20),
          surface: Color(0xFF151030),
        ),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    // 1. Unauthenticated -> Show Login Screen
    if (!authProvider.isAuthenticated) {
      return const LoginScreen();
    }

    // 2. Loading Session/Role -> Show Premium Spinner
    if (authProvider.isLoading) {
      return const LoadingScreen();
    }

    // 3. Authenticated -> Route based on profiles role
    final role = authProvider.role;
    if (role == 'admin') {
      return const AdminDashboard();
    } else if (role == 'client') {
      return const ClientDashboard();
    }

    // 4. Authenticated but Role not found/registered yet
    return const UnrecognizedRoleScreen();
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F0C20), Color(0xFF151030)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE94057)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Establishing Secure Connection...",
                style: GoogleFonts.inter(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UnrecognizedRoleScreen extends StatelessWidget {
  const UnrecognizedRoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFF27121), size: 64),
              const SizedBox(height: 24),
              Text(
                "Role Not Assigned",
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Your account is authenticated, but no matching role has been found in profiles. Please contact your system administrator.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text("Sign Out"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94057),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () {
                  authProvider.signOut();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
