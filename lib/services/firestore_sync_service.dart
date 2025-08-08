// lib/services/firestore_sync_service.dart
// ignore_for_file: avoid_print
import 'dart:async';

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
    // NOTE: settings is handled specially (doc), not as a box here
  ];

  StreamSubscription? _authSub;
  final Map<String, StreamSubscription> _hiveSubs = {};
  final Map<String, StreamSubscription> _fireSubs = {};
  final _connectivity = Connectivity();
  StreamSubscription? _connSub;

  String? _uid;
  bool _enabled = true;
  bool _started = false;

  bool get isEnabled => _enabled;
  set isEnabled(bool v) { _enabled = v; }

  Future<void> init() async {
    await SyncMetaStore.init();

    // React to sign-in/out & user switching
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) async {
      final oldUid = _uid;
      final newUid = user?.uid;

      if (newUid == null) {
        // Signed out -> stop syncing and clear local user data
        await _stop();
        await _clearLocalUserData();
        return;
      }

      if (oldUid != null && oldUid != newUid) {
        // Switched to a different account -> stop, purge, then start fresh
        await _stop();
        await _clearLocalUserData();
      }

      // Start syncing for current user
      await _start(newUid);
    });

    _connSub ??= _connectivity.onConnectivityChanged.listen((_) {
      if (_uid != null && _enabled) {
        _bootstrapPushLocal(_uid!); // best-effort flush when network returns
      }
    });
  }

  Future<void> _start(String uid) async {
    _uid = uid;
    if (_started) return;
    _started = true;
    if (!_enabled) return;

    // First time for this user on this device: pull remote, then push local
    // (Merge ensures both sides converge)
    await _bootstrapMerge(uid);

    // Start watchers: local -> remote
    for (final boxName in _userBoxNames) {
      _attachHiveWatcher(uid, boxName);
    }

    // Start remote -> local
    for (final boxName in _userBoxNames) {
      _attachFirestoreWatcher(uid, boxName);
    }

    // Settings sync (local <-> remote)
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
  // Bootstrapping
  // -----------------------------

  Future<void> _bootstrapMerge(String uid) async {
    await _bootstrapPullRemote(uid);
    await _bootstrapPushLocal(uid);
  }

  Future<void> _bootstrapPullRemote(String uid) async {
    for (final boxName in _userBoxNames) {
      final snap = await FirestorePaths.coll(uid, boxName).get();
      for (final doc in snap.docs) {
        await _applyRemoteDoc(boxName, doc.data(), preferRemote: true);
      }
    }

    // settings
    final sDoc = await FirestorePaths.settingsDoc(uid).get();
    if (sDoc.exists) {
      await _applyRemoteSettings(sDoc.data()!);
    }
  }

  Future<void> _bootstrapPushLocal(String uid) async {
    for (final boxName in _userBoxNames) {
      final box = DataManagementService.getTypedBox(boxName);
      for (final key in box.keys) {
        final dynamic value = box.get(key);
        if (value == null) continue;
        final json = (value as dynamic).toJson() as JsonMap;
        await _pushLocalDoc(uid, boxName, json);
      }
    }

    // settings
    final settingsMap = _collectSettingsAsMap();
    if (settingsMap.isNotEmpty) {
      await FirestorePaths.settingsDoc(uid).set({
        ...settingsMap,
        '_meta': {'updatedAt': FieldValue.serverTimestamp()}
      }, SetOptions(merge: true));
    }
  }

  // -----------------------------
  // Watchers
  // -----------------------------

  void _attachHiveWatcher(String uid, String boxName) {
    final box = DataManagementService.getTypedBox(boxName);
    _hiveSubs[boxName]?.cancel();
    _hiveSubs[boxName] = box.watch().listen((event) async {
      if (!_enabled || _uid != uid) return; // guard against late events
      try {
        if (event.deleted) {
          final id = event.key.toString();
          await _markRemoteDeleted(uid, boxName, id);
          return;
        }
        final dynamic val = box.get(event.key);
        if (val == null) return;
        final json = (val as dynamic).toJson() as JsonMap;
        await _pushLocalDoc(uid, boxName, json);
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
        final data = change.doc.data();
        if (data == null) continue;
        await _applyRemoteDoc(boxName, data, preferRemote: true);
      }
    }, onError: (e, st) {
      if (kDebugMode) print('Firestore watcher error [$boxName]: $e\n$st');
    });
  }

  void _attachSettingsWatchers(String uid) {
    // Push local -> remote on changes
    final settings = Hive.box('settings');
    _hiveSubs['__settings_local__']?.cancel();
    _hiveSubs['__settings_local__'] = settings.watch().listen((_) async {
      if (!_enabled || _uid != uid) return;
      final map = _collectSettingsAsMap();
      if (map.isEmpty) return;
      await FirestorePaths.settingsDoc(uid).set({
        ...map,
        '_meta': {'updatedAt': FieldValue.serverTimestamp()}
      }, SetOptions(merge: true));
    });

    // Pull remote -> local
    _fireSubs['__settings_remote__']?.cancel();
    _fireSubs['__settings_remote__'] = FirestorePaths.settingsDoc(uid)
        .snapshots()
        .listen((doc) async {
      if (!_enabled || _uid != uid) return;
      final data = doc.data();
      if (data == null) return;
      await _applyRemoteSettings(data);
    });
  }

  // -----------------------------
  // Helpers
  // -----------------------------

  Future<void> _pushLocalDoc(String uid, String boxName, JsonMap json) async {
    final id = (json['id'] ?? json['name'] ?? '').toString();
    if (id.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await FirestorePaths.doc(uid, boxName, id).set({
      ...json,
      '_meta': {
        'updatedAt': FieldValue.serverTimestamp(),
        'deviceUpdatedAt': now,
        'deleted': false,
      }
    }, SetOptions(merge: true));

    await SyncMetaStore.setLastSyncedNow(boxName, id, now);
  }

  Future<void> _markRemoteDeleted(String uid, String boxName, String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await FirestorePaths.doc(uid, boxName, id).set({
      '_meta': {
        'updatedAt': FieldValue.serverTimestamp(),
        'deviceUpdatedAt': now,
        'deleted': true,
      }
    }, SetOptions(merge: true));
    await SyncMetaStore.setLastSyncedNow(boxName, id, now);
  }

  Future<void> _applyRemoteDoc(String boxName, JsonMap data, {required bool preferRemote}) async {
    final meta = (data['_meta'] as Map?) ?? {};
    final deviceUpdatedAt = (meta['deviceUpdatedAt'] as num?)?.toInt() ?? 0;
    final deleted = (meta['deleted'] as bool?) ?? false;

    final id = (data['id'] ?? data['name'] ?? '').toString();
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
      return;
    }

    final clean = Map<String, dynamic>.from(data)..remove('_meta');
    final ctor = DataManagementService.fromJsonFor(boxName);
    final obj = ctor(clean);
    await box.put(id, obj);
    await SyncMetaStore.setLastSyncedNow(boxName, id, deviceUpdatedAt);
  }

  Future<void> _applyRemoteSettings(JsonMap data) async {
    final settings = Hive.box('settings');
    final map = Map<String, dynamic>.from(data)..remove('_meta');
    for (final entry in map.entries) {
      await settings.put(entry.key, entry.value);
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
        } else if (Hive.isBoxOpen(boxName) == false && Hive.isBoxOpen(boxName) != null) {
          // no-op
        } else {
          final box = await Hive.openBox(boxName);
          await box.clear();
          await box.close();
        }
      }
      // Clear sync_meta timestamps so new user's remote wins
      if (Hive.isBoxOpen('sync_meta')) {
        await Hive.box('sync_meta').clear();
      }
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
