import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const background = Color(0xFF0A0A0C);
  static const surface = Color(0xFF141418);
  static const surfaceElevated = Color(0xFF1C1C22);
  static const surfaceHighlight = Color(0xFF252530);
  static const accent = Color(0xFF2DD4BF);
  static const accentMuted = Color(0xFF14B8A6);
  static const textPrimary = Color(0xFFF2F2F5);
  static const textSecondary = Color(0xFF9898A6);
  static const textMuted = Color(0xFF5C5C6A);
  static const success = Color(0xFF4ADE80);
  static const error = Color(0xFFF87171);
  static const divider = Color(0xFF2A2A32);
}

FontWeight thickerWeight(FontWeight? weight) {
  return switch (weight ?? FontWeight.w400) {
    FontWeight.w100 => FontWeight.w200,
    FontWeight.w200 => FontWeight.w300,
    FontWeight.w300 => FontWeight.w400,
    FontWeight.w400 => FontWeight.w500,
    FontWeight.w500 => FontWeight.w600,
    FontWeight.w600 => FontWeight.w700,
    FontWeight.w700 => FontWeight.w800,
    _ => weight ?? FontWeight.w500,
  };
}

TextStyle? _thickenStyle(TextStyle? style) {
  if (style == null) return null;
  return style.copyWith(fontWeight: thickerWeight(style.fontWeight));
}

TextTheme thickenTextTheme(TextTheme theme) {
  return theme.copyWith(
    displayLarge: _thickenStyle(theme.displayLarge),
    displayMedium: _thickenStyle(theme.displayMedium),
    displaySmall: _thickenStyle(theme.displaySmall),
    headlineLarge: _thickenStyle(theme.headlineLarge),
    headlineMedium: _thickenStyle(theme.headlineMedium),
    headlineSmall: _thickenStyle(theme.headlineSmall),
    titleLarge: _thickenStyle(theme.titleLarge),
    titleMedium: _thickenStyle(theme.titleMedium),
    titleSmall: _thickenStyle(theme.titleSmall),
    bodyLarge: _thickenStyle(theme.bodyLarge),
    bodyMedium: _thickenStyle(theme.bodyMedium),
    bodySmall: _thickenStyle(theme.bodySmall),
    labelLarge: _thickenStyle(theme.labelLarge),
    labelMedium: _thickenStyle(theme.labelMedium),
    labelSmall: _thickenStyle(theme.labelSmall),
  );
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
    textTheme: thickenTextTheme(
      GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      subtitleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
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
      contentTextStyle: GoogleFonts.plusJakartaSans(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
