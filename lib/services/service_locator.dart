import 'package:get_it/get_it.dart';
import 'package:fermentacraft/repositories/repositories.dart';
import 'package:fermentacraft/services/auth_service.dart';
import 'package:fermentacraft/services/sync_coordinator.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/services/presets_service.dart';
import 'package:fermentacraft/services/memory_optimization_service.dart';
import 'package:fermentacraft/state/state.dart';
import 'package:fermentacraft/models/settings_model.dart';
import 'package:fermentacraft/models/tag_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fermentacraft/utils/boxes.dart';

/// Centralized service locator for dependency injection
/// Provides clean separation between services and UI layers
class ServiceLocator {
  static final _getIt = GetIt.instance;
  static bool _isInitialized = false;
  
  /// Get a service instance
  static T get<T extends Object>() => _getIt.get<T>();
  
  /// Check if a service is registered
  static bool isRegistered<T extends Object>() => _getIt.isRegistered<T>();
  
  /// Initialize all services in proper dependency order
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Core services (no dependencies)
    _registerSingletonService<AuthService>(() => AuthService.instance);
    _registerSingletonService<FeatureGate>(() => FeatureGate.instance);
    _registerSingletonService<MemoryOptimizationService>(() => MemoryOptimizationService.instance);
    
    // Data services
    await _registerPresetsService();
    await _registerSettingsModel();
    await _registerTagManager();
    
    // Repository layer (depends on core services)
    await _registerRepositories();
    
    // Coordination layer (depends on repositories)
    await _registerSyncCoordinator();
    
    // State management (depends on repositories)
    _registerStateClasses();
    
    _isInitialized = true;
  }
  
  /// Clean up services
  static Future<void> dispose() async {
    if (!_isInitialized) return;
    
    // Dispose in reverse order
    if (isRegistered<SyncCoordinator>()) {
      await get<SyncCoordinator>().dispose();
    }
    
    await _getIt.reset();
    _isInitialized = false;
  }
  
  /// Register a singleton service
  static void _registerSingletonService<T extends Object>(T Function() factory) {
    if (!_getIt.isRegistered<T>()) {
      _getIt.registerSingleton<T>(factory());
    }
  }
  
  /// Register a factory (new instance each time)
  static void _registerFactory<T extends Object>(T Function() factory) {
    if (!_getIt.isRegistered<T>()) {
      _getIt.registerFactory<T>(factory);
    }
  }
  
  /// Register presets service
  static Future<void> _registerPresetsService() async {
    final presets = PresetsService();
    await presets.ensureLoaded();
    _registerSingletonService<PresetsService>(() => presets);
  }
  
  /// Register settings model
  static Future<void> _registerSettingsModel() async {
    final settingsBox = Hive.box(Boxes.settings);
    _registerSingletonService<SettingsModel>(() => SettingsModel(settingsBox));
  }
  
  /// Register tag manager
  static Future<void> _registerTagManager() async {
    _registerSingletonService<TagManager>(() => TagManager());
  }
  
  /// Register repository layer
  static Future<void> _registerRepositories() async {
    // Register repositories
    final batchRepo = BatchRepository(authService: get<AuthService>());
    await batchRepo.initialize();
    _registerSingletonService<BatchRepository>(() => batchRepo);
    
    final recipeRepo = RecipeRepository(authService: get<AuthService>());
    await recipeRepo.initialize();
    _registerSingletonService<RecipeRepository>(() => recipeRepo);
  }
  
  /// Register sync coordinator
  static Future<void> _registerSyncCoordinator() async {
    final coordinator = SyncCoordinator.instance;
    await coordinator.initialize(
      batchRepository: get<BatchRepository>(),
      recipeRepository: get<RecipeRepository>(),
    );
    _registerSingletonService<SyncCoordinator>(() => coordinator);
  }
  
  /// Register state management classes as factories (new instance per page)
  static void _registerStateClasses() {
    _registerFactory<BatchDetailState>(() => BatchDetailState(
      batchRepository: get<BatchRepository>(),
    ));
    
    _registerFactory<RecipeBuilderState>(() => RecipeBuilderState(
      recipeRepository: get<RecipeRepository>(),
    ));
    
    _registerFactory<InventoryPageState>(() => InventoryPageState());
  }
}