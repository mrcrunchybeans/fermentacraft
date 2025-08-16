// lib/utils/temp_display.dart

// ignore_for_file: unnecessary_this

/// A collection of robust, stateless utility functions for handling temperature
/// conversion and formatting. Using an extension on `double` provides a clean,
/// fluent API (e.g., `myTempInCelsius.toDisplay(unit: 'f')`).
library;


extension TemperatureUtils on double {
  /// Assumes the current double value is a temperature in Celsius and converts it to Fahrenheit.
  double get asFahrenheit => (this * 9 / 5) + 32;

  /// Assumes the current double value is a temperature in Fahrenheit and converts it to Celsius.
  double get asCelsius => (this - 32) * 5 / 9;

  /// The primary function to use in your UI.
  ///
  /// Assumes the current double value is in Celsius and formats it into a
  /// display-ready string (e.g., "72.5°F") based on the provided target unit.
  /// It is case-insensitive and safely handles unknown units.
  String toDisplay({required String targetUnit}) {
    // Normalize the unit to lowercase for robust comparison
    final unit = targetUnit.toLowerCase();

    if (unit == 'f' || unit == '°f') {
      return '${this.asFahrenheit.toStringAsFixed(1)}°F';
    }

    // Default to Celsius if the unit is 'c' or anything else.
    // This provides a safe fallback.
    return '${this.toStringAsFixed(1)}°C';
  }
}

// You can delete the old class and functions. This extension replaces them all.
