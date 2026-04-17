import 'dart:async';
import 'dart:developer';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/repositories/base_repository.dart';
import 'package:fermentacraft/utils/result.dart';
import 'package:fermentacraft/services/auth_service.dart';

/// Repository for managing batch data with local-first approach
/// Implements offline-first strategy with background synchronization
class BatchRepository implements BaseRepository<BatchModel> {
  static const String _boxName = 'batches';
  static const String _syncBoxName = 'batch_sync_metadata';
  
  late Box<BatchModel> _batchBox;
  late Box<Map<dynamic, dynamic>> _syncBox;
  late Box<int> _timestampBox;
  
  final AuthService _authService;
  final FirebaseFirestore _firestore;
  final RepositoryConfig _config;
  
  bool _isInitialized = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  
  final StreamController<bool> _syncStatusController = StreamController<bool>.broadcast();
  final StreamController<Result<List<BatchModel>, Exception>> _batchesController = 
      StreamController<Result<List<BatchModel>, Exception>>.broadcast();
  final Map<String, StreamController<Result<BatchModel?, Exception>>> _singleBatchControllers = {};
  
  BatchRepository({
    required AuthService authService,
    FirebaseFirestore? firestore,
    RepositoryConfig? config,
  }) : _authService = authService,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _config = config ?? const RepositoryConfig();

  /// Initialize the repository - must be called before use
  Future<Result<void, Exception>> initialize() async {
    try {
      // Check if boxes are already open
      if (Hive.isBoxOpen(_boxName)) {
        _batchBox = Hive.box<BatchModel>(_boxName);
      } else {
        _batchBox = await Hive.openBox<BatchModel>(_boxName);
      }
      
      if (Hive.isBoxOpen(_syncBoxName)) {
        _syncBox = Hive.box<Map<dynamic, dynamic>>(_syncBoxName);
      } else {
        _syncBox = await Hive.openBox<Map<dynamic, dynamic>>(_syncBoxName);
      }
      
      if (Hive.isBoxOpen('batch_timestamps')) {
        _timestampBox = Hive.box<int>('batch_timestamps');
      } else {
        _timestampBox = await Hive.openBox<int>('batch_timestamps');
      }
      
      _lastSyncTime = _getSavedSyncTime();
      _isInitialized = true;
      
      // Start listening to box changes for reactive streams
      _batchBox.listenable().addListener(_onBatchBoxChanged);
      
      // Start background sync if enabled
      if (_config.autoSync) {
        _startBackgroundSync();
      }
      log('BatchRepository initialized successfully', name: 'BatchRepository');
      
      return const Success(null);
    } catch (e, stackTrace) {
      log('Failed to initialize BatchRepository: $e', 
          error: e, stackTrace: stackTrace, name: 'BatchRepository');
      return Failure(RepositoryException('Failed to initialize repository', cause: e as Exception?));
    }
  }
  
  void _onBatchBoxChanged() {
    _emitAllBatches();
  }
  
  void _emitAllBatches() async {
    try {
      if (!_batchBox.isOpen) {
        log('Batch box is closed, cannot emit batches', name: 'BatchRepository');
        return;
      }
      
      final batches = _batchBox.values.toList();
      _batchesController.add(Success(batches));
      
      // Update individual batch streams
      for (final entry in _singleBatchControllers.entries) {
        final batch = _batchBox.get(entry.key);
        entry.value.add(Success(batch));
      }
    } catch (e) {
      _batchesController.add(Failure(Exception('Failed to emit batches: $e')));
    }
  }

  @override
  Stream<Result<List<BatchModel>, Exception>> watchAll() {
    _ensureInitialized();
    
    // Emit current state immediately
    _emitAllBatches();
    
    return _batchesController.stream;
  }

  @override
  Stream<Result<BatchModel?, Exception>> watchById(String id) {
    _ensureInitialized();
    
    if (!_singleBatchControllers.containsKey(id)) {
      _singleBatchControllers[id] = StreamController<Result<BatchModel?, Exception>>.broadcast();
    }
    
    // Emit current state immediately
    final batch = _batchBox.get(id);
    _singleBatchControllers[id]!.add(Success(batch));
    
    return _singleBatchControllers[id]!.stream;
  }

