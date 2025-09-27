// lib/services/firestore_sync_service.dart
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fermentacraft/services/local_mode_service.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/services/firestore_user.dart';
import 'package:fermentacraft/utils/sanitize.dart';
import '../utils/boxes.dart';
import '../models/batch_model.dart';
import '../models/inventory_item.dart';
import '../models/recipe_model.dart';
import '../models/shopping_list_item.dart';
import '../models/tag.dart';
import '../utils/data_management.dart';
import '../utils/app_logger.dart';
import '../utils/sync_retry.dart';
import '../utils/sync_error_handler.dart';
import 'firestore_paths.dart';
import 'sync_meta.dart';

typedef JsonMap = Map<String, dynamic>;

class FirestoreSyncService {
  FirestoreSyncService._();
  static final FirestoreSyncService instance = FirestoreSyncService._();

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

  // ---- Central plan/sign-in/enable gate ------------------------------------
  bool _enabled = true;
  bool get isEnabled => _enabled;
  set isEnabled(bool v) {
    if (_enabled == v) return;
    _enabled = v;
    if (!_enabled) {
      _pauseWatchers();
      return;
    }
    if (!_allowSyncByPlan) {
      // refuse enabling if user is not Premium
      _enabled = false;
      _debugWhyCantSync('isEnabled -> denied (not Premium)');
      return;
    }
    final uid = _uid;
    if (uid != null) _resumeForUid(uid);
  }

bool get _allowSyncByPlan =>
    FeatureGate.instance.allowSync && !LocalModeService.instance.isLocalOnly;  bool get _signedIn => _uid != null;
  bool get _canSync => 
    _enabled && 
    _signedIn && 
    _allowSyncByPlan && 
    _startupSyncComplete && 
    !_emergencyBrakeActive;

  void _debugWhyCantSync([String where = '']) {
    assert(() {
      debugPrint('[Sync] blocked @ $where '
          'enabled=$_enabled signedIn=$_signedIn allowSyncByPlan=$_allowSyncByPlan');
      return true;
    }());
  }

  /// Check if sync operations are healthy for a given operation
  bool isSyncHealthy(String operationType) {
    return syncRetry.isOperationHealthy(operationType);
  }

  /// Get sync health status for debugging
  Map<String, dynamic> getSyncHealthStatus() {
    return {
      'can_sync': _canSync,
      'enabled': _enabled,
      'signed_in': _signedIn,
      'allow_sync_by_plan': _allowSyncByPlan,
      'is_local_mode': LocalModeService.instance.isLocalOnly,
      'plan_allows_sync': FeatureGate.instance.allowSync,
      'current_plan': FeatureGate.instance.plan.name,
      'effective_sync_status': _canSync ? 'Active' : _getSyncBlockedReason(),
      'circuit_breakers': syncRetry.getCircuitBreakerStatus(),
    };
  }

  /// Get detailed reason why sync is blocked
  String _getSyncBlockedReason() {
    if (!_enabled) return 'Sync disabled by user';
    if (!_signedIn) return 'Not signed in';
    if (LocalModeService.instance.isLocalOnly) return 'Local mode active';
    if (!FeatureGate.instance.allowSync) return 'Plan does not include sync (${FeatureGate.instance.plan.name})';
    return 'Unknown reason';
  }

  /// Update the current context for error handling dialogs
  void updateErrorHandlingContext(BuildContext? context) {
    SyncErrorHandler.instance.updateContext(context);
  }

  void enable() => isEnabled = true;
  void disable() => isEnabled = false;
  void setEnabled(bool v) => isEnabled = v;

  bool _started = false;

  // ----------------------------- Optimizations -------------------------------

  // Prevent echo loops (remote -> local -> remote)
  final Set<String> _suppressLocalEcho = {}; // key: box::id
  final Map<String, Timer> _echoSuppressionTimers = {}; // Timed suppression

  // Debounce/coalesce local writes per doc
  final Map<String, Timer> _debouncers = {};
  final Map<String, JsonMap> _pendingPayloads = {};
  final Duration _debounce = const Duration(seconds: 3);

  // Prevent excessive writes - track recent write attempts
  final Map<String, int> _recentWrites = {};
  final Duration _writeThrottle = const Duration(seconds: 1);
  
  // Emergency brake for runaway sync - ULTRA AGGRESSIVE
  int _rapidWriteCount = 0;
  DateTime? _rapidWriteWindowStart;
  static const int _maxRapidWrites = 10; // Much lower threshold
  static const Duration _rapidWriteWindow = Duration(seconds: 30);
  bool _emergencyBrakeActive = false;
  bool _startupSyncComplete = false; // Block sync during startup

