import 'dart:async';
import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fermentacraft/repositories/repositories.dart';
import 'package:fermentacraft/services/auth_service.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/services/local_mode_service.dart';
import 'package:fermentacraft/utils/result.dart';

/// Modern sync coordinator that manages multiple repositories
/// Replaces the monolithic FirestoreSyncService with clean repository pattern
class SyncCoordinator {
  static SyncCoordinator? _instance;
  static SyncCoordinator get instance => _instance ??= SyncCoordinator._();

  SyncCoordinator._();

  // Repository dependencies
  BatchRepository? _batchRepository;
  RecipeRepository? _recipeRepository;

  // Service dependencies
  final AuthService _authService = AuthService.instance;
  final Connectivity _connectivity = Connectivity();
  final FeatureGate _featureGate = FeatureGate.instance;
  final LocalModeService _localMode = LocalModeService.instance;

  // State management
  bool _isInitialized = false;
  bool _isEnabled = true;
  bool _isSyncing = false;
  DateTime? _lastFullSyncTime;

  // Event streams
  final StreamController<bool> _syncStatusController =
      StreamController<bool>.broadcast();
  final StreamController<SyncEvent> _syncEventController =
      StreamController<SyncEvent>.broadcast();

  StreamSubscription? _authSubscription;
  StreamSubscription? _connectivitySubscription;
  Timer? _periodicSyncTimer;

  // Public getters
  bool get isInitialized => _isInitialized;
  bool get isEnabled => _isEnabled;
  bool get isSyncing => _isSyncing;
  bool get canSync => _canSyncInternal();
  DateTime? get lastFullSyncTime => _lastFullSyncTime;

  Stream<bool> get syncStatusStream => _syncStatusController.stream;
  Stream<SyncEvent> get syncEventStream => _syncEventController.stream;

  /// Initialize the sync coordinator with repository dependencies
  Future<Result<void, Exception>> initialize({
    required BatchRepository batchRepository,
    required RecipeRepository recipeRepository,
  }) async {
    if (_isInitialized) {
      return const Success(null);
    }

    try {
      _batchRepository = batchRepository;
      _recipeRepository = recipeRepository;

      // Initialize repositories
      final batchResult = await _batchRepository!.initialize();
      if (batchResult.isFailure) {
        return Failure(Exception(
            'Failed to initialize batch repository: ${batchResult.error}'));
      }

      final recipeResult = await _recipeRepository!.initialize();
      if (recipeResult.isFailure) {
        return Failure(Exception(
            'Failed to initialize recipe repository: ${recipeResult.error}'));
      }

      // Set up auth listener
      _setupAuthListener();

      // Set up connectivity listener
      _setupConnectivityListener();

      // Start periodic sync timer
      _startPeriodicSync();

      _isInitialized = true;

      log('SyncCoordinator initialized successfully', name: 'SyncCoordinator');

      return const Success(null);
    } catch (e, stackTrace) {
      log('Failed to initialize SyncCoordinator: $e',
          error: e, stackTrace: stackTrace, name: 'SyncCoordinator');
      return Failure(Exception('Failed to initialize sync coordinator: $e'));
    }
  }

  /// Enable or disable automatic synchronization
  void setEnabled(bool enabled) {
    if (_isEnabled == enabled) return;

    _isEnabled = enabled;

    if (!enabled) {
      _stopPeriodicSync();
      log('Sync disabled', name: 'SyncCoordinator');
    } else if (canSync) {
      _startPeriodicSync();
      log('Sync enabled', name: 'SyncCoordinator');

      // Trigger immediate sync if user is authenticated
      if (_authService.currentUser != null) {
        performFullSync().ignore();
      }
    }

    _emitSyncEvent(SyncEvent.enabledChanged(enabled));
  }

