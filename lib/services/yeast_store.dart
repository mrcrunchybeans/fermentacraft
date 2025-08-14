// lib/services/yeast_store.dart
import 'package:hive_flutter/hive_flutter.dart';

class YeastStore {
  static const _boxName = 'app_prefs';   // any non-typed box name is fine
  static const _key = 'myYeasts';

  static Future<Box> _open() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return await Hive.openBox(_boxName);
  }

  static List<String> list() {
    // If the box isn't open yet, just return an empty list (no throw)
    if (!Hive.isBoxOpen(_boxName)) return const <String>[];
    final raw = Hive.box(_boxName).get(_key, defaultValue: <String>[]);
    return (raw as List).cast<String>();
  }

  static Future<void> add(String name) async {
    final box = await _open();
    final list = (box.get(_key, defaultValue: <String>[]) as List).cast<String>();
    final exists = list.any((e) => e.toLowerCase() == name.toLowerCase());
    if (!exists) {
      list.add(name);
      await box.put(_key, list);
    }
  }

  static Future<void> remove(String name) async {
    final box = await _open();
    final list = (box.get(_key, defaultValue: <String>[]) as List).cast<String>();
    list.removeWhere((e) => e.toLowerCase() == name.toLowerCase());
    await box.put(_key, list);
  }

  static Future<void> rename(String oldName, String newName) async {
    final box = await _open();
    final list = (box.get(_key, defaultValue: <String>[]) as List).cast<String>();

    final idx = list.indexWhere((e) => e.toLowerCase() == oldName.toLowerCase());
    if (idx == -1) return;

    final dupe = list.any((e) => e.toLowerCase() == newName.toLowerCase());
    if (dupe) return;

    list[idx] = newName;
    await box.put(_key, list);
  }
}