  // Skip re-sending identical JSON
  final Map<String, String> _lastSentJson = {};

  // Retry manager for reliable sync operations
  final SyncRetryManager syncRetry = SyncRetryManager.instance;

  String _keyOf(String boxName, String id) => '$boxName::$id';

  // Prevent echo loops - add with timer-based cleanup
  void _addEchoSuppressionWithTimeout(String key) {
    _suppressLocalEcho.add(key);
    
    // Also add a timer to automatically remove it after a few seconds
    // in case the immediate remove() in the Hive watcher fails
    _echoSuppressionTimers[key]?.cancel();
    _echoSuppressionTimers[key] = Timer(const Duration(seconds: 5), () {
      _suppressLocalEcho.remove(key);
      _echoSuppressionTimers.remove(key);
    });
  }

  // Clean old entries from recent writes map to prevent memory bloat
  void _cleanupRecentWrites() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _recentWrites.removeWhere((key, timestamp) => 
      (now - timestamp) > Duration(minutes: 5).inMilliseconds);
      
    // More aggressive cleanup - limit the size of all sync maps
    if (_lastSentJson.length > 100) {
      final entries = _lastSentJson.entries.toList();
      _lastSentJson.clear();
      // Keep only the 50 most recent entries
      for (final entry in entries.take(50)) {
        _lastSentJson[entry.key] = entry.value;
      }
    }
    
