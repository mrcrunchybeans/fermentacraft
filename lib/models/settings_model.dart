import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class SettingsModel extends ChangeNotifier {
  bool _useCelsius = true;
  ThemeMode _themeMode = ThemeMode.system; // <-- ADDED

  bool get useCelsius => _useCelsius;
  ThemeMode get themeMode => _themeMode; // <-- ADDED
  String get unit => _useCelsius ? '°C' : '°F';

  SettingsModel() {
    // Load initial settings from storage
    _useCelsius = Hive.box('settings').get('useCelsius', defaultValue: true);
    final themeString = Hive.box('settings').get('themeMode', defaultValue: 'system');
    _themeMode = _themeModeFromString(themeString);
  }

  void toggleUnit() {
    _useCelsius = !_useCelsius;
    notifyListeners();
  }

  void setUnitFromStorage(bool useCelsius) {
    _useCelsius = useCelsius;
    notifyListeners();
  }

  // --- ADDED: Methods for theme management ---
  void changeTheme(ThemeMode newTheme) {
    if (_themeMode == newTheme) return;
    _themeMode = newTheme;
    Hive.box('settings').put('themeMode', _themeModeToString(newTheme));
    notifyListeners();
  }

  String _themeModeToString(ThemeMode theme) {
    return theme.toString().split('.').last;
  }

  ThemeMode _themeModeFromString(String themeString) {
    return ThemeMode.values.firstWhere(
      (e) => e.toString().split('.').last == themeString,
      orElse: () => ThemeMode.system,
    );
  }
}