  @override
  Future<Result<List<BatchModel>, Exception>> getAll() async {
    try {
      _ensureInitialized();
      
      final batches = _batchBox.values.toList();
      
      return Success(batches);
    } catch (e) {
      return Failure(Exception('Failed to get all batches: $e'));
    }
  }

  @override
  Future<Result<BatchModel?, Exception>> getById(String id) async {
    try {
      _ensureInitialized();
      
      final batch = _batchBox.get(id);
      
      return Success(batch);
    } catch (e) {
      return Failure(Exception('Failed to get batch $id: $e'));
    }
  }

  @override
  Future<Result<BatchModel, Exception>> save(BatchModel entity) async {
    try {
      _ensureInitialized();
      
      // Save locally first (offline-first approach)
      await _batchBox.put(entity.id, entity);
      
      // Mark for sync
      await _markForSync(entity.id, 'update');
      
      // Attempt immediate sync if online
      if (_config.autoSync && _authService.currentUser != null) {
        _syncSingle(entity.id).ignore(); // Fire and forget
      }
      log('Batch ${entity.id} saved successfully', name: 'BatchRepository');
      
      return Success(entity);
    } catch (e) {
      log('Failed to save batch ${entity.id}: $e', error: e, name: 'BatchRepository');
      return Failure(Exception('Failed to save batch: $e'));
    }
  }

  @override
  Future<Result<List<BatchModel>, Exception>> saveAll(List<BatchModel> entities) async {
    try {
      _ensureInitialized();
      
      // Save all locally first
      final Map<String, BatchModel> batchMap = {
        for (final batch in entities) batch.id: batch
      };
      
      await _batchBox.putAll(batchMap);
      
      // Mark all for sync
      for (final batch in entities) {
        await _markForSync(batch.id, 'update');
      }
      
      // Attempt sync if online
      if (_config.autoSync && _authService.currentUser != null) {
        sync().ignore(); // Fire and forget
      }
      log('${entities.length} batches saved successfully', name: 'BatchRepository');
      
      return Success(entities);
    } catch (e) {
      log('Failed to save batches: $e', error: e, name: 'BatchRepository');
      return Failure(Exception('Failed to save batches: $e'));
    }
  }

  @override
  Future<Result<void, Exception>> delete(String id) async {
    try {
      _ensureInitialized();
      
      // Delete locally first
      await _batchBox.delete(id);
      
      // Mark for sync
      await _markForSync(id, 'delete');
      
      // Attempt immediate sync if online
      if (_config.autoSync && _authService.currentUser != null) {
        _syncSingle(id).ignore(); // Fire and forget
      }
      log('Batch $id deleted successfully', name: 'BatchRepository');
      
      return const Success(null);
    } catch (e) {
      log('Failed to delete batch $id: $e', error: e, name: 'BatchRepository');
      return Failure(Exception('Failed to delete batch: $e'));
    }
  }

  @override
  Future<Result<void, Exception>> deleteAll(List<String> ids) async {
    try {
      _ensureInitialized();
      
      // Delete all locally first
      for (final id in ids) {
        await _batchBox.delete(id);
        await _markForSync(id, 'delete');
      }
      
      // Attempt sync if online
      if (_config.autoSync && _authService.currentUser != null) {
        sync().ignore(); // Fire and forget
      }
      log('${ids.length} batches deleted successfully', name: 'BatchRepository');
      
      return const Success(null);
    } catch (e) {
      log('Failed to delete batches: $e', error: e, name: 'BatchRepository');
      return Failure(Exception('Failed to delete batches: $e'));
    }
  }

  @override
  Future<Result<bool, Exception>> exists(String id) async {
    try {
      _ensureInitialized();
      
      final exists = _batchBox.containsKey(id);
      return Success(exists);
    } catch (e) {
      return Failure(Exception('Failed to check batch existence: $e'));
    }
  }

