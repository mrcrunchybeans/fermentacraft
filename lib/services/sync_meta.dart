class SyncMeta {
  final String key; // "$boxName:$id"
  final int lastSyncedMillis;

  SyncMeta({required this.key, required this.lastSyncedMillis});

  Map<String, dynamic> toJson() => {
        'key': key,
        'lastSyncedMillis': lastSyncedMillis,
      };

  static SyncMeta fromJson(Map<String, dynamic> json) => SyncMeta(
        key: json['key'] as String,
        lastSyncedMillis: json['lastSyncedMillis'] as int,
      );
}

// lib/services/sync_meta.dart
// Skip sync metadata tracking to save memory
class SyncMetaStore {
  // Skip sync metadata tracking to save memory - box tracking disabled
  // static late Box _box;

  static Future<void> init() async {
    // Skip sync metadata tracking to save memory
    return;
    /*
    if (!Hive.isBoxOpen('sync_meta')) {
      _box = await Hive.openBox('sync_meta');
    } else {
      _box = Hive.box('sync_meta');
    }
    */
  }

  static String makeKey(String boxName, String id) => '$boxName:$id';

  static int? getLastSyncedMillis(String boxName, String id) {
    // Skip sync metadata tracking to save memory
    return null;
    /*
    final k = makeKey(boxName, id);
    if (!Hive.isBoxOpen('sync_meta')) return null;
    return _box.get(k) as int?;
    */
  }

  static Future<void> setLastSyncedNow(
      String boxName, String id, int millis) async {
    // Skip sync metadata tracking to save memory
    return;
    /*
    final k = makeKey(boxName, id);
    await _box.put(k, millis);
    */
  }
}
