/// Enhanced logging system for FermentaCraft with structured logging,
/// error categorization, and proper log levels.

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../utils/result.dart';

/// Log levels for the application
enum LogLevel {
  debug(0),
  info(1), 
  warning(2),
  error(3),
  fatal(4);

  const LogLevel(this.priority);
  final int priority;
}

/// Categories for structured logging
enum LogCategory {
  sync,
  premium,
  auth,
  network,
  storage,
  ui,
  performance,
  general,
}

/// Structured log entry
class LogEntry {
  const LogEntry({
    required this.level,
    required this.category,
    required this.message,
    this.details,
    this.error,
    this.stackTrace,
    this.userId,
    this.operation,
    this.timestamp,
  });

  final LogLevel level;
  final LogCategory category;
  final String message;
  final Map<String, dynamic>? details;
  final Object? error;
  final StackTrace? stackTrace;
  final String? userId;
  final String? operation;
  final DateTime? timestamp;

  /// Convert to JSON for structured logging
  Map<String, dynamic> toJson() {
    return {
      'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
      'level': level.name,
      'category': category.name,
      'message': message,
      if (details != null) 'details': details,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      if (userId != null) 'userId': userId,
      if (operation != null) 'operation': operation,
    };
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('[${level.name.toUpperCase()}]');
    buffer.write('[${category.name.toUpperCase()}]');
    if (operation != null) buffer.write('[$operation]');
    buffer.write(' $message');
    
    if (details != null && details!.isNotEmpty) {
      buffer.write(' | Details: ${details.toString()}');
    }
    
    if (error != null) {
      buffer.write(' | Error: $error');
    }
    
    return buffer.toString();
  }
}

/// Enhanced logging service with structured logging and categorization
class AppLogger {
  AppLogger._({
    Logger? logger,
    this.minLevel = LogLevel.info,
  }) : _logger = logger ?? Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      printTime: false,
    ),
  );

  static AppLogger? _instance;
  static AppLogger get instance => _instance ??= AppLogger._();

  /// Initialize with custom settings
  static void initialize({
    LogLevel? minLevel,
    Logger? customLogger,
  }) {
    _instance = AppLogger._(
      logger: customLogger,
      minLevel: minLevel ?? (kDebugMode ? LogLevel.debug : LogLevel.info),
    );
  }

  final Logger _logger;
  final LogLevel minLevel;

  /// Log with full structured entry
  void log(LogEntry entry) {
    if (entry.level.priority < minLevel.priority) return;

    // Use appropriate logger level
    switch (entry.level) {
      case LogLevel.debug:
        _logger.d(entry.toString());
      case LogLevel.info:
        _logger.i(entry.toString());
      case LogLevel.warning:
        _logger.w(entry.toString());
      case LogLevel.error:
        _logger.e(entry.toString(), error: entry.error, stackTrace: entry.stackTrace);
      case LogLevel.fatal:
        _logger.f(entry.toString(), error: entry.error, stackTrace: entry.stackTrace);
    }
  }

  /// Debug level logging
  void debug(
    String message, {
    LogCategory category = LogCategory.general,
    Map<String, dynamic>? details,
    String? operation,
    String? userId,
  }) {
    log(LogEntry(
      level: LogLevel.debug,
      category: category,
      message: message,
      details: details,
      operation: operation,
      userId: userId,
    ));
  }

  /// Info level logging
  void info(
    String message, {
    LogCategory category = LogCategory.general,
    Map<String, dynamic>? details,
    String? operation,
    String? userId,
  }) {
    log(LogEntry(
      level: LogLevel.info,
      category: category,
      message: message,
      details: details,
      operation: operation,
      userId: userId,
    ));
  }

  /// Warning level logging
  void warning(
    String message, {
    LogCategory category = LogCategory.general,
    Map<String, dynamic>? details,
    Object? error,
    String? operation,
    String? userId,
  }) {
    log(LogEntry(
      level: LogLevel.warning,
      category: category,
      message: message,
      details: details,
      error: error,
      operation: operation,
      userId: userId,
    ));
  }

  /// Error level logging
  void error(
    String message, {
    LogCategory category = LogCategory.general,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? details,
    String? operation,
    String? userId,
  }) {
    log(LogEntry(
      level: LogLevel.error,
      category: category,
      message: message,
      error: error,
      stackTrace: stackTrace,
      details: details,
      operation: operation,
      userId: userId,
    ));
  }

  /// Fatal error logging
  void fatal(
    String message, {
    LogCategory category = LogCategory.general,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? details,
    String? operation,
    String? userId,
  }) {
    log(LogEntry(
      level: LogLevel.fatal,
      category: category,
      message: message,
      error: error,
      stackTrace: stackTrace,
      details: details,
      operation: operation,
      userId: userId,
    ));
  }
}

/// Specialized loggers for different service categories
class SyncLogger {
  static final _logger = AppLogger.instance;

  static void starting({String? userId, String? operation}) {
    _logger.info(
      'Sync starting',
      category: LogCategory.sync,
      userId: userId,
      operation: operation,
    );
  }

  static void stopping({String? userId, String? reason}) {
    _logger.info(
      'Sync stopping',
      category: LogCategory.sync,
      details: reason != null ? {'reason': reason} : null,
      userId: userId,
    );
  }

