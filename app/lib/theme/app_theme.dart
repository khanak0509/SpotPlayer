import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const background = Color(0xFF0A0A0C);
  static const surface = Color(0xFF141418);
  static const surfaceElevated = Color(0xFF1C1C22);
  static const surfaceHighlight = Color(0xFF252530);
  static const accent = Color(0xFF8B7CF6);
  static const accentMuted = Color(0xFF6B5BC7);
  static const textPrimary = Color(0xFFF2F2F5);
  static const textSecondary = Color(0xFF9898A6);
  static const textMuted = Color(0xFF5C5C6A);
  static const success = Color(0xFF4ADE80);
  static const error = Color(0xFFF87171);
  static const divider = Color(0xFF2A2A32);
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accentMuted,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
    dividerColor: AppColors.divider,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );

  return base.copyWith(
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceElevated,
      contentTextStyle: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
