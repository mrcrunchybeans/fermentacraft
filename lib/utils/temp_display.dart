class TempDisplay {
  static bool _useFahrenheit = false;

  static void setUseFahrenheit(bool useF) {
    _useFahrenheit = useF;
  }

  static String format(double tempC) {
    if (_useFahrenheit) {
      final f = (tempC * 9 / 5) + 32;
      return "${f.toStringAsFixed(1)}°F";
    }
    return "${tempC.toStringAsFixed(1)}°C";
  }

  static double convertToCelsius(double input, String unit) {
    return unit == "°F" ? (input - 32) * 5 / 9 : input;
  }

  static bool get isF => _useFahrenheit;
}
// -- For direct use in widgets that use SettingsModel -- //

double convertTemp(double value, {required String fromUnit, required String toUnit}) {
  if (fromUnit == toUnit) return value;
  return toUnit == 'f' ? (value * 9 / 5) + 32 : (value - 32) * 5 / 9;
}

String displayTemp(double tempC, {required String unit}) {
  final v = convertTemp(tempC, fromUnit: 'c', toUnit: unit);
  return '${v.toStringAsFixed(1)}°${unit.toUpperCase()}';
}
