import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum ThemeModeOption { light, dark, system }
enum MoneyWallpaperOption { rupeeRain, goldenWealth, disabled }

class ThemeProvider extends ChangeNotifier {
  ThemeModeOption _themeModeOption = ThemeModeOption.light; // Light mode by default!
  MoneyWallpaperOption _wallpaperOption = MoneyWallpaperOption.rupeeRain; // Live Money Wallpaper enabled by default!

  ThemeModeOption get themeModeOption => _themeModeOption;
  MoneyWallpaperOption get wallpaperOption => _wallpaperOption;

  void setThemeMode(ThemeModeOption mode) {
    _themeModeOption = mode;
    notifyListeners();
  }

  void setWallpaperOption(MoneyWallpaperOption option) {
    _wallpaperOption = option;
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
  
  Color get primary => isDark ? AppColors.darkPrimary : AppColors.lightPrimary;
  Color get primaryHover => isDark ? AppColors.darkPrimary : AppColors.lightPrimaryHover;
  Color get secondary => isDark ? AppColors.darkSecondary : AppColors.lightSecondary;
  Color get accent => isDark ? AppColors.darkAccent : AppColors.lightPrimary;
  Color get activeBackground => isDark ? AppColors.darkPrimary.withValues(alpha: 0.15) : AppColors.lightActiveBackground;
  
  // Dedicated Left Panel (Sidebar & Drawer) Tokens
  Color get sidebarBackground => isDark ? AppColors.darkSidebar : AppColors.lightSidebar;
  Color get sidebarSurface => isDark ? AppColors.darkSidebarSurface : AppColors.lightSidebarSurface;
  Color get sidebarActive => isDark ? AppColors.darkSidebarActive : AppColors.lightSidebarActive;
  Color get sidebarTextPrimary => isDark ? AppColors.darkSidebarTextPrimary : AppColors.lightSidebarTextPrimary;
  Color get sidebarTextSecondary => isDark ? AppColors.darkSidebarTextSecondary : AppColors.lightSidebarTextSecondary;
  Color get sidebarBorder => isDark ? AppColors.darkSidebarBorder : AppColors.lightSidebarBorder;

  Color get background => isDark ? AppColors.darkBackground : AppColors.lightBackground;
  Color get surface => isDark ? AppColors.darkSurface : AppColors.lightSurface;
  Color get sidebar => sidebarBackground; // Alias for backward compatibility
  Color get surfaceAccent => isDark ? AppColors.darkSurfaceAccent : AppColors.lightSurfaceAccent;
  Color get tableRowAlt => isDark ? AppColors.darkTableRowAlt : AppColors.lightTableRowAlt;
  
  Color get border => isDark ? AppColors.darkDivider : AppColors.lightDivider;
  Color get textPrimary => isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  Color get textSecondary => isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  Color get placeholder => isDark ? AppColors.darkPlaceholder : AppColors.lightPlaceholder;
  Color get textMuted => isDark ? AppColors.darkDisabled : AppColors.lightDisabled;
  Color get disabled => isDark ? AppColors.darkDisabled : AppColors.lightDisabled;
  
  Color get success => isDark ? AppColors.darkSuccess : AppColors.lightSuccess;
  Color get profit => isDark ? AppColors.darkProfit : AppColors.lightProfit;
  Color get warning => isDark ? AppColors.darkWarning : AppColors.lightWarning;
  Color get error => isDark ? AppColors.darkError : AppColors.lightError;
  Color get info => isDark ? AppColors.darkInfo : AppColors.lightInfo;
  
  Color get cardShadow => isDark ? Colors.black.withValues(alpha: 0.4) : const Color(0xFF0F172A).withValues(alpha: 0.04);
}
