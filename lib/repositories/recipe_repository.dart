import 'dart:async';
import 'dart:developer';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/repositories/base_repository.dart';
import 'package:fermentacraft/utils/result.dart';
import 'package:fermentacraft/services/auth_service.dart';

/// Repository for managing recipe data with local-first approach
/// Implements offline-first strategy with background synchronization
class RecipeRepository implements BaseRepository<RecipeModel> {
  static const String _boxName = 'recipes';
  static const String _syncBoxName = 'recipe_sync_metadata';
  
  late Box<RecipeModel> _recipeBox;
  late Box<Map<dynamic, dynamic>> _syncBox;
  late Box<int> _timestampBox;
  
  final AuthService _authService;
  final FirebaseFirestore _firestore;
  final RepositoryConfig _config;
  
  bool _isInitialized = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  
  final StreamController<bool> _syncStatusController = StreamController<bool>.broadcast();
  final StreamController<Result<List<RecipeModel>, Exception>> _recipesController = 
      StreamController<Result<List<RecipeModel>, Exception>>.broadcast();
  final Map<String, StreamController<Result<RecipeModel?, Exception>>> _singleRecipeControllers = {};
  
  RecipeRepository({
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
      if (Hive.isBoxOpen('recipe_timestamps')) {
        _timestampBox = Hive.box<int>('recipe_timestamps');
      } else {
        _timestampBox = await Hive.openBox<int>('recipe_timestamps');
      }
      
      if (Hive.isBoxOpen(_boxName)) {
        _recipeBox = Hive.box<RecipeModel>(_boxName);
      } else {
        _recipeBox = await Hive.openBox<RecipeModel>(_boxName);
      }
      
      if (Hive.isBoxOpen(_syncBoxName)) {
        _syncBox = Hive.box<Map<dynamic, dynamic>>(_syncBoxName);
      } else {
        _syncBox = await Hive.openBox<Map<dynamic, dynamic>>(_syncBoxName);
      }
      
      _lastSyncTime = _getSavedSyncTime();
      _isInitialized = true;
      
      // Start listening to box changes for reactive streams
      _recipeBox.listenable().addListener(_onRecipeBoxChanged);
      
      // Start background sync if enabled
      if (_config.autoSync) {
        _startBackgroundSync();
      }
      
      log('RecipeRepository initialized successfully', name: 'RecipeRepository');
      
      return const Success(null);
    } catch (e, stackTrace) {
      log('Failed to initialize RecipeRepository: $e', 
          error: e, stackTrace: stackTrace, name: 'RecipeRepository');
      return Failure(RepositoryException('Failed to initialize repository', cause: e as Exception?));
    }
  }
  
  void _onRecipeBoxChanged() {
    _emitAllRecipes();
  }
  
  void _emitAllRecipes() async {
    try {
      if (!_recipeBox.isOpen) {
        log('Recipe box is closed, cannot emit recipes', name: 'RecipeRepository');
        return;
      }
      
      final recipes = _recipeBox.values.toList();
      _recipesController.add(Success(recipes));
      
      // Update individual recipe streams
      for (final entry in _singleRecipeControllers.entries) {
        final recipe = _recipeBox.get(entry.key);
        entry.value.add(Success(recipe));
      }
    } catch (e) {
      _recipesController.add(Failure(Exception('Failed to emit recipes: $e')));
    }
  }

  @override
  Stream<Result<List<RecipeModel>, Exception>> watchAll() {
    _ensureInitialized();
    
    // Emit current state immediately
    _emitAllRecipes();
    
    return _recipesController.stream;
  }

  @override
  Stream<Result<RecipeModel?, Exception>> watchById(String id) {
    _ensureInitialized();
    
    if (!_singleRecipeControllers.containsKey(id)) {
      _singleRecipeControllers[id] = StreamController<Result<RecipeModel?, Exception>>.broadcast();
    }
    
    // Emit current state immediately
    final recipe = _recipeBox.get(id);
    _singleRecipeControllers[id]!.add(Success(recipe));
    
    return _singleRecipeControllers[id]!.stream;
  }

  @override
  Future<Result<List<RecipeModel>, Exception>> getAll() async {
    try {
      _ensureInitialized();
      
      final recipes = _recipeBox.values.toList();
      
      return Success(recipes);
    } catch (e) {
      return Failure(Exception('Failed to get all recipes: $e'));
    }
  }

  @override
  Future<Result<RecipeModel?, Exception>> getById(String id) async {
    try {
      _ensureInitialized();
      
      final recipe = _recipeBox.get(id);
      
      return Success(recipe);
    } catch (e) {
      return Failure(Exception('Failed to get recipe $id: $e'));
    }
  }

  @override
  Future<Result<RecipeModel, Exception>> save(RecipeModel entity) async {
    try {
      _ensureInitialized();
      
      // Save locally first (offline-first approach)
      await _recipeBox.put(entity.id, entity);
      
      // Mark for sync
      await _markForSync(entity.id, 'update');
      
      // Attempt immediate sync if online
      if (_config.autoSync && _authService.currentUser != null) {
        _syncSingle(entity.id).ignore(); // Fire and forget
      }
      
      log('Recipe ${entity.id} saved successfully', name: 'RecipeRepository');
      
      return Success(entity);
    } catch (e) {
      log('Failed to save recipe ${entity.id}: $e', error: e, name: 'RecipeRepository');
      return Failure(Exception('Failed to save recipe: $e'));
    }
  }

