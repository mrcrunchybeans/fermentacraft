// lib/services/presets_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple persistence for user-defined yeast and additive presets.
/// Uses SharedPreferences under the hood.
class PresetsService extends ChangeNotifier {
  static const _kYeastKey = 'user_presets_yeasts_v1';
  static const _kAddKey  = 'user_presets_additives_v1';

  bool _loaded = false;
  final List<String> _userYeasts = <String>[];
  final List<String> _userAdditives = <String>[];

  /// Built-in (“common”) suggestions. Shown *in addition* to user presets.
  static const List<String> builtInYeasts = <String>[
    'Lalvin EC-1118',
    'Lalvin D47',
    'Lalvin 71B',
    'K1-V1116',
    'QA23',
    'Red Star Premier Blanc',
    'Red Star Premier Rouge',
  ];

  static const List<String> builtInAdditives = <String>[
    'Yeast nutrient',
    'Yeast energizer',
    'Pectic enzyme',
    'Bentonite',
    'Oak chips',
    'Acid blend',
    'Potassium metabisulfite (K-meta)',
    'Potassium sorbate',
    'Tannin',
    'Gelatin',
  ];

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _userYeasts
      ..clear()
      ..addAll(_decodeList(prefs.getString(_kYeastKey)));
    _userAdditives
      ..clear()
      ..addAll(_decodeList(prefs.getString(_kAddKey)));
    _loaded = true;
    notifyListeners();
  }

  List<String> get userYeastPresets => List.unmodifiable(_userYeasts);
  List<String> get userAdditivePresets => List.unmodifiable(_userAdditives);

  List<String> get allYeastPresets {
    final s = <String>{...builtInYeasts, ..._userYeasts};
    return s.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<String> get allAdditivePresets {
    final s = <String>{...builtInAdditives, ..._userAdditives};
    return s.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<void> maybeAddYeastPreset(String name) async {
    final clean = _clean(name);
    if (clean.isEmpty) return;
    if (_containsCaseInsensitive(_userYeasts, clean)) return;
    if (_containsCaseInsensitive(builtInYeasts, clean)) return;
    _userYeasts.add(clean);
    await _save();
    notifyListeners();
  }

  Future<void> maybeAddAdditivePreset(String name) async {
    final clean = _clean(name);
    if (clean.isEmpty) return;
    if (_containsCaseInsensitive(_userAdditives, clean)) return;
    if (_containsCaseInsensitive(builtInAdditives, clean)) return;
    _userAdditives.add(clean);
    await _save();
    notifyListeners();
  }

  Future<void> removeYeastPreset(String name) async {
    _removeCaseInsensitive(_userYeasts, name);
    await _save();
    notifyListeners();
  }

  Future<void> removeAdditivePreset(String name) async {
    _removeCaseInsensitive(_userAdditives, name);
    await _save();
    notifyListeners();
  }

  // ------- helpers -------
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kYeastKey, jsonEncode(_userYeasts));
    await prefs.setString(_kAddKey, jsonEncode(_userAdditives));
  }

  List<String> _decodeList(String? s) {
    if (s == null || s.isEmpty) return <String>[];
    try {
      final d = jsonDecode(s);
      if (d is List) {
        return d.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      }
    } catch (_) {}
    return <String>[];
  }

  String _clean(String s) => s.trim();

  bool _containsCaseInsensitive(Iterable<String> list, String value) {
    final v = value.toLowerCase();
    return list.any((e) => e.toLowerCase() == v);
  }

  void _removeCaseInsensitive(List<String> list, String value) {
    final v = value.toLowerCase();
    list.removeWhere((e) => e.toLowerCase() == v);
  }
}
