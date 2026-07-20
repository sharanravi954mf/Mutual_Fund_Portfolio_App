import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  static TextStyle h1(bool isDark) => GoogleFonts.outfit(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        letterSpacing: -0.5,
      );

  static TextStyle h2(bool isDark) => GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        letterSpacing: -0.3,
      );

  static TextStyle h3(bool isDark) => GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      );

  static TextStyle bodyLarge(bool isDark) => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      );

  static TextStyle bodyMedium(bool isDark) => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      );

  static TextStyle bodySecondary(bool isDark) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
      );

  static TextStyle labelMedium(bool isDark) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
      );

  static TextStyle labelBold(bool isDark) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      );

  static TextStyle caption(bool isDark) => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
      );
}