  static void authStateChange({
    String? oldUid,
    String? newUid,
    bool? emailVerified,
    bool? isAnonymous,
  }) {
    _logger.info(
      'Auth state change',
      category: LogCategory.sync,
      operation: 'auth_change',
      details: {
        'old_uid': oldUid,
        'new_uid': newUid,
        'email_verified': emailVerified,
        'is_anonymous': isAnonymous,
      },
    );
  }

  static void docSync({
    required String collection,
    required String docId,
    required String direction, // 'local_to_remote' or 'remote_to_local'
    String? userId,
    bool? success,
    Object? error,
  }) {
    if (success == true) {
      _logger.debug(
        'Document synced',
        category: LogCategory.sync,
        operation: 'doc_sync',
        details: {
          'collection': collection,
          'doc_id': docId,
          'direction': direction,
        },
        userId: userId,
      );
    } else if (error != null) {
      _logger.error(
        'Document sync failed',
        category: LogCategory.sync,
        operation: 'doc_sync',
        error: error,
        details: {
          'collection': collection,
          'doc_id': docId,
          'direction': direction,
        },
        userId: userId,
      );
    }
  }

  static void connectivityChange({
    required String status,
    String? userId,
  }) {
    _logger.info(
      'Connectivity changed',
      category: LogCategory.sync,
      operation: 'connectivity',
      details: {'status': status},
      userId: userId,
    );
  }

  static void syncError({
    required String operation,
    required Object error,
    StackTrace? stackTrace,
    String? userId,
    Map<String, dynamic>? context,
  }) {
    _logger.error(
      'Sync operation failed',
      category: LogCategory.sync,
      operation: operation,
      error: error,
      stackTrace: stackTrace,
      details: context,
      userId: userId,
    );
  }
}

class PremiumLogger {
  static final _logger = AppLogger.instance;

  static void subscriptionCheck({
    required String userId,
    required bool isPremium,
    String? productId,
    DateTime? expiryDate,
  }) {
    _logger.info(
      'Premium subscription checked',
      category: LogCategory.premium,
      operation: 'subscription_check',
      details: {
        'is_premium': isPremium,
        'product_id': productId,
        'expiry_date': expiryDate?.toIso8601String(),
      },
      userId: userId,
    );
  }

  static void purchaseAttempt({
    required String userId,
    required String productId,
    String? operation,
  }) {
    _logger.info(
      'Purchase attempt started',
      category: LogCategory.premium,
      operation: operation ?? 'purchase_attempt',
      details: {'product_id': productId},
      userId: userId,
    );
  }

  static void purchaseResult({
    required String userId,
    required String productId,
    required bool success,
    Object? error,
    String? transactionId,
  }) {
    if (success) {
      _logger.info(
        'Purchase completed successfully',
        category: LogCategory.premium,
        operation: 'purchase_success',
        details: {
          'product_id': productId,
          'transaction_id': transactionId,
        },
        userId: userId,
      );
    } else {
      _logger.error(
        'Purchase failed',
        category: LogCategory.premium,
        operation: 'purchase_failed',
        error: error,
        details: {'product_id': productId},
        userId: userId,
      );
    }
  }

  static void featureGateCheck({
    required String userId,
    required String feature,
    required bool allowed,
    String? reason,
  }) {
    _logger.debug(
      'Feature gate check',
      category: LogCategory.premium,
      operation: 'feature_gate',
      details: {
        'feature': feature,
        'allowed': allowed,
        'reason': reason,
      },
      userId: userId,
    );
  }
}

class AuthLogger {
  static final _logger = AppLogger.instance;

  static void signInAttempt({required String method}) {
    _logger.info(
      'Sign in attempt',
      category: LogCategory.auth,
      operation: 'sign_in_attempt',
      details: {'method': method},
    );
  }

  static void signInResult({
    required String method,
    required bool success,
    String? userId,
    Object? error,
  }) {
    if (success) {
      _logger.info(
        'Sign in successful',
        category: LogCategory.auth,
        operation: 'sign_in_success',
        details: {'method': method},
        userId: userId,
      );
    } else {
      _logger.error(
        'Sign in failed',
        category: LogCategory.auth,
        operation: 'sign_in_failed',
        error: error,
        details: {'method': method},
      );
    }
  }

  static void signOut({String? userId}) {
    _logger.info(
      'User signed out',
      category: LogCategory.auth,
      operation: 'sign_out',
      userId: userId,
    );
  }
}

/// Extension methods for logging AppResult operations
extension AppResultLogging<T> on AppResult<T> {
  /// Log the result of an operation
  AppResult<T> logResult({
    required String operation,
    LogCategory category = LogCategory.general,
    String? userId,
    Map<String, dynamic>? context,
  }) {
    switch (this) {
      case Success():
        AppLogger.instance.debug(
          'Operation completed successfully',
          category: category,
          operation: operation,
          details: {
            'success': true,
            if (context != null) ...context,
          },
          userId: userId,
        );
      case Failure(error: final AppError error):
        AppLogger.instance.error(
          'Operation failed',
          category: category,
          operation: operation,
          error: error,
          details: {
            'error_type': error.type.name,
            'error_code': error.code,
            if (context != null) ...context,
          },
          userId: userId,
        );
    }
    return this;
  }
}

/// Convenience logger instances
final appLogger = AppLogger.instance;
final syncLogger = SyncLogger();
final premiumLogger = PremiumLogger();
final authLogger = AuthLogger();