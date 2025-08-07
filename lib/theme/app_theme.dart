import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // --- Text Theme ---
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

  static const ColorScheme _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF8E5B26),
    onPrimary: Colors.white,
    secondary: Color(0xFFA3C567),
    onSecondary: Colors.black,
    tertiary: Color(0xFFB24F47),
    onTertiary: Colors.white,
    error: Color(0xFFD14343),
    onError: Colors.white,
    background: Color(0xFFFFF8F0),
    onBackground: Color(0xFF2F2F2F),
    surface: Color(0xFFFAF4E7),
    onSurface: Color(0xFF2F2F2F),
    surfaceVariant: Color(0xFFDCD6C4),
    onSurfaceVariant: Color(0xFF4F4F4F),
    outline: Color(0xFFB7B4A5),
    shadow: Colors.black12,
    inverseSurface: Color(0xFF2F2F2F),
    onInverseSurface: Colors.white,
    inversePrimary: Color(0xFFBF8244),
    surfaceTint: Color(0xFF8E5B26),
  );

  static const ColorScheme _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8E5B26),
    onPrimary: Colors.white,
    secondary: Color(0xFFA3C567),
    onSecondary: Colors.black,
    tertiary: Color(0xFFB24F47),
    onTertiary: Colors.white,
    error: Color(0xFFD14343),
    onError: Colors.white,
    background: Color(0xFF1C1C1A),
    onBackground: Color(0xFFEDEAE5),
    surface: Color(0xFF2A2A28),
    onSurface: Color(0xFFEDEAE5),
    surfaceVariant: Color(0xFF6C6C63),
    onSurfaceVariant: Color(0xFFCFCFCF),
    outline: Color(0xFF8D8D84),
    shadow: Colors.black54,
    inverseSurface: Color(0xFFFDF9F0),
    onInverseSurface: Color(0xFF1A1A1A),
    inversePrimary: Color(0xFFFFD9B0),
    surfaceTint: Color(0xFF8E5B26),
  );

  // --- LIGHT THEME ---
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: _lightColorScheme,
        textTheme: _baseTextTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: _lightColorScheme.surface,
          foregroundColor: _lightColorScheme.onSurface,
          elevation: 1,
          scrolledUnderElevation: 4,
          shadowColor: _lightColorScheme.shadow,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _lightColorScheme.tertiary,
          foregroundColor: _lightColorScheme.onTertiary,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _lightColorScheme.primary,
            foregroundColor: _lightColorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        tabBarTheme: TabBarThemeData(
          indicatorColor: _lightColorScheme.primary,
          labelColor: _lightColorScheme.primary,
          unselectedLabelColor: _lightColorScheme.onSurfaceVariant,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          color: _lightColorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        listTileTheme: ListTileThemeData(
          selectedColor: _lightColorScheme.primary,
          selectedTileColor: _lightColorScheme.primary.withOpacity(0.1),
          iconColor: _lightColorScheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _lightColorScheme.surfaceVariant.withOpacity(0.5),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(8),
          ),
          labelStyle: _baseTextTheme.bodyMedium?.copyWith(color: _lightColorScheme.onSurfaceVariant),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: _lightColorScheme.surface,
          selectedItemColor: _lightColorScheme.primary,
          unselectedItemColor: _lightColorScheme.onSurfaceVariant,
        ),
      );

  // --- DARK THEME ---
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        colorScheme: _darkColorScheme,
        textTheme: _baseTextTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: _darkColorScheme.surface,
          foregroundColor: _darkColorScheme.onSurface,
          elevation: 1,
          scrolledUnderElevation: 4,
          shadowColor: _darkColorScheme.shadow,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: _darkColorScheme.tertiary,
          foregroundColor: _darkColorScheme.onTertiary,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _darkColorScheme.primary,
            foregroundColor: _darkColorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        tabBarTheme: TabBarThemeData(
          indicatorColor: _darkColorScheme.primary,
          labelColor: _darkColorScheme.primary,
          unselectedLabelColor: _darkColorScheme.onSurfaceVariant,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          color: _darkColorScheme.surfaceVariant.withOpacity(0.3),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        listTileTheme: ListTileThemeData(
          selectedColor: _darkColorScheme.primary,
          selectedTileColor: _darkColorScheme.primary.withOpacity(0.2),
          iconColor: _darkColorScheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _darkColorScheme.surfaceVariant.withOpacity(0.3),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(8),
          ),
          labelStyle: _baseTextTheme.bodyMedium?.copyWith(color: _darkColorScheme.onSurfaceVariant),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: _darkColorScheme.surface,
          selectedItemColor: _darkColorScheme.primary,
          unselectedItemColor: _darkColorScheme.onSurfaceVariant,
        ),
      );
}
