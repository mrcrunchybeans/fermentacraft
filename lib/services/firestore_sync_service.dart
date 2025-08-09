// lib/services/firestore_sync_service.dart
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../utils/data_management.dart';
import 'firestore_paths.dart';
import 'sync_meta.dart';

typedef JsonMap = Map<String, dynamic>;

class FirestoreSyncService {
  FirestoreSyncService._();
  static final FirestoreSyncService instance = FirestoreSyncService._();

  // Hive boxes that represent user-scoped data
  final _userBoxNames = const [
    'recipes',
    'batches',
    'inventory',
    'shopping_list',
    'tags',
    // NOTE: 'settings' is handled separately
  ];

  StreamSubscription? _authSub;
  final Map<String, StreamSubscription> _hiveSubs = {};
  final Map<String, StreamSubscription> _fireSubs = {};
  final _connectivity = Connectivity();
  StreamSubscription? _connSub;

  String? _uid;

  bool _enabled = true;
  bool get isEnabled => _enabled;
  set isEnabled(bool v) {
    if (_enabled == v) return;
    _enabled = v;
    if (!_enabled) {
      _pauseWatchers();
    } else {
      final uid = _uid;
      if (uid != null) {
        _resumeForUid(uid);
      }
    }
  }

  void enable() => isEnabled = true;
  void disable() => isEnabled = false;
  void setEnabled(bool v) => isEnabled = v;

  bool _started = false;

  // -----------------------------
  // Optimizations state
  // -----------------------------

  // Prevent echo loop: mark keys we just wrote into Hive from remote so the
  // Hive watcher won't re-enqueue them to Firestore.
  final Set<String> _suppressLocalEcho = {}; // key: box::id

  // Debounce & coalesce: per-doc timers and latest payloads (box::id)
  final Map<String, Timer> _debouncers = {};
  final Map<String, JsonMap> _pendingPayloads = {};
  final Duration _debounce = const Duration(seconds: 3);

  // No-change skip: remember last JSON we sent per doc (box::id)
  final Map<String, String> _lastSentJson = {};

  String _keyOf(String boxName, String id) => '$boxName::$id';

  // -----------------------------
  // Lifecycle
  // -----------------------------

