import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fermentacraft/models/enums.dart';

class SettingsModel extends ChangeNotifier {
  // --- Storage & keys ---
  final Box _box;
  static const String _kUseCelsius      = 'useCelsius';
  static const String _kThemeMode       = 'themeMode';
  static const String _kCurrencySymbol  = 'currencySymbol';
  static const String _kVolumeUnit      = 'volumeUnit';

  // --- State ---
  late bool _useCelsius;
  late ThemeMode _themeMode;
  late String _currencySymbol;
  late VolumeUiUnit _volumeUnit;

  // --- Getters ---
  bool get useCelsius => _useCelsius;
  ThemeMode get themeMode => _themeMode;
  String get unit => _useCelsius ? '°C' : '°F';
  String get currencySymbol => _currencySymbol;
  VolumeUiUnit get volumeUnit => _volumeUnit;

  // --- Constructor (inject the already-opened settings box) ---
  SettingsModel(Box settingsBox) : _box = settingsBox {
    _useCelsius = _box.get(_kUseCelsius, defaultValue: true) == true;
    _currencySymbol = _box.get(_kCurrencySymbol, defaultValue: r'$') as String;

    final themeName = _box.get(_kThemeMode, defaultValue: 'system') as String;
    _themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == themeName,
      orElse: () => ThemeMode.system,
    );

    // Load volume unit preference, default to liters
    final volumeUnitIndex = _box.get(_kVolumeUnit, defaultValue: VolumeUiUnit.liters.index) as int;
    _volumeUnit = VolumeUiUnit.values[volumeUnitIndex.clamp(0, VolumeUiUnit.values.length - 1)];
  }

  // --- Mutators ---
  Future<void> setUnit({required bool isCelsius}) async {
    if (_useCelsius == isCelsius) return;
    _useCelsius = isCelsius;
    await _box.put(_kUseCelsius, _useCelsius);
    notifyListeners();
  }

  Future<void> changeTheme(ThemeMode newTheme) async {
    if (_themeMode == newTheme) return;
    _themeMode = newTheme;
    await _box.put(_kThemeMode, newTheme.name);
    notifyListeners();
  }

  /// Sets the currency symbol used across the app (e.g. $, €, £, ₹, R$, etc.).
  Future<void> setCurrencySymbol(String symbol) async {
    final cleaned = symbol.trim();
    if (cleaned.isEmpty || cleaned == _currencySymbol) return;
    _currencySymbol = cleaned;
    await _box.put(_kCurrencySymbol, _currencySymbol);
    notifyListeners();
  }

  /// Sets the preferred volume unit for recipe and tool displays.
  Future<void> setVolumeUnit(VolumeUiUnit unit) async {
    if (_volumeUnit == unit) return;
    _volumeUnit = unit;
    await _box.put(_kVolumeUnit, unit.index);
    notifyListeners();
  }

  // --- Deprecated (kept for safety/back-compat) ---
  @Deprecated('Use setUnit() instead. This will be removed in a future version.')
  void toggleUnit() {
    _useCelsius = !_useCelsius;
    _box.put(_kUseCelsius, _useCelsius);
    notifyListeners();
  }

  @Deprecated('No longer used. The constructor handles initialization.')
  void setUnitFromStorage(bool useCelsius) {
    _useCelsius = useCelsius;
  }
}
