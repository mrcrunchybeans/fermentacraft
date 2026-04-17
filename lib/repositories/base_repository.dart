import 'package:fermentacraft/utils/result.dart';

/// Abstract base repository defining common CRUD operations for all data entities
/// Provides consistent interface with Result<T, Exception> error handling and reactive streams
abstract class BaseRepository<T> {
  /// Get all entities as a reactive stream for UI updates
  Stream<Result<List<T>, Exception>> watchAll();
  
  /// Get a single entity by ID as a reactive stream
  Stream<Result<T?, Exception>> watchById(String id);
  
  /// Get all entities as a one-time fetch
  Future<Result<List<T>, Exception>> getAll();
  
  /// Get a single entity by ID
  Future<Result<T?, Exception>> getById(String id);
  
  /// Save an entity (create or update)
  /// Returns the saved entity with any server-generated fields
  Future<Result<T, Exception>> save(T entity);
  
  /// Save multiple entities in a batch operation
  Future<Result<List<T>, Exception>> saveAll(List<T> entities);
  
  /// Delete an entity by ID
  Future<Result<void, Exception>> delete(String id);
  
  /// Delete multiple entities by IDs
  Future<Result<void, Exception>> deleteAll(List<String> ids);
  
  /// Check if an entity exists locally
  Future<Result<bool, Exception>> exists(String id);
  
  /// Force sync with remote data source
  /// Returns true if sync was successful
  Future<Result<bool, Exception>> sync();
  
  /// Clear local cache and force fresh data from remote
  Future<Result<void, Exception>> clearCache();
  
  /// Get last sync timestamp for this repository
  DateTime? getLastSyncTime();
  
  /// Check if repository is currently syncing
  bool get isSyncing;
  
  /// Stream of sync status changes
  Stream<bool> get syncStatusStream;
}

/// Exception thrown when repository operations fail
class RepositoryException implements Exception {
  final String message;
  final String? code;
  final Exception? cause;
  
  const RepositoryException(
    this.message, {
    this.code,
    this.cause,
  });
  
  @override
  String toString() => 'RepositoryException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Common repository configuration and settings
class RepositoryConfig {
  /// Maximum number of retries for failed operations
  final int maxRetries;
  
  /// Timeout for network operations
  final Duration networkTimeout;
  
  /// Whether to enable local caching
  final bool enableCache;
  
  /// Cache expiration time
  final Duration cacheExpiration;
  
  /// Whether to sync automatically in background
  final bool autoSync;
  
  /// Interval for background sync
  final Duration syncInterval;
  
  const RepositoryConfig({
    this.maxRetries = 3,
    this.networkTimeout = const Duration(seconds: 30),
    this.enableCache = true,
    this.cacheExpiration = const Duration(hours: 1),
    this.autoSync = true,
    this.syncInterval = const Duration(minutes: 15),
  });
}