  Future<void> init() async {
    await SyncMetaStore.init();

    // Auth: sign-in/out & user switching
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) async {
      final oldUid = _uid;
      final newUid = user?.uid;

      if (newUid == null) {
        // Signed out → stop syncing and clear local user data
        await _stop();
        await _clearLocalUserData();
        return;
      }

      if (oldUid != null && oldUid != newUid) {
        // Switched account → stop, purge, then start fresh
        await _stop();
        await _clearLocalUserData();
      }

      await _start(newUid);
    });

    // Connectivity: best-effort flush when network returns
    _connSub ??= _connectivity.onConnectivityChanged.listen((_) {
      if (_uid != null && _enabled) {
        _bootstrapPushLocal(_uid!);
      }
    });
  }

  Future<void> _start(String uid) async {
    _uid = uid;
    if (_started) return;
    if (!_enabled) return;
    _started = true;

    // First time for this user on this device: pull remote, then push local (converge).
    await _bootstrapMerge(uid);

    // Local -> Remote watchers
    for (final boxName in _userBoxNames) {
      _attachHiveWatcher(uid, boxName);
    }

    // Remote -> Local watchers
    for (final boxName in _userBoxNames) {
      _attachFirestoreWatcher(uid, boxName);
    }

    // Settings sync
    _attachSettingsWatchers(uid);
  }

  Future<void> _stop() async {
    _started = false;

    for (final s in _hiveSubs.values) {
      await s.cancel();
    }
    _hiveSubs.clear();

    for (final s in _fireSubs.values) {
      await s.cancel();
    }
    _fireSubs.clear();

    // Cancel any outstanding debouncers
    for (final t in _debouncers.values) {
      t.cancel();
    }
    _debouncers.clear();
    _pendingPayloads.clear();

    _uid = null;
  }

  Future<void> dispose() async {
    await _stop();
    await _authSub?.cancel();
    await _connSub?.cancel();
    _authSub = null;
    _connSub = null;
  }

  // -----------------------------
  // Pause / Resume (for isEnabled toggle)
  // -----------------------------

  Future<void> _pauseWatchers() async {
    _started = false;

    for (final s in _hiveSubs.values) {
      await s.cancel();
    }
    _hiveSubs.clear();

    for (final s in _fireSubs.values) {
      await s.cancel();
    }
    _fireSubs.clear();

    // Cancel debouncers
    for (final t in _debouncers.values) {
      t.cancel();
    }
    _debouncers.clear();
    _pendingPayloads.clear();
    // Keep _uid; we’re only pausing.
  }

  Future<void> _resumeForUid(String uid) async {
    await _pauseWatchers();
    if (!_enabled) return;

    // Small delay to let in-flight listeners settle.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    _started = true;

    // Converge before reattaching.
    await _bootstrapMerge(uid);

    // Reattach watchers
    for (final boxName in _userBoxNames) {
      _attachHiveWatcher(uid, boxName);
    }
    for (final boxName in _userBoxNames) {
      _attachFirestoreWatcher(uid, boxName);
    }
    _attachSettingsWatchers(uid);
  }

  // -----------------------------
  // Bootstrapping
  // -----------------------------

  Future<void> _bootstrapMerge(String uid) async {
    await _bootstrapPullRemote(uid);
    await _bootstrapPushLocal(uid);
  }

  Future<void> _bootstrapPullRemote(String uid) async {
    for (final boxName in _userBoxNames) {
      try {
        final snap = await FirestorePaths.coll(uid, boxName).get();
        for (final doc in snap.docs) {
          try {
            await _applyRemoteDoc(boxName, doc.data(), preferRemote: true);
          } catch (e, st) {
            if (kDebugMode) print('bootstrapPull apply fail [$boxName]: $e\n$st');
          }
        }
      } catch (e, st) {
        if (kDebugMode) print('bootstrapPull fail [$boxName]: $e\n$st');
      }
    }

    // settings
    try {
      final sDoc = await FirestorePaths.settingsDoc(uid).get();
      if (sDoc.exists) {
        await _applyRemoteSettings(sDoc.data()!);
      }
    } catch (e, st) {
      if (kDebugMode) print('bootstrapPull settings fail: $e\n$st');
    }
  }

  Future<void> _bootstrapPushLocal(String uid) async {
    for (final boxName in _userBoxNames) {
      try {
        final box = DataManagementService.getTypedBox(boxName);
        for (final key in box.keys) {
          try {
            final dynamic value = box.get(key);
            if (value == null) continue;
            final json = (value as dynamic).toJson() as JsonMap;
            final id = key.toString();

            // Skip identical payloads to avoid re-writing unchanged docs.
            final fullKey = _keyOf(boxName, id);
            final s = jsonEncode(json);
            if (_lastSentJson[fullKey] == s) continue;

            await _pushLocalDocWithId(uid, boxName, id, json);
          } catch (e, st) {
            if (kDebugMode) print('bootstrapPush item fail [$boxName,$key]: $e\n$st');
          }
        }
      } catch (e, st) {
        if (kDebugMode) print('bootstrapPush box fail [$boxName]: $e\n$st');
      }
    }

    // settings
    try {
      final settingsMap = _collectSettingsAsMap();
      if (settingsMap.isNotEmpty) {
        final key = '__settings__::singleton';
        final s = jsonEncode(settingsMap);
        if (_lastSentJson[key] != s) {
          _lastSentJson[key] = s;
          await FirestorePaths.settingsDoc(uid).set({
            ...settingsMap,
            '_meta': {'updatedAt': FieldValue.serverTimestamp()}
          }, SetOptions(merge: true));
        }
      }
    } catch (e, st) {
      if (kDebugMode) print('bootstrapPush settings fail: $e\n$st');
    }
  }

  // -----------------------------
  // Watchers
  // -----------------------------

  void _attachHiveWatcher(String uid, String boxName) {
    final box = DataManagementService.getTypedBox(boxName);
    _hiveSubs[boxName]?.cancel();
    _hiveSubs[boxName] = box.watch().listen((event) async {
      if (!_enabled || _uid != uid) return;

      final id = event.key.toString();
      final k = _keyOf(boxName, id);

      // If this change came from _applyRemoteDoc, ignore it (no echo).
      if (_suppressLocalEcho.remove(k)) {
        return;
      }

      try {
        if (event.deleted) {
          await _markRemoteDeleted(uid, boxName, id);
          return;
        }
        final dynamic val = box.get(event.key);
        if (val == null) return;
        final json = (val as dynamic).toJson() as JsonMap;

        // Debounce / coalesce the latest payload per-doc
        _pendingPayloads[k] = json;

        _debouncers[k]?.cancel();
        _debouncers[k] = Timer(_debounce, () async {
          try {
            final latest = _pendingPayloads.remove(k);
            _debouncers.remove(k);
            if (latest == null) return;

            // Skip no-change writes
            final s = jsonEncode(latest);
            if (_lastSentJson[k] == s) return;

            await _pushLocalDocWithId(uid, boxName, id, latest);
          } catch (e, st) {
            if (kDebugMode) print('Hive debounce flush fail [$boxName,$id]: $e\n$st');
          }
        });
      } catch (e, st) {
        if (kDebugMode) print('Hive watcher error [$boxName]: $e\n$st');
      }
    });
  }

  void _attachFirestoreWatcher(String uid, String boxName) {
    _fireSubs[boxName]?.cancel();
    _fireSubs[boxName] = FirestorePaths.coll(uid, boxName)
        .snapshots()
        .listen((querySnap) async {
      if (!_enabled || _uid != uid) return;
      for (final change in querySnap.docChanges) {
        try {
          final data = change.doc.data();
          if (data == null) continue;
          await _applyRemoteDoc(boxName, data, preferRemote: true);
        } catch (e, st) {
          if (kDebugMode) print('applyRemoteDoc fail [$boxName]: $e\n$st');
        }
      }
    }, onError: (e, st) {
      if (kDebugMode) print('Firestore watcher error [$boxName]: $e\n$st');
    });
  }

  void _attachSettingsWatchers(String uid) {
    // Push local -> remote on changes (very light debounce via microtask queue)
    final settings = Hive.box('settings');
    _hiveSubs['__settings_local__']?.cancel();
    Timer? settingsDebounce;
    _hiveSubs['__settings_local__'] = settings.watch().listen((_) async {
      if (!_enabled || _uid != uid) return;
      settingsDebounce?.cancel();
      settingsDebounce = Timer(const Duration(milliseconds: 500), () async {
        try {
          final map = _collectSettingsAsMap();
          if (map.isEmpty) return;
          final key = '__settings__::singleton';
          final s = jsonEncode(map);
          if (_lastSentJson[key] == s) return;
          _lastSentJson[key] = s;

          await FirestorePaths.settingsDoc(uid).set({
            ...map,
            '_meta': {'updatedAt': FieldValue.serverTimestamp()}
          }, SetOptions(merge: true));
        } catch (e, st) {
          if (kDebugMode) print('settings push fail: $e\n$st');
        }
      });
    });

    // Pull remote -> local
    _fireSubs['__settings_remote__']?.cancel();
    _fireSubs['__settings_remote__'] = FirestorePaths.settingsDoc(uid)
        .snapshots()
        .listen((doc) async {
      if (!_enabled || _uid != uid) return;
      try {
        final data = doc.data();
        if (data == null) return;
        await _applyRemoteSettings(data);
      } catch (e, st) {
        if (kDebugMode) print('settings pull fail: $e\n$st');
      }
    });
  }

  // -----------------------------
  // Helpers
  // -----------------------------

  Future<void> _pushLocalDocWithId(
    String uid,
    String boxName,
    String id,
    JsonMap json,
  ) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) {
      if (kDebugMode) print('Skip push: empty key id for $boxName: $json');
      return;
    }

    // Skip identical payloads (prevents repeated writes on bootstrap & steady state)
    final key = _keyOf(boxName, cleanId);
    final s = jsonEncode(json);
    if (_lastSentJson[key] == s) return;
    _lastSentJson[key] = s;

    final now = DateTime.now().millisecondsSinceEpoch;
    await FirestorePaths.doc(uid, boxName, cleanId).set({
      ...json,
      'id': cleanId, // ensure remote carries the id too
      '_meta': {
        'updatedAt': FieldValue.serverTimestamp(),
        'deviceUpdatedAt': now,
        'deleted': false,
      }
    }, SetOptions(merge: true));

    await SyncMetaStore.setLastSyncedNow(boxName, cleanId, now);
  }

  Future<void> _markRemoteDeleted(String uid, String boxName, String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await FirestorePaths.doc(uid, boxName, cleanId).set({
      '_meta': {
        'updatedAt': FieldValue.serverTimestamp(),
        'deviceUpdatedAt': now,
        'deleted': true,
      }
    }, SetOptions(merge: true));
    await SyncMetaStore.setLastSyncedNow(boxName, cleanId, now);

    // Also forget lastSent so a re-create won't be blocked by equality cache
    _lastSentJson.remove(_keyOf(boxName, cleanId));
  }

  Future<void> _applyRemoteDoc(String boxName, JsonMap data, {required bool preferRemote}) async {
    try {
      final meta = (data['_meta'] as Map?) ?? {};
      final deviceUpdatedAt = (meta['deviceUpdatedAt'] as num?)?.toInt() ?? 0;
      final deleted = (meta['deleted'] as bool?) ?? false;

      // Prefer 'id' written from local key; fallback to 'name' if ever needed.
      final id = (data['id'] ?? data['name'] ?? '').toString().trim();
      if (id.isEmpty) return;

      final last = SyncMetaStore.getLastSyncedMillis(boxName, id) ?? 0;
      if (deviceUpdatedAt < last) {
        // Local newer; ignore remote
        return;
      }

      final box = DataManagementService.getTypedBox(boxName);
      if (deleted) {
        await box.delete(id);
        await SyncMetaStore.setLastSyncedNow(boxName, id, deviceUpdatedAt);
        // Since it’s deleted remotely, clear equality cache so a re-add pushes again
        _lastSentJson.remove(_keyOf(boxName, id));
        return;
      }

      final clean = Map<String, dynamic>.from(data)..remove('_meta');

      // Defensive: ensure required fields exist for your models if needed.

      final ctor = DataManagementService.fromJsonFor(boxName);
      final obj = ctor(clean);

      // Mark this key so the Hive watcher doesn't echo this write back to Firestore
      final k = _keyOf(boxName, id);
      _suppressLocalEcho.add(k);

      await box.put(id, obj);
      await SyncMetaStore.setLastSyncedNow(boxName, id, deviceUpdatedAt);

      // Since remote just "won", refresh lastSent cache to avoid immediate re-push on bootstrap
      _lastSentJson[k] = jsonEncode(clean);
    } catch (e, st) {
      if (kDebugMode) print('applyRemoteDoc exception [$boxName]: $e\n$st');
    }
  }

  Future<void> _applyRemoteSettings(JsonMap data) async {
    try {
      final settings = Hive.box('settings');
      final map = Map<String, dynamic>.from(data)..remove('_meta');

      // Prevent echo loop for settings by setting cache before write
      final key = '__settings__::singleton';
      _lastSentJson[key] = jsonEncode(map);

      for (final entry in map.entries) {
        await settings.put(entry.key, entry.value);
      }
    } catch (e, st) {
      if (kDebugMode) print('applyRemoteSettings fail: $e\n$st');
    }
  }

  Map<String, dynamic> _collectSettingsAsMap() {
    final settings = Hive.box('settings');
    final result = <String, dynamic>{};
    for (final key in settings.keys) {
      result[key as String] = settings.get(key);
    }
    return result;
  }

  /// Clear all user-scoped local boxes when logging out or switching users.
  Future<void> _clearLocalUserData() async {
    // Close watchers first just in case
    for (final s in _hiveSubs.values) {
      await s.cancel();
    }
    _hiveSubs.clear();

    try {
      for (final boxName in _userBoxNames) {
        if (Hive.isBoxOpen(boxName)) {
          await Hive.box(boxName).clear();
        } else {
          final box = await Hive.openBox(boxName);
          await box.clear();
        }
      }
      // Clear sync_meta timestamps so new user's remote wins
      if (Hive.isBoxOpen('sync_meta')) {
        await Hive.box('sync_meta').clear();
      }
      // Clear caches
      _suppressLocalEcho.clear();
      _lastSentJson.clear();
      for (final t in _debouncers.values) {
        t.cancel();
      }
      _debouncers.clear();
      _pendingPayloads.clear();
    } catch (e) {
      if (kDebugMode) print('Clear local data error: $e');
    }
  }

  Future<void> forceSync() async {
    final uid = _uid;
    if (uid == null || !_enabled) return;
    await _bootstrapMerge(uid);
  }
}
