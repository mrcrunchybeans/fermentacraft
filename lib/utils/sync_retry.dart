/// Retry utility for handling transient failures in sync operations
/// with exponential backoff and circuit breaker pattern.
library;

import 'dart:async';
import 'dart:math';
import '../utils/app_logger.dart';
import '../utils/result.dart';

/// Configuration for retry behavior
class RetryConfig {
  const RetryConfig({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.1,
    this.retryableExceptions = const [],
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final double backoffMultiplier;
  final double jitterFactor; // 0.0 to 1.0
  final List<Type> retryableExceptions;

  /// Config for Hive operations (local storage)
  static const hive = RetryConfig(
    maxAttempts: 3,
    baseDelay: Duration(milliseconds: 100),
    maxDelay: Duration(seconds: 5),
    backoffMultiplier: 1.5,
  );

  /// Config for Firestore operations (network)
  static const firestore = RetryConfig(
    maxAttempts: 5,
    baseDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 30),
    backoffMultiplier: 2.0,
    jitterFactor: 0.2,
  );

  /// Config for critical operations that must not fail
  static const critical = RetryConfig(
    maxAttempts: 10,
    baseDelay: Duration(milliseconds: 200),
    maxDelay: Duration(minutes: 2),
    backoffMultiplier: 1.8,
    jitterFactor: 0.15,
  );
}

/// Result of a retry operation
class RetryResult<T> {
  const RetryResult._({
    required this.success,
    this.result,
    this.error,
    required this.attempts,
    required this.totalDuration,
  });

  final bool success;
  final T? result;
  final Object? error;
  final int attempts;
  final Duration totalDuration;

  factory RetryResult.success(T result, int attempts, Duration duration) =>
      RetryResult._(
        success: true,
        result: result,
        attempts: attempts,
        totalDuration: duration,
      );

  factory RetryResult.failure(Object error, int attempts, Duration duration) =>
      RetryResult._(
        success: false,
        error: error,
        attempts: attempts,
        totalDuration: duration,
      );
}

/// Circuit breaker states
enum CircuitState { closed, open, halfOpen }

/// Circuit breaker to prevent cascading failures
class CircuitBreaker {
  CircuitBreaker({
    this.failureThreshold = 5,
    this.recoveryTimeout = const Duration(minutes: 1),
    this.successThreshold = 3,
  });

  final int failureThreshold;
  final Duration recoveryTimeout;
  final int successThreshold;

  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  int _successCount = 0;
  DateTime? _lastFailureTime;

  CircuitState get state => _state;

  bool get isOpen => _state == CircuitState.open;
  bool get isClosed => _state == CircuitState.closed;
  bool get isHalfOpen => _state == CircuitState.halfOpen;

  /// Check if operation should be allowed
  bool canExecute() {
    switch (_state) {
      case CircuitState.closed:
        return true;
      case CircuitState.open:
        if (_lastFailureTime != null &&
            DateTime.now().difference(_lastFailureTime!) > recoveryTimeout) {
          _state = CircuitState.halfOpen;
          _successCount = 0;
          return true;
        }
        return false;
      case CircuitState.halfOpen:
        return true;
    }
  }

  /// Record successful operation
  void recordSuccess() {
    _failureCount = 0;
    if (_state == CircuitState.halfOpen) {
      _successCount++;
      if (_successCount >= successThreshold) {
        _state = CircuitState.closed;
      }
    }
  }

  /// Record failed operation
  void recordFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    
    if (_state == CircuitState.halfOpen) {
      _state = CircuitState.open;
    } else if (_failureCount >= failureThreshold) {
      _state = CircuitState.open;
    }
  }

  void reset() {
    _state = CircuitState.closed;
    _failureCount = 0;
    _successCount = 0;
    _lastFailureTime = null;
  }
}

/// Enhanced retry utility with circuit breaker pattern
class SyncRetryManager {
  SyncRetryManager._();
  static final SyncRetryManager instance = SyncRetryManager._();