  /// Perform a complete synchronization of all repositories
  Future<Result<SyncSummary, Exception>> performFullSync() async {
    if (!canSync) {
      final reason = _getSyncBlockReason();
      log('Sync blocked: $reason', name: 'SyncCoordinator');
      return Failure(Exception('Sync not available: $reason'));
    }

    if (_isSyncing) {
      return Failure(Exception('Sync already in progress'));
    }

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        _isSyncing = true;
        _syncStatusController.add(true);
        _emitSyncEvent(SyncEvent.started());

        log('Starting full sync (attempt ${retryCount + 1}/$maxRetries)',
            name: 'SyncCoordinator');

        final summary = SyncSummary();

        // Sync batches with timeout
        Result<dynamic, Exception>? batchResult;
        try {
          batchResult = await _batchRepository!.sync().timeout(
                const Duration(seconds: 30),
                onTimeout: () => throw TimeoutException(
                    'Batch sync timed out', const Duration(seconds: 30)),
              );
          summary.batchSyncSuccess = batchResult.isSuccess;
        } catch (e) {
          batchResult = Failure(Exception('Batch sync failed: $e'));
          summary.batchSyncSuccess = false;
        }

        if (batchResult.isFailure) {
          summary.errors.add('Batch sync failed: ${batchResult.error}');
        }

        // Sync recipes with timeout
        Result<dynamic, Exception>? recipeResult;
        try {
          recipeResult = await _recipeRepository!.sync().timeout(
                const Duration(seconds: 30),
                onTimeout: () => throw TimeoutException(
                    'Recipe sync timed out', const Duration(seconds: 30)),
              );
          summary.recipeSyncSuccess = recipeResult.isSuccess;
        } catch (e) {
          recipeResult = Failure(Exception('Recipe sync failed: $e'));
          summary.recipeSyncSuccess = false;
        }

        if (recipeResult.isFailure) {
          summary.errors.add('Recipe sync failed: ${recipeResult.error}');
        }

        // Check if sync was successful
        if (summary.hasErrors && retryCount < maxRetries - 1) {
          retryCount++;
          log('Sync had errors, retrying in ${retryCount * 2} seconds...',
              name: 'SyncCoordinator');
          await Future.delayed(Duration(seconds: retryCount * 2));
          continue;
        }

        // If we get here, either success or final attempt
        _lastFullSyncTime = DateTime.now();

        log('Full sync completed with ${summary.errors.length} errors',
            name: 'SyncCoordinator');
        _emitSyncEvent(SyncEvent.completed(summary));

        return Success(summary);
      } catch (e) {
        log('Full sync attempt ${retryCount + 1} failed: $e',
            error: e, name: 'SyncCoordinator');

        if (retryCount < maxRetries - 1) {
          retryCount++;
          log('Retrying sync in ${retryCount * 2} seconds...',
              name: 'SyncCoordinator');
          await Future.delayed(Duration(seconds: retryCount * 2));
          continue;
        } else {
          // Final attempt failed
          _emitSyncEvent(SyncEvent.failed(e.toString()));
          return Failure(
              Exception('Full sync failed after $maxRetries attempts: $e'));
        }
      } finally {
        _isSyncing = false;
        _syncStatusController.add(false);
      }
    }

    // Should never reach here
    return Failure(Exception('Unexpected sync failure'));
  }

  /// Clear all local data and force fresh sync from server
  Future<Result<void, Exception>> clearCacheAndResync() async {
    if (!canSync) {
      return Failure(Exception('Sync not available'));
    }

    try {
      log('Clearing cache and resyncing', name: 'SyncCoordinator');

      // Clear all repository caches
      await _batchRepository!.clearCache();
      await _recipeRepository!.clearCache();

      // Perform fresh sync
      final syncResult = await performFullSync();
      if (syncResult.isFailure) {
        return Failure(Exception('Resync failed: ${syncResult.error}'));
      }

      _emitSyncEvent(SyncEvent.cacheCleared());

      return const Success(null);
    } catch (e) {
      log('Clear cache and resync failed: $e',
          error: e, name: 'SyncCoordinator');
      return Failure(Exception('Clear cache and resync failed: $e'));
    }
  }

  /// Get sync status for all repositories
  Map<String, dynamic> getSyncStatus() {
    return {
      'canSync': canSync,
      'isEnabled': _isEnabled,
      'isSyncing': _isSyncing,
      'isAuthenticated': _authService.currentUser != null,
      'localModeActive': _localMode.isLocalOnly,
      'featureGateAllowed': _featureGate.allowSync,
      'lastFullSync': _lastFullSyncTime?.toIso8601String(),
      'batchRepository': {
        'lastSync': _batchRepository?.getLastSyncTime()?.toIso8601String(),
        'isSyncing': _batchRepository?.isSyncing ?? false,
      },
      'recipeRepository': {
        'lastSync': _recipeRepository?.getLastSyncTime()?.toIso8601String(),
        'isSyncing': _recipeRepository?.isSyncing ?? false,
      },
    };
  }

  /// Dispose resources and cleanup
  Future<void> dispose() async {
    _stopPeriodicSync();

    await _authSubscription?.cancel();
    await _connectivitySubscription?.cancel();

    _batchRepository?.dispose();
    _recipeRepository?.dispose();

    await _syncStatusController.close();
    await _syncEventController.close();

    _isInitialized = false;

    log('SyncCoordinator disposed', name: 'SyncCoordinator');
  }

  // Private methods

  bool _canSyncInternal() {
    return _isEnabled &&
        _isInitialized &&
        _authService.currentUser != null &&
        _featureGate.allowSync &&
        !_localMode.isLocalOnly;
  }

  String _getSyncBlockReason() {
    if (!_isEnabled) return 'Sync disabled';
    if (!_isInitialized) return 'Not initialized';
    if (_authService.currentUser == null) return 'Not authenticated';
    if (!_featureGate.allowSync) return 'Feature gate blocked';
    if (_localMode.isLocalOnly) return 'Local mode active';
    return 'Unknown reason';
  }

  void _setupAuthListener() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && canSync) {
        log('User authenticated, triggering sync', name: 'SyncCoordinator');
        performFullSync().ignore();
      } else if (user == null) {
        log('User signed out, stopping sync', name: 'SyncCoordinator');
        _stopPeriodicSync();
      }

      _emitSyncEvent(SyncEvent.authChanged(user != null));
    });
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = _connectivity.onConnectivityChanged
        .listen((List<ConnectivityResult> result) {
      // connectivity_plus v6+: onConnectivityChanged emits List<ConnectivityResult>
      final isOnline = result.any((r) => r != ConnectivityResult.none);

      if (isOnline && canSync && !_isSyncing) {
        log('Network connectivity restored, triggering sync',
            name: 'SyncCoordinator');
        performFullSync().ignore();
      }

      _emitSyncEvent(SyncEvent.connectivityChanged(isOnline));
    });
  }

  void _startPeriodicSync() {
    _stopPeriodicSync(); // Cancel existing timer

    if (!canSync) return;

    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
      if (canSync && !_isSyncing) {
        performFullSync().ignore();
      }
    });

    log('Periodic sync started (15 min interval)', name: 'SyncCoordinator');
  }

  void _stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  void _emitSyncEvent(SyncEvent event) {
    _syncEventController.add(event);
  }
}