  @override
  Future<Result<List<RecipeModel>, Exception>> saveAll(List<RecipeModel> entities) async {
    try {
      _ensureInitialized();
      
      // Save all locally first
      final Map<String, RecipeModel> recipeMap = {
        for (final recipe in entities) recipe.id: recipe
      };
      
      await _recipeBox.putAll(recipeMap);
      
      // Mark all for sync
      for (final recipe in entities) {
        await _markForSync(recipe.id, 'update');
      }
      
      // Attempt sync if online
      if (_config.autoSync && _authService.currentUser != null) {
        sync().ignore(); // Fire and forget
      }
      
      log('${entities.length} recipes saved successfully', name: 'RecipeRepository');
      
      return Success(entities);
    } catch (e) {
      log('Failed to save recipes: $e', error: e, name: 'RecipeRepository');
      return Failure(Exception('Failed to save recipes: $e'));
    }
  }

  @override
  Future<Result<void, Exception>> delete(String id) async {
    try {
      _ensureInitialized();
      
      // Delete locally first
      await _recipeBox.delete(id);
      
      // Mark for sync
      await _markForSync(id, 'delete');
      
      // Attempt immediate sync if online
      if (_config.autoSync && _authService.currentUser != null) {
        _syncSingle(id).ignore(); // Fire and forget
      }
      
      log('Recipe $id deleted successfully', name: 'RecipeRepository');
      
      return const Success(null);
    } catch (e) {
      log('Failed to delete recipe $id: $e', error: e, name: 'RecipeRepository');
      return Failure(Exception('Failed to delete recipe: $e'));
    }
  }

  @override
  Future<Result<void, Exception>> deleteAll(List<String> ids) async {
    try {
      _ensureInitialized();
      
      // Delete all locally first
      for (final id in ids) {
        await _recipeBox.delete(id);
        await _markForSync(id, 'delete');
      }
      
      // Attempt sync if online
      if (_config.autoSync && _authService.currentUser != null) {
        sync().ignore(); // Fire and forget
      }
      
      log('${ids.length} recipes deleted successfully', name: 'RecipeRepository');
      
      return const Success(null);
    } catch (e) {
      log('Failed to delete recipes: $e', error: e, name: 'RecipeRepository');
      return Failure(Exception('Failed to delete recipes: $e'));
    }
  }

  @override
  Future<Result<bool, Exception>> exists(String id) async {
    try {
      _ensureInitialized();
      
      final exists = _recipeBox.containsKey(id);
      return Success(exists);
    } catch (e) {
      return Failure(Exception('Failed to check recipe existence: $e'));
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
          log('Failed to sync recipe $id: ${result.error}', name: 'RecipeRepository');
        }
      }
      
      // Pull latest from server
      await _pullFromServer();
      
      _lastSyncTime = DateTime.now();
      await _saveSyncTime(_lastSyncTime!);
      
      return Success(!hasErrors);
    } catch (e) {
      log('Sync failed: $e', error: e, name: 'RecipeRepository');
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
      
      await _recipeBox.clear();
      await _syncBox.clear();
      _lastSyncTime = null;
      
      log('Cache cleared successfully', name: 'RecipeRepository');
      
      return const Success(null);
    } catch (e) {
      log('Failed to clear cache: $e', error: e, name: 'RecipeRepository');
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
        final recipe = _recipeBox.get(id);
        if (recipe != null) {
          await _saveToServer(recipe);
        }
      }
      
      // Remove from sync queue on success
      await _syncBox.delete(id);
      
      return const Success(null);
    } catch (e) {
      return Failure(Exception('Failed to sync recipe $id: $e'));
    }
  }
  
  Future<void> _saveToServer(RecipeModel recipe) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) throw Exception('User not authenticated');
    
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('recipes')
        .doc(recipe.id)
        .set(recipe.toJson());
  }
  
  Future<void> _deleteOnServer(String id) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) throw Exception('User not authenticated');
    
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('recipes')
        .doc(id)
        .delete();
  }
  
  Future<void> _pullFromServer() async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) return;
    
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('recipes')
        .get();
    
    final Map<String, RecipeModel> serverRecipes = {};
    
    for (final doc in snapshot.docs) {
      try {
        final recipe = RecipeModel.fromJson(doc.data());
        serverRecipes[doc.id] = recipe;
      } catch (e) {
        log('Failed to parse recipe ${doc.id}: $e', name: 'RecipeRepository');
      }
    }
    
    if (serverRecipes.isNotEmpty) {
      await _recipeBox.putAll(serverRecipes);
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
    _recipesController.close();
    for (final controller in _singleRecipeControllers.values) {
      controller.close();
    }
    _singleRecipeControllers.clear();
  }
}