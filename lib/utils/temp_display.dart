// lib/utils/temp_display.dart

// ignore_for_file: unnecessary_this

/// A collection of robust, stateless utility functions for handling temperature
/// conversion and formatting. Using an extension on `double` provides a clean,
/// fluent API (e.g., `myTempInCelsius.toDisplay(unit: 'f')`).
library;

/// Standalone temperature conversion utilities
class TempConversion {
  TempConversion._();

  /// Standard calibration temperature for hydrometers (Celsius)
  static const double calibrationTempC = 20.0;
  
  /// Standard calibration temperature for hydrometers (Fahrenheit)
  static const double calibrationTempF = 68.0;

  /// Converts temperature to Celsius.
  /// 
  /// If the [unit] contains 'F' (case-insensitive), converts from Fahrenheit.
  /// Otherwise, assumes the temperature is already in Celsius.
  static double toC(double temp, String? unit) {
    if (unit != null && unit.toUpperCase().contains('F')) {
      return (temp - 32) * 5 / 9;
    }
    return temp;
  }

  /// Converts temperature from Celsius to Fahrenheit.
  static double toF(double tempC) {
    return tempC * 9 / 5 + 32;
  }

  /// Parses temperature from a value and optional unit string.
  /// Returns temperature in Celsius.
  static double parse(num value, String? unit) {
    return toC(value.toDouble(), unit);
  }

  /// Validates if a temperature is within realistic brewing ranges.
  /// Returns true if temperature is between -5°C and 100°C (23°F to 212°F).
  static bool isValidBrewingTemp(double tempC) {
    return tempC >= -5 && tempC <= 100;
  }

  /// Validates if a temperature is within realistic fermentation ranges.
  /// Returns true if temperature is between 0°C and 40°C (32°F to 104°F).
  static bool isValidFermentationTemp(double tempC) {
    return tempC >= 0 && tempC <= 40;
  }
}

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
