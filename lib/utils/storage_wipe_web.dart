// lib/utils/storage_wipe_web.dart
import 'package:web/web.dart' as web;
import '../utils/cache_keys.dart';

/// Removes ONLY keys starting with [prefix] from localStorage & sessionStorage.
void wipeNamespacedStorage({String prefix = CacheKeys.prefix}) {
  try {
    // localStorage
    final ls = web.window.localStorage;
    final lsLen = ls.length;
    final toRemove = <String>[];
    for (var i = 0; i < lsLen; i++) {
      final key = ls.key(i);
      if (key != null && key.startsWith(prefix)) {
        toRemove.add(key);
      }
    }
    for (final k in toRemove) {
      ls.removeItem(k);
    }

    // sessionStorage
    final ss = web.window.sessionStorage;
    final ssLen = ss.length;
    final sRemove = <String>[];
    for (var i = 0; i < ssLen; i++) {
      final key = ss.key(i);
      if (key != null && key.startsWith(prefix)) {
        sRemove.add(key);
      }
    }
    for (final k in sRemove) {
      ss.removeItem(k);
    }
  } catch (e) {
    // Non-fatal: if storage is unavailable (e.g., privacy mode), ignore.
  }
}