  final Map<String, CircuitBreaker> _circuitBreakers = {};
  final Random _random = Random();

  /// Get or create circuit breaker for an operation
  CircuitBreaker _getCircuitBreaker(String operationKey) {
    return _circuitBreakers.putIfAbsent(
      operationKey,
      () => CircuitBreaker(),
    );
  }

  /// Calculate delay with exponential backoff and jitter
  Duration _calculateDelay(RetryConfig config, int attempt) {
    final baseDelayMs = config.baseDelay.inMilliseconds;
    final exponentialDelay = (baseDelayMs * pow(config.backoffMultiplier, attempt)).round();
    
    // Add jitter to prevent thundering herd
    final jitter = (exponentialDelay * config.jitterFactor * _random.nextDouble()).round();
    final totalDelay = exponentialDelay + jitter;
    
    // Cap at max delay
    final cappedDelay = min(totalDelay, config.maxDelay.inMilliseconds);
    return Duration(milliseconds: cappedDelay);
  }

  /// Check if exception is retryable
  bool _isRetryableError(Object error, RetryConfig config) {
    // If specific exceptions are configured, check those
    if (config.retryableExceptions.isNotEmpty) {
      return config.retryableExceptions.contains(error.runtimeType);
    }

    // Default retryable errors
    final errorString = error.toString().toLowerCase();
    return errorString.contains('network') ||
           errorString.contains('timeout') ||
           errorString.contains('connection') ||
           errorString.contains('unavailable') ||
           errorString.contains('deadline') ||
           errorString.contains('cancelled') ||
           // Hive specific
           errorString.contains('hive') ||
           errorString.contains('io') ||
           errorString.contains('file');
  }

  /// Execute operation with retry logic and circuit breaker
  Future<AppResult<T>> executeWithRetry<T>({
    required Future<T> Function() operation,
    required String operationKey,
    RetryConfig config = const RetryConfig(),
    LogCategory logCategory = LogCategory.sync,
    String? userId,
    Map<String, dynamic>? context,
  }) async {
    final circuitBreaker = _getCircuitBreaker(operationKey);
    final stopwatch = Stopwatch()..start();
    
    // Check circuit breaker
    if (!circuitBreaker.canExecute()) {
      return Failure(AppError.sync(
        'Circuit breaker is open for operation: $operationKey',
        details: 'Operation blocked due to repeated failures',
      ));
    }

    Object? lastError;
    
    for (int attempt = 0; attempt < config.maxAttempts; attempt++) {
      try {
        appLogger.debug(
          'Executing operation attempt ${attempt + 1}/${config.maxAttempts}',
          category: logCategory,
          operation: operationKey,
          details: {
            'attempt': attempt + 1,
            'max_attempts': config.maxAttempts,
            if (context != null) ...context,
          },
          userId: userId,
        );

        final result = await operation();
        
        // Success!
        circuitBreaker.recordSuccess();
        stopwatch.stop();
        
        if (attempt > 0) {
          appLogger.info(
            'Operation succeeded after retry',
            category: logCategory,
            operation: operationKey,
            details: {
              'attempts': attempt + 1,
              'duration_ms': stopwatch.elapsedMilliseconds,
              if (context != null) ...context,
            },
            userId: userId,
          );
        }
        
        return Success(result);
        
      } catch (error) {
        lastError = error;
        
        // Check if we should retry
        if (!_isRetryableError(error, config)) {
          appLogger.error(
            'Non-retryable error in operation',
            category: logCategory,
            operation: operationKey,
            error: error,
            details: {
              'attempt': attempt + 1,
              'non_retryable': true,
              if (context != null) ...context,
            },
            userId: userId,
          );
          break;
        }

        // Log retry attempt
        appLogger.warning(
          'Operation failed, will retry',
          category: logCategory,
          operation: operationKey,
          error: error,
          details: {
            'attempt': attempt + 1,
            'remaining_attempts': config.maxAttempts - attempt - 1,
            if (context != null) ...context,
          },
          userId: userId,
        );

        // Don't delay on the last attempt
        if (attempt < config.maxAttempts - 1) {
          final delay = _calculateDelay(config, attempt);
          await Future.delayed(delay);
        }
      }
    }

    // All attempts failed
    circuitBreaker.recordFailure();
    stopwatch.stop();
    
    appLogger.error(
      'Operation failed after all retry attempts',
      category: logCategory,
      operation: operationKey,
      error: lastError,
      details: {
        'total_attempts': config.maxAttempts,
        'total_duration_ms': stopwatch.elapsedMilliseconds,
        'circuit_breaker_state': circuitBreaker.state.name,
        if (context != null) ...context,
      },
      userId: userId,
    );

    return Failure(AppError.sync(
      'Operation failed after ${config.maxAttempts} attempts: $operationKey',
      details: lastError?.toString(),
    ));
  }

