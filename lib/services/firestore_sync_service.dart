// lib/services/firestore_sync_service.dart
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:fermentacraft/utils/sanitize.dart';
import '../utils/boxes.dart';
import '../models/batch_model.dart';
import '../models/inventory_item.dart';
import '../models/recipe_model.dart';
import '../models/shopping_list_item.dart';
import '../models/tag.dart';
import '../utils/data_management.dart';
import 'firestore_paths.dart';
import 'sync_meta.dart';

typedef JsonMap = Map<String, dynamic>;

class FirestoreSyncService {
  FirestoreSyncService._();
  static final FirestoreSyncService instance = FirestoreSyncService._();

  final _log = Logger();

  // Keep these in sync with setup() / Boxes.*
  final _userBoxNames = const [
    Boxes.tags,
    Boxes.recipes,
    Boxes.batches,
    Boxes.inventory,
    Boxes.shoppingList,
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

  // Prevent echo loops (remote -> local -> remote)
  final Set<String> _suppressLocalEcho = {}; // key: box::id

  // Debounce/coalesce local writes per doc
  final Map<String, Timer> _debouncers = {};
  final Map<String, JsonMap> _pendingPayloads = {};
  final Duration _debounce = const Duration(seconds: 3);

  // Skip re-sending identical JSON
  final Map<String, String> _lastSentJson = {};

  String _keyOf(String boxName, String id) => '$boxName::$id';

  // Helpers for tag id policy
  bool _isNumericId(String s) => RegExp(r'^\d+$').hasMatch(s);
  String _canonicalTagIdFromData(JsonMap data) =>
      (data['name'] ?? data['id'] ?? '').toString().trim();

  List<Map<String, dynamic>> _normalizeTagsForJson({
    required dynamic sourceObject,
    required List? rawTags,
  }) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];

    // 1) Prefer any already-present raw tag maps/strings
    for (final t in (rawTags ?? const [])) {
      try {
        if (t is Map) {
          final m = Map<String, dynamic>.from(t);
          final name = (m['name'] ?? m['id'] ?? '').toString().trim();
          if (name.isEmpty) continue;
          final key = name.toLowerCase();
          if (seen.add(key)) {
            out.add({
              'id': name,
              'name': name,
              'iconKey': (m['iconKey'] ?? 'default') as String,
              'iconFontFamily': m['iconFontFamily'],
              'iconCodePoint': m['iconCodePoint'],
            });
          }
        } else if (t is String) {
          final name = t.trim();
          if (name.isEmpty) continue;
          final key = name.toLowerCase();
          if (seen.add(key)) {
            out.add({
              'id': name,
              'name': name,
              'iconKey': 'default',
              'iconFontFamily': null,
              'iconCodePoint': null,
            });
          }
        }
      } catch (_) {/* ignore one-off bad tag */}
    }