    // Clear old pending payloads
    if (_pendingPayloads.length > 50) {
      _pendingPayloads.clear();
    }
  }

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

  // ------------------------------- Lifecycle ---------------------------------

  Future<void> init() async {
    await SyncMetaStore.init();

    // Auth: sign-in/out & user switching
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) async {
      final newUid = user?.uid;
      
      if (kDebugMode) {
        print('[SYNC] === AUTH STATE CHANGE ===');
        print('[SYNC] New User: ${user?.uid}');
        print('[SYNC] User Email: ${user?.email}');
        print('[SYNC] Previous UID: $_uid');
        print('[SYNC] User Verified: ${user?.emailVerified}');
        print('[SYNC] User Anonymous: ${user?.isAnonymous}');
        print('[SYNC] Has Refresh Token: ${user?.refreshToken != null}');
        print('[SYNC] ================================');
      }
      
      if (newUid == null) {
        if (kDebugMode) print('[SYNC] User signed out, stopping sync');
        await _stop();
        await _clearLocalUserData();
        return;
      }
      
      // Force token refresh if token appears invalid
      if (user != null && user.refreshToken == null) {
        if (kDebugMode) print('[SYNC] Forcing auth token refresh on auth state change...');
        try {
          await user.getIdToken(true);
          if (kDebugMode) print('[SYNC] ✅ Auth token refreshed successfully on auth state change');
        } catch (refreshError) {
          if (kDebugMode) print('[SYNC] ❌ Auth token refresh failed on auth state change: $refreshError');
        }
      }
      
      if (_uid != null && _uid != newUid) {
        if (kDebugMode) print('[SYNC] User switched from $_uid to $newUid, restarting sync');
        await _stop();
        await _clearLocalUserData();
      }
      if (kDebugMode) print('[SYNC] Starting sync for user: $newUid');
      await _start(newUid);
    });

    // Connectivity: best-effort flush when network returns
    _connSub ??= _connectivity.onConnectivityChanged.listen((_) async {
      if (_canSync) {
        // Ensure user document exists before attempting any sync operations
        try {
          await FirestoreUser.instance.ensureUserDoc();
          await _bootstrapPushLocal(_uid!);
        } catch (e) {
          if (kDebugMode) {
            print('[ERROR] Connectivity sync failed: Failed to ensure user document: $e');
          }
        }
      }
    });

    // React to plan changes (Premium <-> Pro-Offline/Free)
    FeatureGate.instance.addListener(_onGateChanged);
  }

  void _onGateChanged() {
    if (!_signedIn) return;
    if (_canSync) {
      _resumeForUid(_uid!);
    } else {
      _pauseWatchers();
    }
  }

  Future<void> _start(String uid) async {
    _uid = uid;
    if (_started) return;
    if (!_enabled || !_signedIn || !_allowSyncByPlan) {
      _debugWhyCantSync('_start');
      return;
    }
    
    // Block sync during startup to prevent infinite loops
    print('[SYNC] Starting sync service - disabling sync during initialization');
    _startupSyncComplete = false;
    _started = true;

    // Ensure user document exists before attempting any sync operations
    try {
      await FirestoreUser.instance.ensureUserDoc();
    } catch (e) {
      if (kDebugMode) {
        print('[ERROR] FirestoreSync._start: Failed to ensure user document: $e');
      }
      // Don't start sync if we can't ensure the user document exists
      _started = false;
      return;
    }

    await _bootstrapMerge(uid); // pull → push converge
    for (final box in _userBoxNames) {
      _attachHiveWatcher(uid, box);
    }
    for (final box in _userBoxNames) {
      _attachFirestoreWatcher(uid, box);
    }
    _attachSettingsWatchers(uid);
  }

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
    if (!_canSync) {
      _debugWhyCantSync('_resumeForUid');
      return;
    }
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
    _recentWrites.clear();
    
    // Clean up echo suppression timers
    for (final t in _echoSuppressionTimers.values) {
      t.cancel();
    }
    _echoSuppressionTimers.clear();
    _suppressLocalEcho.clear();

    _uid = null;
  }

  Future<void> dispose() async {
    await _stop();
    await _authSub?.cancel();
    await _connSub?.cancel();
    FeatureGate.instance.removeListener(_onGateChanged);
    _authSub = null;
    _connSub = null;
  }

  // ------------------------------- Bootstrapping ------------------------------

  Future<void> _bootstrapMerge(String uid) async {
    if (!_enabled || !_signedIn || !_allowSyncByPlan) {
      _debugWhyCantSync('_bootstrapMerge');
      return;
    }
    
    // Cleanup old entries to prevent memory buildup
    _cleanupRecentWrites();
    
    print('[SYNC] Bootstrap pull starting');
    await _bootstrapPullRemote(uid);
    
    print('[SYNC] Bootstrap push starting');
    await _bootstrapPushLocal(uid);
    
    // Enable normal sync after bootstrap completes with delay
    print('[SYNC] Bootstrap completed - enabling normal sync after delay');
    
    // Add a delay to prevent immediate echo loops
    Timer(Duration(seconds: 5), () {
      _startupSyncComplete = true;
      print('[SYNC] Startup sync now enabled after bootstrap delay');
    });
  }

  Future<void> _bootstrapPullRemote(String uid) async {
    if (!_enabled || !_signedIn || !_allowSyncByPlan) {
      _debugWhyCantSync('_bootstrapPullRemote');
      return;
    }

    if (kDebugMode) {
      print('[SYNC] _bootstrapPullRemote starting for uid: $uid');
    }

    // Defensive check: Ensure user document exists before attempting any operations
    try {
      await FirestoreUser.instance.ensureUserDoc();
      if (kDebugMode) {
        print('[SYNC] _bootstrapPullRemote: User document verified');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ERROR] _bootstrapPullRemote: Failed to ensure user document: $e');
      }
      return;
    }

    for (final boxName in _userBoxNames) {
      try {
        if (kDebugMode) {
          print('[SYNC] Pulling data for box: $boxName');
        }
        final snap = await FirestorePaths.coll(uid, boxName).get();
        if (kDebugMode) {
          print('[SYNC] Found ${snap.docs.length} documents in $boxName');
        }
        
        for (final doc in snap.docs) {
          try {
            await _applyRemoteDoc(boxName, doc.id, doc.data());
            if (kDebugMode) {
              print('[SYNC] Applied remote doc: $boxName/${doc.id}');
            }
          } catch (e, st) {
            if (kDebugMode) {
              print('[ERROR] bootstrapPull apply fail [$boxName/${doc.id}]: $e\n$st');
            }
            appLogger.warning(
              'Bootstrap pull apply failed',
              category: LogCategory.sync,
              operation: 'bootstrap_pull_apply',
              error: e,
              details: {'box_name': boxName},
              userId: _uid,
            );
          }
        }
      } catch (e, st) {
        if (kDebugMode) {
          print('[ERROR] bootstrapPull fail [$boxName]: $e\n$st');
        }
        appLogger.warning(
          'Bootstrap pull failed',
          category: LogCategory.sync,
          operation: 'bootstrap_pull',
          error: e,
          details: {'box_name': boxName},
          userId: _uid,
        );
      }
    }

    // settings
    try {
      if (kDebugMode) {
        print('[SYNC] Pulling settings');
      }
      final sDoc = await FirestorePaths.settingsDoc(uid).get();
      if (sDoc.exists) {
        await _applyRemoteSettings(sDoc.data()!);
        if (kDebugMode) {
          print('[SYNC] Applied remote settings');
        }
      } else {
        if (kDebugMode) {
          print('[SYNC] No remote settings found');
        }
      }
    } catch (e, st) {
      if (kDebugMode) print('[ERROR] bootstrapPull settings fail: $e\n$st');
      appLogger.warning(
        'Bootstrap pull settings failed',
        category: LogCategory.sync,
        operation: 'bootstrap_pull_settings',
        error: e,
        userId: _uid,
      );
    }

    if (kDebugMode) {
      print('[SYNC] _bootstrapPullRemote completed');
    }
  }

  Future<void> _bootstrapPushLocal(String uid) async {
    if (!_enabled || !_signedIn || !_allowSyncByPlan) {
      _debugWhyCantSync('_bootstrapPushLocal');
      return;
    }

    // Defensive check: Ensure user document exists before attempting any operations
    try {
      await FirestoreUser.instance.ensureUserDoc();
    } catch (e) {
      if (kDebugMode) {
        print('[ERROR] _bootstrapPushLocal: Failed to ensure user document: $e');
      }
      return;
    }

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
            appLogger.warning(
              'Bootstrap push item failed',
              category: LogCategory.sync,
              operation: 'bootstrap_push_item',
              error: e,
              details: {'box_name': boxName, 'key': key.toString()},
              userId: _uid,
            );
          }
        }
      } catch (e, st) {
        if (kDebugMode) print('bootstrapPush box fail [$boxName]: $e\n$st');
        appLogger.warning(
          'Bootstrap push box failed',
          category: LogCategory.sync,
          operation: 'bootstrap_push',
          error: e,
          details: {'box_name': boxName},
          userId: _uid,
        );
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
      appLogger.warning(
        'Bootstrap push settings failed',
        category: LogCategory.sync,
        operation: 'bootstrap_push_settings',
        error: e,
        userId: _uid,
      );
    }
  }

  // -------------------------------- Watchers ---------------------------------

  void _attachHiveWatcher(String uid, String boxName) {
    final box = DataManagementService.getTypedBox(boxName);
    _hiveSubs[boxName]?.cancel();
    _hiveSubs[boxName] = box.watch().listen((event) async {
      if (!_canSync || _uid != uid) return;

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
            appLogger.warning(
              'Hive debounce flush failed',
              category: LogCategory.sync,
              operation: 'hive_debounce_flush',
              error: e,
              details: {'box_name': boxName, 'id': id},
              userId: _uid,
            );
          }
        });
      } catch (e, st) {
        if (kDebugMode) print('Hive watcher error [$boxName]: $e\n$st');
        appLogger.warning(
          'Hive watcher error',
          category: LogCategory.sync,
          operation: 'hive_watcher',
          error: e,
          details: {'box_name': boxName},
          userId: _uid,
        );
      }
    });
  }

  void _attachFirestoreWatcher(String uid, String boxName) {
    _fireSubs[boxName]?.cancel();
    _fireSubs[boxName] =
        FirestorePaths.coll(uid, boxName).snapshots().listen((querySnap) async {
      if (!_canSync || _uid != uid) return;
      for (final change in querySnap.docChanges) {
        try {
          final data = change.doc.data();
          if (data == null) continue;
          await _applyRemoteDoc(boxName, change.doc.id, data);
        } catch (e, st) {
          if (kDebugMode) print('applyRemoteDoc fail [$boxName]: $e\n$st');
          appLogger.warning(
            'Apply remote document failed',
            category: LogCategory.sync,
            operation: 'apply_remote_doc',
            error: e,
            details: {'box_name': boxName},
            userId: _uid,
          );
        }
      }
    }, onError: (e, st) {
      if (kDebugMode) print('Firestore watcher error [$boxName]: $e\n$st');
      appLogger.warning(
        'Firestore watcher error',
        category: LogCategory.sync,
        operation: 'firestore_watcher',
        error: e,
        details: {'box_name': boxName},
        userId: _uid,
      );
    });
  }

  void _attachSettingsWatchers(String uid) {
    // Push local -> remote on changes
    final settings = Hive.box('settings');
    _hiveSubs['__settings_local__']?.cancel();
    Timer? settingsDebounce;
    _hiveSubs['__settings_local__'] = settings.watch().listen((_) async {
      if (!_canSync || _uid != uid) return;
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
            appLogger.warning(
              'Settings push failed',
              category: LogCategory.sync,
              operation: 'settings_push',
              error: e,
              userId: _uid,
            );
          }
        } catch (e, st) {
          if (kDebugMode) print('settings push fail: $e\n$st');
          appLogger.warning(
            'Settings push failed',
            category: LogCategory.sync,
            operation: 'settings_push',
            error: e,
            userId: _uid,
          );
        }
      });
    });

    // Pull remote -> local
    _fireSubs['__settings_remote__']?.cancel();
    _fireSubs['__settings_remote__'] =
        FirestorePaths.settingsDoc(uid).snapshots().listen((doc) async {
      if (!_canSync || _uid != uid) return;
      try {
        final data = doc.data();
        if (data == null) return;
        await _applyRemoteSettings(data);
      } catch (e, st) {
        if (kDebugMode) print('settings pull fail: $e\n$st');
        appLogger.warning(
          'Settings pull failed',
          category: LogCategory.sync,
          operation: 'settings_pull',
          error: e,
          userId: _uid,
        );
      }
    });
  }

  // -------------------------------- Helpers ----------------------------------

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
    if (!_canSync) {
      _debugWhyCantSync('_pushLocalDocWithId');
      return;
    }

    final cleanId = id.trim();
    if (cleanId.isEmpty) {
      if (kDebugMode) print('Skip push: empty key id for $boxName: $json');
      return;
    }

    // ---------- WRITE THROTTLING (prevent infinite loops) ----------
    final writeKey = '$boxName::$cleanId';
    final writeTime = DateTime.now().millisecondsSinceEpoch;
    final lastWrite = _recentWrites[writeKey];
    if (lastWrite != null && (writeTime - lastWrite) < _writeThrottle.inMilliseconds) {
      if (kDebugMode) {
        print('[SYNC] Throttling write for $writeKey (too soon)');
      }
      return;
    }
    _recentWrites[writeKey] = writeTime;
    
    // Emergency brake for rapid writes
    final currentTime = DateTime.now();
    if (_rapidWriteWindowStart == null || currentTime.difference(_rapidWriteWindowStart!) > _rapidWriteWindow) {
      _rapidWriteWindowStart = currentTime;
      _rapidWriteCount = 0;
    }
    
    _rapidWriteCount++;
    if (_rapidWriteCount > _maxRapidWrites) {
      if (kDebugMode) {
        print('[SYNC] EMERGENCY BRAKE: Too many rapid writes ($_rapidWriteCount), disabling sync temporarily');
      }
      _emergencyBrakeActive = true;
      // Re-enable after 10 minutes
      Timer(const Duration(minutes: 10), () {
        if (kDebugMode) print('[SYNC] Re-enabling sync after emergency brake');
        _emergencyBrakeActive = false;
        _rapidWriteCount = 0;
      });
      return;
    }
    // ----------------------------------------------------------------------

    // ---------- TAGS WRITE POLICY (prevents accidental stripping) ----------
    if (boxName == Boxes.recipes || boxName == Boxes.batches) {
      final rawTags = (json['tags'] as List?);

      // Drop volatile local-only fields for recipes before comparing/sending
      if (boxName == Boxes.recipes) {
        json.remove('lastOpened');
      }

      // Canonical local sources (tri-state: unknown vs empty vs non-empty)
      dynamic refsList;
      dynamic legacyList;
      List? plainList;
      try {
        refsList = (sourceObject as dynamic).tagRefs;
      } catch (_) {}
      try {
        legacyList = (sourceObject as dynamic).tagsLegacy;
      } catch (_) {}
      try {
        plainList = (sourceObject as dynamic).tags as List?;
      } catch (_) {}

      final refsKnown = refsList != null;
      final refsNonEmpty = refsKnown && (refsList is Iterable) && refsList.isNotEmpty;

      final legacyKnown = legacyList != null;
      final legacyNonEmpty = legacyKnown && (legacyList is Iterable) && legacyList.isNotEmpty;

      final plainKnown = plainList != null;
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
      //  - payload explicitly carries [] AND
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

      // Only write tags when we truly mean to; otherwise omit to preserve server value.
      final hasLocalTags =
          (rawTags is List && rawTags.isNotEmpty) ||
              refsNonEmpty ||
              legacyNonEmpty ||
              plainNonEmpty;

      if (hasLocalTags || shouldExplicitClear) {
        final preferred =
            (rawTags != null) ? rawTags : (plainList ?? const []);
        json['tags'] = _normalizeTagsForJson(sourceObject: sourceObject, rawTags: preferred);
      } else {
        json.remove('tags');
      }
    }
    // ----------------------------------------------------------------------

    // ---- TAG POLICY ENFORCEMENT (client-side) ----
    if (boxName == Boxes.tags) {
      // never push numeric tag IDs
      if (_isNumericId(cleanId)) {
        if (kDebugMode) print('Skip push of numeric tag id "$cleanId"');
        appLogger.info(
          'Skipping push of numeric tag id',
          category: LogCategory.sync,
          operation: 'tag_push_skip',
          details: {'id': cleanId},
          userId: _uid,
        );
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
    if (_lastSentJson[key] == s) {
      if (kDebugMode) {
        print('[SYNC] Skipping identical payload for $boxName/$cleanId');
      }
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    
    if (kDebugMode) {
      print('[SYNC] === FIRESTORE WRITE ATTEMPT ===');
      print('[SYNC] UID: $uid');
      print('[SYNC] Collection: $boxName');
      print('[SYNC] Doc ID: $cleanId');
      print('[SYNC] Firebase Auth User: ${FirebaseAuth.instance.currentUser?.uid}');
      print('[SYNC] UIDs Match: ${FirebaseAuth.instance.currentUser?.uid == uid}');
      print('[SYNC] Can Sync: $_canSync');
      print('[SYNC] Path: users/$uid/$boxName/$cleanId');
      print('[SYNC] ===================================');
    }
    
    try {
      final firestoreResult = await syncRetry.retryFirestoreOperation(
        operation: () => FirestorePaths.doc(uid, boxName, cleanId).set({
          ...json,
          'id': cleanId, // ensure remote carries the id too
          '_meta': {
            'updatedAt': FieldValue.serverTimestamp(),
            'deviceUpdatedAt': now,
            'deleted': false,
          }
        }, SetOptions(merge: true)),
        operationKey: 'set_${boxName}_$cleanId',
        userId: _uid,
        context: {
          'box_name': boxName,
          'clean_id': cleanId,
          'device_updated_at': now,
        },
      );
      
      if (firestoreResult.isSuccess) {
        _lastSentJson[key] = s; // only mark after success
        await SyncMetaStore.setLastSyncedNow(boxName, cleanId, now);
      } else {
        // On failure, don't poison the equality cache
        _lastSentJson.remove(key);
        if (kDebugMode) {
          print('Firestore set failed [$boxName/$cleanId]: ${firestoreResult.error}');
        }
        SyncLogger.syncError(
          operation: 'firestore_set',
          error: firestoreResult.error!,
          userId: _uid,
          context: {'box_name': boxName, 'clean_id': cleanId},
        );
        
        // Handle user-visible error feedback
        SyncErrorHandler.instance.handleRetryError(
          operationKey: 'set_${boxName}_$cleanId',
          error: firestoreResult.error!,
          userId: _uid ?? 'unknown',
          context: {
            'box_name': boxName,
            'clean_id': cleanId,
            'device_updated_at': now,
          },
        );
        
        throw firestoreResult.error!;
      }
    } catch (e, st) {
      // On failure, don't poison the equality cache
      _lastSentJson.remove(key);
      if (kDebugMode) {
        print('Firestore set failed [$boxName/$cleanId]: $e\n$st');
      }
      SyncLogger.syncError(
        operation: 'firestore_set',
        error: e,
        userId: _uid,
        context: {'box_name': boxName, 'clean_id': cleanId},
      );
      rethrow;
    }
  }

  Future<void> _markRemoteDeleted(String uid, String boxName, String id) async {
    if (!_canSync) {
      _debugWhyCantSync('_markRemoteDeleted');
      return;
    }

    final cleanId = id.trim();
    if (cleanId.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final deleteResult = await syncRetry.retryFirestoreOperation(
      operation: () => FirestorePaths.doc(uid, boxName, cleanId).set({
        'id': cleanId,
        '_meta': {
          'updatedAt': FieldValue.serverTimestamp(),
          'deviceUpdatedAt': now,
          'deleted': true,
        }
      }, SetOptions(merge: true)),
      operationKey: 'delete_${boxName}_$cleanId',
      userId: _uid,
      context: {
        'box_name': boxName,
        'clean_id': cleanId,
        'operation': 'mark_deleted',
      },
    );
    
    if (deleteResult.isSuccess) {
      await SyncMetaStore.setLastSyncedNow(boxName, cleanId, now);
      // Also forget lastSent so a re-create won't be blocked by equality cache
      _lastSentJson.remove(_keyOf(boxName, cleanId));
    } else {
      SyncLogger.syncError(
        operation: 'firestore_mark_deleted',
        error: deleteResult.error!,
        userId: _uid,
        context: {'box_name': boxName, 'clean_id': cleanId},
      );
      throw deleteResult.error!;
    }
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
        final deleteResult = await syncRetry.retryHiveOperation(
          operation: () => box.delete(id),
          operationKey: 'delete_${boxName}_$id',
          userId: _uid,
          context: {'box_name': boxName, 'id': id, 'reason': 'remote_deleted'},
        );
        
        if (deleteResult.isSuccess) {
          await SyncMetaStore.setLastSyncedNow(boxName, id, deviceUpdatedAt);
          _lastSentJson.remove(_keyOf(boxName, id));
        } else {
          SyncLogger.syncError(
            operation: 'hive_delete_mirror',
            error: deleteResult.error!,
            userId: _uid,
            context: {'box_name': boxName, 'id': id},
          );
        }
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
        try {
          localObj = await box.get(id);
        } catch (_) {}

        bool localHasRefs = false;
        bool localHasLegacy = false;
        List? localTagsArray;
        bool localHasTagsArray = false;

        try {
          localHasRefs = (localObj?.tagRefs as dynamic)?.isNotEmpty == true;
        } catch (_) {}
        try {
          localHasLegacy = (localObj?.tagsLegacy as dynamic)?.isNotEmpty == true;
        } catch (_) {}
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

        if (!remoteHasTags &&
            (localHasRefs || localHasLegacy || localHasTagsArray || lastSentHadTags)) {
          final chosenRaw =
              localHasTagsArray ? localTagsArray : (lastSentHadTags ? lastSentTags : null);
          clean['tags'] =
              _normalizeTagsForJson(sourceObject: localObj, rawTags: chosenRaw);
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
      _addEchoSuppressionWithTimeout(k);

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

      // Default path - put object in Hive with retry
      final putResult = await syncRetry.retryHiveOperation(
        operation: () => box.put(id, obj),
        operationKey: 'put_${boxName}_$id',
        userId: _uid,
        context: {
          'box_name': boxName,
          'id': id,
          'device_updated_at': deviceUpdatedAt,
        },
      );
      
      if (putResult.isSuccess) {
        await SyncMetaStore.setLastSyncedNow(boxName, id, deviceUpdatedAt);
        _lastSentJson[k] = jsonEncode(clean);
      } else {
        SyncLogger.syncError(
          operation: 'hive_put_remote_doc',
          error: putResult.error!,
          userId: _uid,
          context: {
            'box_name': boxName,
            'id': id,
            'device_updated_at': deviceUpdatedAt,
          },
        );
        
        // Handle user-visible error feedback
        SyncErrorHandler.instance.handleRetryError(
          operationKey: 'put_${boxName}_$id',
          error: putResult.error!,
          userId: _uid ?? 'unknown',
          context: {
            'box_name': boxName,
            'id': id,
            'device_updated_at': deviceUpdatedAt,
          },
        );
        
        // Don't update sync metadata if put failed
        throw putResult.error!;
      }
    } catch (e, st) {
      if (kDebugMode) print('applyRemoteDoc exception [$boxName]: $e\n$st');
      appLogger.warning(
        'Apply remote document exception',
        category: LogCategory.sync,
        operation: 'apply_remote_doc',
        error: e,
        details: {'box_name': boxName},
        userId: _uid,
      );
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
      appLogger.warning(
        'Apply remote settings failed',
        category: LogCategory.sync,
        operation: 'apply_remote_settings',
        error: e,
        userId: _uid,
      );
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
      for (final t in _echoSuppressionTimers.values) {
        t.cancel();
      }
      _echoSuppressionTimers.clear();
      _lastSentJson.clear();
      _recentWrites.clear();
      for (final t in _debouncers.values) {
        t.cancel();
      }
      _debouncers.clear();
      _pendingPayloads.clear();
    } catch (e) {
      if (kDebugMode) print('Clear local data error: $e');
      appLogger.warning(
        'Clear local data error',
        category: LogCategory.sync,
        operation: 'clear_local_data',
        error: e,
        userId: _uid,
      );
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
        appLogger.warning(
          'Flush pending failed',
          category: LogCategory.sync,
          operation: 'flush_pending',
          error: err,
          details: {'box_name': boxName, 'id': id},
          userId: _uid,
        );
      }
    }
  }

  Future<void> forceSync() async {
    final uid = _uid;
    
    // Debug authentication and permissions state
    if (kDebugMode) {
      final currentUser = FirebaseAuth.instance.currentUser;
      final premiumStatus = FeatureGate.instance.allowSync;
      final localMode = LocalModeService.instance.isLocalOnly;
      
      print('[SYNC] === FORCE SYNC DEBUG INFO ===');
      print('[SYNC] Service UID: $uid');
      print('[SYNC] Firebase Current User: ${currentUser?.uid}');
      print('[SYNC] Firebase User Email: ${currentUser?.email}');
      print('[SYNC] Firebase User Auth Token Valid: ${currentUser?.refreshToken != null}');
      print('[SYNC] Sync Enabled: $_enabled');
      print('[SYNC] Signed In: $_signedIn');
      print('[SYNC] Premium Status (allowSync): $premiumStatus');
      print('[SYNC] Local Mode Only: $localMode');
      print('[SYNC] Allow Sync By Plan: $_allowSyncByPlan');
      print('[SYNC] Can Sync: $_canSync');
      print('[SYNC] UID Match: ${uid == currentUser?.uid}');
      print('[SYNC] =====================================');
    }
    
    if (uid == null || !_canSync) {
      _debugWhyCantSync('forceSync');
      if (kDebugMode) {
        print('[SYNC] forceSync blocked - uid: $uid, canSync: $_canSync');
      }
      return;
    }

    if (kDebugMode) {
      print('[SYNC] Starting forceSync for uid: $uid');
    }

    // Ensure user document exists before attempting any sync operations
    try {
      await FirestoreUser.instance.ensureUserDoc();
      if (kDebugMode) {
        print('[SYNC] User document ensured successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ERROR] forceSync: Failed to ensure user document: $e');
      }
      return;
    }

    // Test basic Firestore write permissions
    if (kDebugMode) {
      await _testFirestoreWrite(uid);
    }

    try {
      // 1) Flush any debounced local changes
      if (kDebugMode) print('[SYNC] Step 1: Flushing pending changes');
      await _flushPendingNow(uid);

      // 2) Push local → remote first so remote can't clobber fresh local edits
      if (kDebugMode) print('[SYNC] Step 2: Pushing local to remote');
      await _bootstrapPushLocal(uid);

      // 3) Then pull remote → local to converge any remaining deltas
      if (kDebugMode) print('[SYNC] Step 3: Pulling remote to local');
      await _bootstrapPullRemote(uid);

      if (kDebugMode) {
        print('[SYNC] ✅ forceSync completed successfully');
      }
    } catch (e, st) {
      if (kDebugMode) {
        print('[ERROR] forceSync failed during execution: $e\n$st');
      }
      SyncLogger.syncError(
        operation: 'force_sync',
        error: e,
        userId: _uid,
      );
    }
  }

  // Test method to verify basic Firestore write permissions
  Future<void> _testFirestoreWrite(String uid) async {
    try {
      if (kDebugMode) print('[SYNC] Testing Firestore write permissions...');
      
      // First, try to refresh the auth token if it's invalid
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.refreshToken == null) {
        if (kDebugMode) print('[SYNC] Auth token invalid, attempting refresh...');
        try {
          await currentUser.getIdToken(true); // force refresh
          if (kDebugMode) print('[SYNC] ✅ Auth token refreshed successfully');
        } catch (refreshError) {
          if (kDebugMode) print('[SYNC] ❌ Auth token refresh failed: $refreshError');
        }
      }
      
      final testDoc = FirestorePaths.doc(uid, 'test', 'connectivity_test');
      await testDoc.set({
        'test': true,
        'timestamp': FieldValue.serverTimestamp(),
        'uid': uid,
        'testType': 'connectivity_check',
      });
      
      if (kDebugMode) print('[SYNC] ✅ Firestore write test PASSED');
      
      // Clean up test document
      await testDoc.delete();
      if (kDebugMode) print('[SYNC] ✅ Test document cleaned up');
      
    } catch (e, st) {
      if (kDebugMode) {
        print('[SYNC] ❌ Firestore write test FAILED: $e');
        print('[SYNC] Stack trace: $st');
      }
    }
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
    if (uid == null || !_canSync) {
      _debugWhyCantSync('restoreBatch');
      return;
    }

    final id = batch.id.trim();
    if (id.isEmpty) return;

    final json = batch.toJson();

    // device-side timestamp in epoch millis (int)
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Firestore-friendly payload + ensure required fields
    final payload = sanitizeForFirestore({
      ...json,
      'id': id, // rules require id == docId
      'ownerUid': uid,
      '_meta': {
        'updatedAt': FieldValue.serverTimestamp(),
        'deviceUpdatedAt': nowMs,
        'deleted': false,
      },
    });

    await FirestorePaths.doc(uid, Boxes.batches, id).set(payload, SetOptions(merge: true));

    // cache last-sent JSON (so we can skip identical re-sends)
    _lastSentJson[_keyOf(Boxes.batches, id)] = jsonEncode(json);

    // record last-synced time in millis
    await SyncMetaStore.setLastSyncedNow(Boxes.batches, id, nowMs);
  }
}
