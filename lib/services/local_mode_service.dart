// lib/services/local_mode_service.dart
import 'package:hive_flutter/hive_flutter.dart';
import '../utils/boxes.dart';

class LocalModeService {
  LocalModeService._();
  static final instance = LocalModeService._();

  static const _key = 'local_mode_enabled';

  Future<Box> _ensureSettingsBox() async {
    if (Hive.isBoxOpen(Boxes.settings)) return Hive.box(Boxes.settings);
    return Hive.openBox(Boxes.settings);
  }

  // Safe sync getter (used in AuthGate, Settings, etc.)
  bool get isLocalOnly {
    if (!Hive.isBoxOpen(Boxes.settings)) return false;
    final box = Hive.box(Boxes.settings);
    return box.get(_key, defaultValue: false) == true;
  }

  Future<void> enableLocalOnly() async {
    final box = await _ensureSettingsBox();
    await box.put(_key, true);
  }

  Future<void> clearLocalOnly() async {
    final box = await _ensureSettingsBox();
    await box.put(_key, false);
  }
}
