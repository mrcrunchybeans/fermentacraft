import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // --- LIGHT THEME COLORS ---
  static const Color _lightPrimaryColor = Color(0xFF415A77);
  static const Color _lightSecondaryColor = Color(0xFFE9911C);
  static const Color _lightSurfaceColor = Color(0xFFFDFCF9); // For background and cards
  static const Color _lightTextPrimaryColor = Color(0xFF34191C);
  static const Color _lightTextSecondaryColor = Color(0xFF965220);

  // --- DARK THEME COLORS ---
  static const Color _darkPrimaryColor = Color(0xFF778DA9);
  static const Color _darkSecondaryColor = Color(0xFFE9911C);
  static const Color _darkSurfaceColor = Color(0xFF1B263B);
  static const Color _darkTextPrimaryColor = Color(0xFFE0E1DD);

  // --- Base Text Themes (to apply colors separately) ---
  static final TextTheme _baseTextTheme = TextTheme(
    displayLarge: GoogleFonts.libreBaskerville(fontSize: 57, fontWeight: FontWeight.bold),
    displayMedium: GoogleFonts.libreBaskerville(fontSize: 45, fontWeight: FontWeight.bold),
    displaySmall: GoogleFonts.libreBaskerville(fontSize: 36, fontWeight: FontWeight.bold),
    headlineLarge: GoogleFonts.libreBaskerville(fontSize: 32, fontWeight: FontWeight.bold),
    headlineMedium: GoogleFonts.libreBaskerville(fontSize: 28, fontWeight: FontWeight.bold),
    headlineSmall: GoogleFonts.libreBaskerville(fontSize: 24, fontWeight: FontWeight.bold),
    titleLarge: GoogleFonts.libreBaskerville(fontSize: 22, fontWeight: FontWeight.bold),
    bodyLarge: GoogleFonts.roboto(fontSize: 16),
    bodyMedium: GoogleFonts.roboto(fontSize: 14),
    bodySmall: GoogleFonts.roboto(fontSize: 12),
    labelLarge: GoogleFonts.roboto(fontSize: 14, fontWeight: FontWeight.bold),
  );

  // ### LIGHT THEME ###
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light().copyWith(
        primary: _lightPrimaryColor,
        onPrimary: Colors.white,
        secondary: _lightSecondaryColor,
        onSecondary: Colors.white,
        surface: _lightSurfaceColor,
        onSurface: _lightTextPrimaryColor,
      ),
      textTheme: _baseTextTheme.apply(
        bodyColor: _lightTextPrimaryColor,
        displayColor: _lightTextPrimaryColor,
      ).copyWith(
        bodySmall: _baseTextTheme.bodySmall?.copyWith(color: _lightTextSecondaryColor),
        labelLarge: _baseTextTheme.labelLarge?.copyWith(color: Colors.white),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _lightPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _lightSecondaryColor,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightPrimaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: Colors.white,
        labelColor: Colors.white,
        unselectedLabelColor: Color(0xB3FFFFFF), // White with 70% opacity
      ),
      cardTheme: const CardThemeData(
        elevation: 1,
        color: _lightSurfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      listTileTheme: ListTileThemeData(
        selectedColor: _lightSecondaryColor,
        selectedTileColor: _lightSecondaryColor.withAlpha(25), // ~10% opacity
        iconColor: _lightTextSecondaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ### DARK THEME ###
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark().copyWith(
        primary: _darkPrimaryColor,
        onPrimary: _darkTextPrimaryColor,
        secondary: _darkSecondaryColor,
        onSecondary: Colors.black,
        surface: _darkSurfaceColor,
        onSurface: _darkTextPrimaryColor,
      ),
      textTheme: _baseTextTheme.apply(
        bodyColor: _darkTextPrimaryColor,
        displayColor: _darkTextPrimaryColor,
      ).copyWith(
        labelLarge: _baseTextTheme.labelLarge?.copyWith(color: Colors.black),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkSurfaceColor,
        elevation: 2,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _darkSecondaryColor,
        foregroundColor: Colors.black,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _darkPrimaryColor,
          foregroundColor: _darkTextPrimaryColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: _darkSecondaryColor,
        labelColor: _darkSecondaryColor,
        unselectedLabelColor: Color(0xB3E0E1DD), // Off-white with 70% opacity
      ),
      cardTheme: const CardThemeData(
        elevation: 1,
        color: _darkSurfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      listTileTheme: ListTileThemeData(
        selectedColor: _darkSecondaryColor,
        selectedTileColor: _darkSecondaryColor.withAlpha(40), // ~15% opacity
        iconColor: _darkTextPrimaryColor.withOpacity(0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}