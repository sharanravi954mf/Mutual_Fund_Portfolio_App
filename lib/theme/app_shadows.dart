import 'package:flutter/material.dart';

class AppShadows {
  // Soft elevation shadows for light mode and dark mode
  static List<BoxShadow> card(bool isDark) {
    if (isDark) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
    }
    return [
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.04),
        blurRadius: 12,
        spreadRadius: 0,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.02),
        blurRadius: 4,
        spreadRadius: 0,
        offset: const Offset(0, 1),
      ),
    ];
  }

  static List<BoxShadow> dropdown(bool isDark) {
    if (isDark) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];
    }
    return [
      BoxShadow(
        color: const Color(0xFF0F172A).withValues(alpha: 0.08),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ];
  }

  static List<BoxShadow> buttonHover(Color color) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.25),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ];
  }
}