    // 2) If nothing came from raw tags, rebuild from tagRefs (and tagsLegacy fallback)
    if (out.isEmpty && sourceObject != null) {
      // Try tagRefs (HiveList<Tag>)
      try {
        final refs = (sourceObject.tagRefs as dynamic);
        if (refs != null) {
          for (final tag in refs) {
            try {
              final name = (tag.id ?? tag.name ?? '').toString().trim();
              if (name.isEmpty) continue;
              final key = name.toLowerCase();
              if (seen.add(key)) {
                out.add({
                  'id': name,
                  'name': name,
                  'iconKey': (tag.iconKey ?? 'default') as String,
                  'iconFontFamily': tag.iconFontFamily,
                  'iconCodePoint': tag.iconCodePoint,
                });
              }
            } catch (_) {}
          }
        }
      } catch (_) {}

      // Fallback: tagsLegacy (List<Tag>)
      if (out.isEmpty) {
        try {
          final legacy = (sourceObject.tagsLegacy as dynamic);
          if (legacy != null) {
            for (final tag in legacy) {
              try {
                final name = (tag.id ?? tag.name ?? '').toString().trim();
                if (name.isEmpty) continue;
                final key = name.toLowerCase();
                if (seen.add(key)) {
                  out.add({
                    'id': name,
                    'name': name,
                    'iconKey': (tag.iconKey ?? 'default') as String,
                    'iconFontFamily': tag.iconFontFamily,
                    'iconCodePoint': tag.iconCodePoint,
                  });
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
      }
    }

    return out;
  }

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

    // First time on this device: pull remote, then push local (converge)
    await _bootstrapMerge(uid);

    // Local -> Remote
    for (final boxName in _userBoxNames) {
      _attachHiveWatcher(uid, boxName);
    }

    // Remote -> Local
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
  // Pause / Resume (for isEnabled)
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

    await Future<void>.delayed(const Duration(milliseconds: 50));
    _started = true;

    await _bootstrapMerge(uid);

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
            await _applyRemoteDoc(
              boxName,
              doc.id,
              doc.data(),
            );
          } catch (e, st) {
            if (kDebugMode) {
              print('bootstrapPull apply fail [$boxName]: $e\n$st');
            }
            _log.w('bootstrapPull apply fail [$boxName]', error: e, stackTrace: st);
          }
        }
      } catch (e, st) {
        if (kDebugMode) print('bootstrapPull fail [$boxName]: $e\n$st');
        _log.w('bootstrapPull fail [$boxName]', error: e, stackTrace: st);
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
      _log.w('bootstrapPull settings fail', error: e, stackTrace: st);
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
            await _pushLocalDocWithId(uid, boxName, id, json, sourceObject: value);
          } catch (e, st) {
            if (kDebugMode) {
              print('bootstrapPush item fail [$boxName,$key]: $e\n$st');
            }
            _log.w('bootstrapPush item fail [$boxName,$key]', error: e, stackTrace: st);
          }
        }
      } catch (e, st) {
        if (kDebugMode) print('bootstrapPush box fail [$boxName]: $e\n$st');
        _log.w('bootstrapPush box fail [$boxName]', error: e, stackTrace: st);
      }
    }

    // settings
    try {
      final settingsMap = _collectSettingsAsMap();
      if (settingsMap.isNotEmpty) {
        final key = '__settings__::singleton';
        final s = jsonEncode(settingsMap);
        if (_lastSentJson[key] != s) {
          await FirestorePaths.settingsDoc(uid).set({
            ...settingsMap,
            '_meta': {'updatedAt': FieldValue.serverTimestamp()}
          }, SetOptions(merge: true));
          _lastSentJson[key] = s; // only mark after success
        }
      }
    } catch (e, st) {
      if (kDebugMode) print('bootstrapPush settings fail: $e\n$st');
      _log.w('bootstrapPush settings fail', error: e, stackTrace: st);
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
      if (_suppressLocalEcho.remove(k)) return;

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
            await _pushLocalDocWithId(uid, boxName, id, latest, sourceObject: val);
          } catch (e, st) {
            if (kDebugMode) {
              print('Hive debounce flush fail [$boxName,$id]: $e\n$st');
            }
            _log.w('Hive debounce flush fail [$boxName,$id]', error: e, stackTrace: st);
          }
        });
      } catch (e, st) {
        if (kDebugMode) print('Hive watcher error [$boxName]: $e\n$st');
        _log.w('Hive watcher error [$boxName]', error: e, stackTrace: st);
      }
    });
  }

  void _attachFirestoreWatcher(String uid, String boxName) {
    _fireSubs[boxName]?.cancel();
    _fireSubs[boxName] =
        FirestorePaths.coll(uid, boxName).snapshots().listen((querySnap) async {
      if (!_enabled || _uid != uid) return;
      for (final change in querySnap.docChanges) {
        try {
          final data = change.doc.data();
          if (data == null) continue;
          await _applyRemoteDoc(
            boxName,
            change.doc.id,
            data,
          );
        } catch (e, st) {
          if (kDebugMode) print('applyRemoteDoc fail [$boxName]: $e\n$st');
          _log.w('applyRemoteDoc fail [$boxName]', error: e, stackTrace: st);
        }
      }
    }, onError: (e, st) {
      if (kDebugMode) print('Firestore watcher error [$boxName]: $e\n$st');
      _log.w('Firestore watcher error [$boxName]', error: e, stackTrace: st);
    });
  }

  void _attachSettingsWatchers(String uid) {
    // Push local -> remote on changes
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

          try {
            await FirestorePaths.settingsDoc(uid).set({
              ...map,
              '_meta': {'updatedAt': FieldValue.serverTimestamp()}
            }, SetOptions(merge: true));
            _lastSentJson[key] = s; // only after success
          } catch (e, st) {
            if (kDebugMode) print('settings push fail: $e\n$st');
            _log.w('settings push fail', error: e, stackTrace: st);
          }
        } catch (e, st) {
          if (kDebugMode) print('settings push fail: $e\n$st');
          _log.w('settings push fail', error: e, stackTrace: st);
        }
      });
    });

    // Pull remote -> local
    _fireSubs['__settings_remote__']?.cancel();
    _fireSubs['__settings_remote__'] =
        FirestorePaths.settingsDoc(uid).snapshots().listen((doc) async {
      if (!_enabled || _uid != uid) return;
      try {
        final data = doc.data();
        if (data == null) return;
        await _applyRemoteSettings(data);
      } catch (e, st) {
        if (kDebugMode) print('settings pull fail: $e\n$st');
        _log.w('settings pull fail', error: e, stackTrace: st);
      }
    });
  }

  // -----------------------------
  // Helpers
  // -----------------------------

  Future<Box> _ensureTypedOpen(String name) {
    if (Hive.isBoxOpen(name)) {
      // Return the already-open *typed* box
      return Future.value(DataManagementService.getTypedBox(name));
    }
    // Open with the correct generic type
    switch (name) {
      case Boxes.recipes:
        return Hive.openBox<RecipeModel>(Boxes.recipes);
      case Boxes.batches:
        return Hive.openBox<BatchModel>(Boxes.batches);
      case Boxes.inventory:
        return Hive.openBox<InventoryItem>(Boxes.inventory);
      case Boxes.shoppingList:
        return Hive.openBox<ShoppingListItem>(Boxes.shoppingList);
      case Boxes.tags:
        return Hive.openBox<Tag>(Boxes.tags);
      default:
        return Hive.openBox(name);
    }
  }

  Future<void> _pushLocalDocWithId(
    String uid,
    String boxName,
    String id,
    JsonMap json, {
    dynamic sourceObject,
  }) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) {
      if (kDebugMode) print('Skip push: empty key id for $boxName: $json');
      return;
    }

    // ---------- TAGS WRITE POLICY (prevents accidental stripping) ----------
    if (boxName == Boxes.recipes || boxName == Boxes.batches) {
      final rawTags = (json['tags'] as List?);

      // Canonical local sources (tri-state: unknown vs empty vs non-empty)
      dynamic refsList;
      dynamic legacyList;
      List? plainList;
      try { refsList = (sourceObject as dynamic).tagRefs; } catch (_) {}
      try { legacyList = (sourceObject as dynamic).tagsLegacy; } catch (_) {}
      try { plainList = (sourceObject as dynamic).tags as List?; } catch (_) {}

      final refsKnown     = refsList != null;
      final refsNonEmpty  = refsKnown && (refsList is Iterable) && refsList.isNotEmpty;

      final legacyKnown   = legacyList != null;
      final legacyNonEmpty= legacyKnown && (legacyList is Iterable) && legacyList.isNotEmpty;

      final plainKnown    = plainList != null;
      final plainNonEmpty = (plainList?.isNotEmpty ?? false);

      // What did we last send (to gate intentional clears)?
      final cacheKey = _keyOf(boxName, cleanId);
      bool lastSentHadTags = false;
      try {
        final prev = _lastSentJson[cacheKey];
        if (prev != null) {
          final prevJson = Map<String, dynamic>.from(jsonDecode(prev));
          final prevTags = prevJson['tags'];
          lastSentHadTags = (prevTags is List) && prevTags.isNotEmpty;
        }
      } catch (_) {}

      // Only treat "clear" as intentional if:
      //  - the payload explicitly carries [] AND
      //  - we previously sent non-empty tags AND
      //  - every known local canonical source has no tags.
      final payloadExplicitlyEmpty =
          json.containsKey('tags') && (rawTags is List) && rawTags.isEmpty;

      final canonicalKnownEmpty =
          (!refsKnown || !refsNonEmpty) &&
          (!legacyKnown || !legacyNonEmpty) &&
          (!plainKnown || !plainNonEmpty);

      final shouldExplicitClear =
          lastSentHadTags && payloadExplicitlyEmpty && canonicalKnownEmpty;

      // Only write tags when we truly mean to (any local source has tags),
      // otherwise omit the field so Firestore preserves whatever it has.
      final hasLocalTags =
          (rawTags is List && rawTags.isNotEmpty) ||
          refsNonEmpty ||
          legacyNonEmpty ||
          plainNonEmpty;

      if (hasLocalTags || shouldExplicitClear) {
        // ignore: unnecessary_type_check
        final preferred = (rawTags != null && (rawTags is List))
            ? rawTags
            : (plainList ?? const []);
        json['tags'] =
            _normalizeTagsForJson(sourceObject: sourceObject, rawTags: preferred);
      } else {
        json.remove('tags'); // preserve server value
      }
    }
    // ----------------------------------------------------------------------

    // ---- TAG POLICY ENFORCEMENT (client-side) ----
    if (boxName == Boxes.tags) {
      // never push numeric tag IDs
      if (_isNumericId(cleanId)) {
        if (kDebugMode) print('Skip push of numeric tag id "$cleanId"');
        _log.i('Skip push of numeric tag id "$cleanId"');
        return;
      }
      // rules expect docId == id == name
      final tagId = cleanId.trim();
      json['id'] = tagId;
      json['name'] = tagId;
    }
    // ----------------------------------------------

    // Skip identical payloads
    final key = _keyOf(boxName, cleanId);
    final s = jsonEncode(json);
    if (_lastSentJson[key] == s) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await FirestorePaths.doc(uid, boxName, cleanId).set({
        ...json,
        'id': cleanId, // ensure remote carries the id too
        '_meta': {
          'updatedAt': FieldValue.serverTimestamp(),
          'deviceUpdatedAt': now,
          'deleted': false,
        }
      }, SetOptions(merge: true));
      _lastSentJson[key] = s; // only mark after success
      await SyncMetaStore.setLastSyncedNow(boxName, cleanId, now);
    } catch (e, st) {
      // On failure, don't poison the equality cache
      _lastSentJson.remove(key);
      if (kDebugMode) {
        print('Firestore set failed [$boxName/$cleanId]: $e\n$st');
      }
      _log.e('Firestore set failed [$boxName/$cleanId]', error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<void> _markRemoteDeleted(String uid, String boxName, String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await FirestorePaths.doc(uid, boxName, cleanId).set({
      'id': cleanId,
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

  Future<void> _applyRemoteDoc(
    String boxName,
    String remoteDocId,
    JsonMap data,
  ) async {
    try {
      final meta = (data['_meta'] as Map?) ?? {};
      final deviceUpdatedAt = (meta['deviceUpdatedAt'] as num?)?.toInt() ?? 0;
      final deleted = (meta['deleted'] as bool?) ?? false;

      // Canonical ID rules (tags use 'name'; others use 'id' fallback 'name')
      final String id = (boxName == Boxes.tags)
          ? _canonicalTagIdFromData(data)
          : (data['id'] ?? data['name'] ?? '').toString().trim();

      if (id.isEmpty) return;

      final last = SyncMetaStore.getLastSyncedMillis(boxName, id) ?? 0;
      if (deviceUpdatedAt < last) {
        // Local newer; ignore remote
        return;
      }

      final box = DataManagementService.getTypedBox(boxName);

      // If remote is marked deleted, mirror locally
      if (deleted) {
        await box.delete(id);
        await SyncMetaStore.setLastSyncedNow(boxName, id, deviceUpdatedAt);
        _lastSentJson.remove(_keyOf(boxName, id));
        return;
      }

      // ---- TAG POLICY CLEANUP (server -> client) ----
      if (boxName == Boxes.tags) {
        // tombstone legacy numeric doc id if it differs from canonical
        if (remoteDocId != id && _isNumericId(remoteDocId)) {
          try {
            await box.delete(remoteDocId);
          } catch (_) {}
          if (_uid != null) {
            try {
              await _markRemoteDeleted(_uid!, boxName, remoteDocId);
            } catch (_) {}
          }
        }
        // Force local canonical fields so models stay consistent
        data = Map<String, dynamic>.from(data);
        data['id'] = id;
        data['name'] = id;
      }
      // -----------------------------------------------

      // Also tombstone any mismatched non-numeric docId (case-insensitive ok)
      if (remoteDocId != id && _uid != null) {
        final sameIgnoringCase = remoteDocId.toLowerCase() == id.toLowerCase();
        if (!sameIgnoringCase) {
          try {
            await _markRemoteDeleted(_uid!, boxName, remoteDocId);
          } catch (_) {}
        }
      }

      // Start with a shallow clean copy
      final clean = Map<String, dynamic>.from(data)..remove('_meta');

      // ---- Merge policy to avoid tag loss on pull ----
      if (boxName == Boxes.recipes || boxName == Boxes.batches) {
        final remoteTags = (clean['tags'] as List?) ?? const [];
        final remoteHasTags = remoteTags.isNotEmpty;

        dynamic localObj;
        try { localObj = await box.get(id); } catch (_) {}

        bool localHasRefs = false;
        bool localHasLegacy = false;
        List? localTagsArray;
        bool localHasTagsArray = false;

        try { localHasRefs = (localObj?.tagRefs as dynamic)?.isNotEmpty == true; } catch (_) {}
        try { localHasLegacy = (localObj?.tagsLegacy as dynamic)?.isNotEmpty == true; } catch (_) {}
        try {
          localTagsArray = (localObj as dynamic)?.tags as List?;
          localHasTagsArray = localTagsArray != null && localTagsArray.isNotEmpty;
        } catch (_) {}

        // Last-sent fallback (helps the very first pull after a write)
        final k = _keyOf(boxName, id);
        bool lastSentHadTags = false;
        List<dynamic> lastSentTags = const [];
        try {
          final prev = _lastSentJson[k];
          if (prev != null) {
            final prevJson = Map<String, dynamic>.from(jsonDecode(prev));
            final prevTags = prevJson['tags'];
            if (prevTags is List && prevTags.isNotEmpty) {
              lastSentHadTags = true;
              lastSentTags = prevTags;
            }
          }
        } catch (_) {}

        if (!remoteHasTags && (localHasRefs || localHasLegacy || localHasTagsArray || lastSentHadTags)) {
          final chosenRaw = localHasTagsArray ? localTagsArray : (lastSentHadTags ? lastSentTags : null);
          clean['tags'] = _normalizeTagsForJson(
            sourceObject: localObj,
            rawTags: chosenRaw,
          );
        } else {
          // Otherwise sanitize what we got from remote (upgrade strings, dedupe)
          final raw = (clean['tags'] as List?) ?? const [];
          final seen = <String>{};
          final List<Map<String, dynamic>> tagsSanitized = [];
          for (final t in raw) {
            try {
              if (t is Map) {
                final m = Map<String, dynamic>.from(t);
                final name = (m['name'] ?? m['id'] ?? '').toString().trim();
                if (name.isEmpty) continue;
                final key = name.toLowerCase();
                if (seen.add(key)) {
                  tagsSanitized.add({
                    'id': name,
                    'name': name,
                    'iconKey': (m['iconKey'] ?? 'default') as String,
                    'iconFontFamily': m['iconFontFamily'],
                    'iconCodePoint': m['iconCodePoint'],
                  });
                }
              } else if (t is String) {
                final name = t.trim();
                if (name.isEmpty) continue;
                final key = name.toLowerCase();
                if (seen.add(key)) {
                  tagsSanitized.add({
                    'id': name,
                    'name': name,
                    'iconKey': 'default',
                    'iconFontFamily': null,
                    'iconCodePoint': null,
                  });
                }
              }
            } catch (_) {}
          }
          clean['tags'] = tagsSanitized;
        }
      }
      // ---------------------------------------------------------------------

      final ctor = DataManagementService.fromJsonFor(boxName);
      final obj = ctor(clean);

      // Prevent echo
      final k = _keyOf(boxName, id);
      _suppressLocalEcho.add(k);

      // For recipes/batches: write fast, then bind canonical tag refs asynchronously
      if (boxName == Boxes.recipes && obj is RecipeModel) {
        await (box as Box<RecipeModel>).put(id, obj);
        await SyncMetaStore.setLastSyncedNow(boxName, id, deviceUpdatedAt);
        _lastSentJson[k] = jsonEncode(clean);

        scheduleMicrotask(() async {
          try {
            final tagBox = Hive.box<Tag>(Boxes.tags);
            await obj.setTagsFromBox(obj.tags, tagBox); // calls save()
          } catch (_) {}
        });
        return;
      }

      if (boxName == Boxes.batches && obj is BatchModel) {
        await (box as Box<BatchModel>).put(id, obj);
        await SyncMetaStore.setLastSyncedNow(boxName, id, deviceUpdatedAt);
        _lastSentJson[k] = jsonEncode(clean);

        // Try dynamic tag-ref canonicalization for batches (if model provides it)
        scheduleMicrotask(() async {
          try {
            final tagBox = Hive.box<Tag>(Boxes.tags);
            final dyn = obj as dynamic;
            if (dyn.setTagsFromBox != null) {
              await dyn.setTagsFromBox(dyn.tags, tagBox); // calls save() if implemented
            }
          } catch (_) {}
        });
        return;
      }

      // Default path
      await box.put(id, obj);
      await SyncMetaStore.setLastSyncedNow(boxName, id, deviceUpdatedAt);
      _lastSentJson[k] = jsonEncode(clean);
    } catch (e, st) {
      if (kDebugMode) print('applyRemoteDoc exception [$boxName]: $e\n$st');
      _log.w('applyRemoteDoc exception [$boxName]', error: e, stackTrace: st);
    }
  }

  Future<void> _applyRemoteSettings(JsonMap data) async {
    try {
      final settings = Hive.box('settings');
      final map = Map<String, dynamic>.from(data)..remove('_meta');

      final key = '__settings__::singleton';
      _lastSentJson[key] = jsonEncode(map);

      for (final entry in map.entries) {
        await settings.put(entry.key, entry.value);
      }
    } catch (e, st) {
      if (kDebugMode) print('applyRemoteSettings fail: $e\n$st');
      _log.w('applyRemoteSettings fail', error: e, stackTrace: st);
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
    for (final s in _hiveSubs.values) {
      await s.cancel();
    }
    _hiveSubs.clear();

    try {
      for (final boxName in _userBoxNames) {
        final wasOpen = Hive.isBoxOpen(boxName);
        final box = await _ensureTypedOpen(boxName);
        await box.clear();
        if (!wasOpen) {
          await box.close();
        }
      }

      if (Hive.isBoxOpen('sync_meta')) {
        await Hive.box('sync_meta').clear();
      }

      _suppressLocalEcho.clear();
      _lastSentJson.clear();
      for (final t in _debouncers.values) {
        t.cancel();
      }
      _debouncers.clear();
      _pendingPayloads.clear();
    } catch (e) {
      if (kDebugMode) print('Clear local data error: $e');
      _log.w('Clear local data error', error: e);
    }
  }

  // Flush any debounced, coalesced local writes immediately.
  Future<void> _flushPendingNow(String uid) async {
    for (final t in _debouncers.values) {
      t.cancel();
    }
    _debouncers.clear();

    final entries = _pendingPayloads.entries.toList();
    _pendingPayloads.clear();

    for (final e in entries) {
      final k = e.key; // format: boxName::id
      final sep = k.indexOf('::');
      if (sep <= 0) continue;
      final boxName = k.substring(0, sep);
      final id = k.substring(sep + 2);
      try {
        final box = DataManagementService.getTypedBox(boxName);
        final sourceObject = box.get(id);
        if (sourceObject == null) continue;
        await _pushLocalDocWithId(uid, boxName, id, e.value, sourceObject: sourceObject);
      } catch (err, st) {
        if (kDebugMode) {
          print('flushPending fail [$boxName/$id]: $err\n$st');
        }
        _log.w('flushPending fail [$boxName/$id]', error: err, stackTrace: st);
      }
    }
  }

  Future<void> forceSync() async {
    final uid = _uid;
    if (uid == null || !_enabled) return;

    // 1) Flush any debounced local changes
    await _flushPendingNow(uid);

    // 2) Push local → remote first so remote can't clobber fresh local edits
    await _bootstrapPushLocal(uid);

    // 3) Then pull remote → local to converge any remaining deltas
    await _bootstrapPullRemote(uid);
  }

  // ------------------------------------------------------------------
  // Public helpers
  // ------------------------------------------------------------------

  Future<void> markDeleted({
    required String collection,
    required String id,
  }) async {
    final uid = _uid;
    if (uid == null || id.trim().isEmpty) return;
    await _markRemoteDeleted(uid, collection, id);
  }

  Future<void> restoreBatch(BatchModel batch) async {
  final uid = _uid;
  if (uid == null) return;

  final id = batch.id.trim();
  if (id.isEmpty) return;

  final json = batch.toJson();

  // device-side timestamp in epoch millis (int)
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  // Firestore-friendly payload + ensure required fields
  final payload = sanitizeForFirestore({
    ...json,
    'id': id,                // rules require id == docId
    'ownerUid': uid,         // helps if client filters on owner
    '_meta': {
      'updatedAt': FieldValue.serverTimestamp(), // server authoritative
      'deviceUpdatedAt': nowMs,                  // int (millis)
      'deleted': false,
    },
  });

  await FirestorePaths.doc(uid, Boxes.batches, id)
      .set(payload, SetOptions(merge: true));

  // cache last-sent JSON (so we can skip identical re-sends)
  _lastSentJson[_keyOf(Boxes.batches, id)] = jsonEncode(json);

  // record last-synced time in millis
  await SyncMetaStore.setLastSyncedNow(Boxes.batches, id, nowMs);
}

}
