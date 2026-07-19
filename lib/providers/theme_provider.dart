import 'package:flutter/material.dart';

enum ThemeModeOption { light, dark, system }

class ThemeProvider extends ChangeNotifier {
  ThemeModeOption _themeModeOption = ThemeModeOption.light; // Light mode by default!

  ThemeModeOption get themeModeOption => _themeModeOption;

  void setThemeMode(ThemeModeOption mode) {
    _themeModeOption = mode;
    notifyListeners();
  }

  ThemeMode getThemeMode() {
    switch (_themeModeOption) {
      case ThemeModeOption.light:
        return ThemeMode.light;
      case ThemeModeOption.dark:
        return ThemeMode.dark;
      case ThemeModeOption.system:
      default:
        return ThemeMode.system;
    }
  }

  bool isDarkMode(BuildContext context) {
    if (_themeModeOption == ThemeModeOption.system) {
      final brightness = MediaQuery.platformBrightnessOf(context);
      return brightness == Brightness.dark;
    }
    return _themeModeOption == ThemeModeOption.dark;
  }
}

class AppThemeColors {
  final bool isDark;
  
  AppThemeColors(this.isDark);
  
  Color get primary => const Color(0xFFE94057);
  Color get secondary => const Color(0xFF8A2387);
  Color get accent => const Color(0xFFF27121);
  
  Color get background => isDark ? const Color(0xFF0F0C20) : const Color(0xFFF4F6FA);
  Color get surface => isDark ? const Color(0xFF151030) : const Color(0xFFFFFFFF);
  Color get surfaceAccent => isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.015);
  
  Color get border => isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200;
  Color get textPrimary => isDark ? Colors.white : const Color(0xFF0F0C20);
  Color get textSecondary => isDark ? Colors.grey.shade400 : Colors.grey.shade600;
  Color get textMuted => isDark ? Colors.grey.shade600 : Colors.grey.shade400;
  
  Color get cardShadow => isDark ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.04);
}
