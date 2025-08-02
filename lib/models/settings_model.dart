import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class SettingsModel extends ChangeNotifier {
  late bool _useCelsius;
  late ThemeMode _themeMode;

  // --- Getters ---
  bool get useCelsius => _useCelsius;
  ThemeMode get themeMode => _themeMode;
  String get unit => _useCelsius ? '°C' : '°F';

  // --- Constructor ---
  SettingsModel() {
    _useCelsius = Hive.box('settings').get('useCelsius', defaultValue: true);
    final themeName = Hive.box('settings').get('themeMode', defaultValue: 'system');
    _themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == themeName,
      orElse: () => ThemeMode.system,
    );
  }

  // --- New & Improved Methods ---

  /// Sets the temperature unit and saves it to storage.
  Future<void> setUnit({required bool isCelsius}) async {
    if (_useCelsius == isCelsius) return;

    _useCelsius = isCelsius;
    await Hive.box('settings').put('useCelsius', _useCelsius);
    notifyListeners();
  }

  /// Changes the app's theme and saves it to storage.
  Future<void> changeTheme(ThemeMode newTheme) async {
    if (_themeMode == newTheme) return;
    _themeMode = newTheme;
    await Hive.box('settings').put('themeMode', newTheme.name);
    notifyListeners();
  }

  // --- Deprecated Methods (Kept for Safety) ---

  // UPDATED: Added a helpful message.
  @Deprecated('Use setUnit() instead. This will be removed in a future version.')
  void toggleUnit() {
    _useCelsius = !_useCelsius;
    Hive.box('settings').put('useCelsius', _useCelsius);
    notifyListeners();
  }

  // UPDATED: Added a helpful message.
  @Deprecated('No longer used. The constructor handles initialization.')
  void setUnitFromStorage(bool useCelsius) {
    _useCelsius = useCelsius;
  }
}