  /// Retry specifically for Hive operations
  Future<AppResult<T>> retryHiveOperation<T>({
    required Future<T> Function() operation,
    required String operationKey,
    String? userId,
    Map<String, dynamic>? context,
  }) {
    return executeWithRetry<T>(
      operation: operation,
      operationKey: 'hive_$operationKey',
      config: RetryConfig.hive,
      logCategory: LogCategory.storage,
      userId: userId,
      context: context,
    );
  }

  /// Retry specifically for Firestore operations
  Future<AppResult<T>> retryFirestoreOperation<T>({
    required Future<T> Function() operation,
    required String operationKey,
    String? userId,
    Map<String, dynamic>? context,
  }) {
    return executeWithRetry<T>(
      operation: operation,
      operationKey: 'firestore_$operationKey',
      config: RetryConfig.firestore,
      logCategory: LogCategory.network,
      userId: userId,
      context: context,
    );
  }

  /// Retry for critical operations that must succeed
  Future<AppResult<T>> retryCriticalOperation<T>({
    required Future<T> Function() operation,
    required String operationKey,
    String? userId,
    Map<String, dynamic>? context,
  }) {
    return executeWithRetry<T>(
      operation: operation,
      operationKey: 'critical_$operationKey',
      config: RetryConfig.critical,
      logCategory: LogCategory.sync,
      userId: userId,
      context: context,
    );
  }

  /// Reset circuit breaker for an operation
  void resetCircuitBreaker(String operationKey) {
    _circuitBreakers[operationKey]?.reset();
  }

  /// Get circuit breaker status
  CircuitState getCircuitBreakerState(String operationKey) {
    return _circuitBreakers[operationKey]?.state ?? CircuitState.closed;
  }

  /// Clear all circuit breakers (useful for testing or recovery)
  void clearAllCircuitBreakers() {
    _circuitBreakers.clear();
  }

  /// Check if an operation is healthy (circuit breaker not open)
  bool isOperationHealthy(String operationKey) {
    final circuitBreaker = _circuitBreakers[operationKey];
    return circuitBreaker?.isOpen != true;
  }

  /// Get status of all circuit breakers for debugging
  Map<String, Map<String, dynamic>> getCircuitBreakerStatus() {
    final status = <String, Map<String, dynamic>>{};
    for (final entry in _circuitBreakers.entries) {
      final cb = entry.value;
      status[entry.key] = {
        'state': cb.isOpen ? 'OPEN' : (cb.isHalfOpen ? 'HALF_OPEN' : 'CLOSED'),
        'can_execute': cb.canExecute(),
        'failure_threshold': cb.failureThreshold,
        'recovery_timeout_seconds': cb.recoveryTimeout.inSeconds,
      };
    }
    return status;
  }
}

/// Convenience instance
final syncRetry = SyncRetryManager.instance;