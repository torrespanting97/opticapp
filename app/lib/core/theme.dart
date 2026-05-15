import 'package:flutter/material.dart';

/// Color palette mirrors the existing Salud Visual web template
/// so the migration from HTML -> Flutter is visually seamless.
class AppColors {
  static const greenPrimary = Color(0xFF1A7A4A); // --g1
  static const greenAccent  = Color(0xFF2D9E62); // --g2
  static const greenSoft    = Color(0xFFE8F5EE); // --g3
  static const greenMist    = Color(0xFFF0FBF5); // --g4
  static const navy         = Color(0xFF1E3A5F);
  static const navyDark     = Color(0xFF15293F);
  static const danger       = Color(0xFFDC2626);
  static const amber        = Color(0xFFD97706);
  static const ink          = Color(0xFF111827);
  static const mid          = Color(0xFF374151);
  static const muted        = Color(0xFF6B7280);
  static const border       = Color(0xFFD1D5DB);
  static const bg           = Color(0xFFF9FAFB);
}

final appTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'DMSans',
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.greenPrimary,
    primary: AppColors.greenPrimary,
    secondary: AppColors.greenAccent,
  ),
  scaffoldBackgroundColor: AppColors.bg,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.greenPrimary,
    foregroundColor: Colors.white,
    elevation: 2,
    centerTitle: false,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: AppColors.border, width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: AppColors.border, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: AppColors.greenAccent, width: 1.5),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.greenPrimary,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    ),
  ),
);