  @override
  Future<Result<bool, Exception>> sync() async {
    if (_isSyncing || _authService.currentUser == null) {
      return const Success(false);
    }
    
    try {
      _isSyncing = true;
      _syncStatusController.add(true);
      
      // Get pending sync operations
      final pendingSync = _syncBox.keys.toList();
      bool hasErrors = false;
      
      for (final id in pendingSync) {
        final result = await _syncSingle(id);
        if (result.isFailure) {
          hasErrors = true;
          log('Failed to sync batch $id: ${result.error}', name: 'BatchRepository');
        }
      }
      
      // Pull latest from server
      await _pullFromServer();
      
      _lastSyncTime = DateTime.now();
      await _saveSyncTime(_lastSyncTime!);
      
      return Success(!hasErrors);
    } catch (e) {
      log('Sync failed: $e', error: e, name: 'BatchRepository');
      return Failure(Exception('Sync failed: $e'));
    } finally {
      _isSyncing = false;
      _syncStatusController.add(false);
    }
  }

  @override
  Future<Result<void, Exception>> clearCache() async {
    try {
      _ensureInitialized();
      
      await _batchBox.clear();
      await _syncBox.clear();
      _lastSyncTime = null;
      log('Cache cleared successfully', name: 'BatchRepository');
      
      return const Success(null);
    } catch (e) {
      log('Failed to clear cache: $e', error: e, name: 'BatchRepository');
      return Failure(Exception('Failed to clear cache: $e'));
    }
  }

  @override
  DateTime? getLastSyncTime() => _lastSyncTime;

  @override
  bool get isSyncing => _isSyncing;

  @override
  Stream<bool> get syncStatusStream => _syncStatusController.stream;

  // Private helper methods
  
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('Repository not initialized. Call initialize() first.');
    }
  }
  
  Future<void> _markForSync(String id, String operation) async {
    await _syncBox.put(id, {
      'operation': operation,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  
  Future<Result<void, Exception>> _syncSingle(String id) async {
    try {
      final syncData = _syncBox.get(id);
      if (syncData == null) return const Success(null);
      
      final operation = syncData['operation'] as String;
      
      if (operation == 'delete') {
        await _deleteOnServer(id);
      } else {
        final batch = _batchBox.get(id);
        if (batch != null) {
          await _saveToServer(batch);
        }
      }
      
      // Remove from sync queue on success
      await _syncBox.delete(id);
      
      return const Success(null);
    } catch (e) {
      return Failure(Exception('Failed to sync batch $id: $e'));
    }
  }
  
  Future<void> _saveToServer(BatchModel batch) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) throw Exception('User not authenticated');
    
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('batches')
        .doc(batch.id)
        .set(batch.toJson());
  }
  
  Future<void> _deleteOnServer(String id) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) throw Exception('User not authenticated');
    
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('batches')
        .doc(id)
        .delete();
  }
  
  Future<void> _pullFromServer() async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) return;
    
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('batches')
        .get();
    
    final Map<String, BatchModel> serverBatches = {};
    
    for (final doc in snapshot.docs) {
      try {
        final batch = BatchModel.fromJson(doc.data());
        serverBatches[doc.id] = batch;
      } catch (e) {
        log('Failed to parse batch ${doc.id}: $e', name: 'BatchRepository');
      }
    }
    
    if (serverBatches.isNotEmpty) {
      await _batchBox.putAll(serverBatches);
    }
  }
  
  void _startBackgroundSync() {
    Timer.periodic(_config.syncInterval, (timer) {
      if (_authService.currentUser != null && !_isSyncing) {
        sync().ignore();
      }
    });
  }
  
  DateTime? _getSavedSyncTime() {
    final timestamp = _timestampBox.get('_last_sync_time');
    return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
  }
  
  Future<void> _saveSyncTime(DateTime time) async {
    await _timestampBox.put('_last_sync_time', time.millisecondsSinceEpoch);
  }
  
  /// Dispose resources
  void dispose() {
    _syncStatusController.close();
    _batchesController.close();
    for (final controller in _singleBatchControllers.values) {
      controller.close();
    }
    _singleBatchControllers.clear();
  }
}