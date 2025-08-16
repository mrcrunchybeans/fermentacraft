import 'package:hive_flutter/hive_flutter.dart';

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

class SyncMetaStore {
  static late Box _box;

  static Future<void> init() async {
    if (!Hive.isBoxOpen('sync_meta')) {
      _box = await Hive.openBox('sync_meta');
    } else {
      _box = Hive.box('sync_meta');
    }
  }

  static String makeKey(String boxName, String id) => '$boxName:$id';

  static int? getLastSyncedMillis(String boxName, String id) {
    final k = makeKey(boxName, id);
    return _box.get(k) as int?;
  }

  static Future<void> setLastSyncedNow(
      String boxName, String id, int millis) async {
    final k = makeKey(boxName, id);
    await _box.put(k, millis);
  }
}