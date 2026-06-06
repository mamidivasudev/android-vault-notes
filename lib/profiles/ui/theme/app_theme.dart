import 'package:flutter/material.dart';

class AppTheme {
  static const primaryColor = Color(0xFF1D63D2); // Blue
  static const accentColor = Color(0xFF1D63D2);
  static const backgroundColor = Color(0xFFF8FAFC); 
  static const cardColor = Colors.white;

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      primary: primaryColor,
      surface: backgroundColor,
    ),
    scaffoldBackgroundColor: backgroundColor,
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      primary: const Color(0xFF3B82F6), // Vibrant blue for dark mode
      surface: const Color(0xFF000000), // Pure OLED black
      onSurface: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xFF000000),
    cardTheme: CardThemeData(
      color: const Color(0xFF0F172A), // Elegant deep slate card background
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF1E293B)), // Subtle dark border
      ),
    ),
  );
}
