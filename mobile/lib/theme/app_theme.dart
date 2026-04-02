import 'package:flutter/material.dart';

class AppTheme {
  // Colors
  static const Color primaryGreen = Color(0xFF4CAF50);
  static const Color safeGreen = Color(0xFF2E7D32);
  static const Color alertRed = Color(0xFFD32F2F);
  static const Color warningYellow = Color(0xFFFFA000);
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color white = Colors.white;

  // Elderly-friendly font sizes (per UX requirements)
  static const double fontBody = 20.0;
  static const double fontHeading = 28.0;
  static const double fontButtonLabel = 36.0;
  static const double fontSmall = 16.0;

  // Button sizes
  static const double checkInButtonSize = 220.0; // 200dp min + padding
  static const double minTapTarget = 48.0; // 44pt min per a11y

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        primary: primaryGreen,
        error: alertRed,
        surface: backgroundLight,
      ),
      scaffoldBackgroundColor: backgroundLight,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: fontHeading,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: fontBody,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 18,
          color: textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: fontButtonLabel,
          fontWeight: FontWeight.bold,
          color: white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(minTapTarget, minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: const TextStyle(fontSize: fontBody, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        labelStyle: const TextStyle(fontSize: 18),
        hintStyle: const TextStyle(fontSize: 18),
      ),
    );
  }
}