/// Summary of synchronization operation results
class SyncSummary {
  bool batchSyncSuccess = false;
  bool recipeSyncSuccess = false;
  List<String> errors = [];

  bool get hasErrors => errors.isNotEmpty;
  bool get allSuccessful => batchSyncSuccess && recipeSyncSuccess && !hasErrors;

  @override
  String toString() {
    return 'SyncSummary(batches: ${batchSyncSuccess ? 'OK' : 'FAIL'}, '
        'recipes: ${recipeSyncSuccess ? 'OK' : 'FAIL'}, '
        'errors: ${errors.length})';
  }
}

/// Events emitted by the sync coordinator
sealed class SyncEvent {
  const SyncEvent();

  factory SyncEvent.started() = SyncStarted;
  factory SyncEvent.completed(SyncSummary summary) = SyncCompleted;
  factory SyncEvent.failed(String error) = SyncFailed;
  factory SyncEvent.authChanged(bool isAuthenticated) = AuthChanged;
  factory SyncEvent.connectivityChanged(bool isOnline) = ConnectivityChanged;
  factory SyncEvent.enabledChanged(bool isEnabled) = EnabledChanged;
  factory SyncEvent.cacheCleared() = CacheCleared;
}

class SyncStarted extends SyncEvent {
  const SyncStarted();
}

class SyncCompleted extends SyncEvent {
  final SyncSummary summary;
  const SyncCompleted(this.summary);
}

class SyncFailed extends SyncEvent {
  final String error;
  const SyncFailed(this.error);
}

class AuthChanged extends SyncEvent {
  final bool isAuthenticated;
  const AuthChanged(this.isAuthenticated);
}

class ConnectivityChanged extends SyncEvent {
  final bool isOnline;
  const ConnectivityChanged(this.isOnline);
}

class EnabledChanged extends SyncEvent {
  final bool isEnabled;
  const EnabledChanged(this.isEnabled);
}

class CacheCleared extends SyncEvent {
  const CacheCleared();
}
