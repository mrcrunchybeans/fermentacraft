/// Centralized error handling system for sync operations
/// Provides user-visible feedback and recovery options for critical failures
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_logger.dart';
import 'sync_retry.dart';
import 'snacks.dart';

/// Categories of sync errors for different handling strategies
enum SyncErrorCategory {
  /// Network connectivity issues (temporary, usually recoverable)
  network,
  
  /// Authentication problems (requires re-login)
  authentication,
  
  /// Firestore permission or rule violations
  permissions,
  
  /// Local database corruption or I/O errors
  localStorage,
  
  /// Data corruption or validation failures
  dataIntegrity,
  
  /// Circuit breaker tripped - too many failures
  circuitBreaker,
  
  /// Unknown or unexpected errors
  unknown,
}

/// Severity levels for error handling
enum SyncErrorSeverity {
  /// Info level - operation succeeded after retry
  info,
  
  /// Warning level - operation had issues but completed
  warning,
  
  /// Error level - operation failed but not critical
  error,
  
  /// Critical level - data loss possible, immediate attention needed
  critical,
}

/// Represents a sync error with context and recovery options
class SyncError {
  const SyncError({
    required this.category,
    required this.severity,
    required this.operation,
    required this.error,
    required this.userMessage,
    required this.technicalMessage,
    this.context = const {},
    this.recoveryActions = const [],
  });

  final SyncErrorCategory category;
  final SyncErrorSeverity severity;
  final String operation;
  final Object error;
  final String userMessage;
  final String technicalMessage;
  final Map<String, dynamic> context;
  final List<SyncRecoveryAction> recoveryActions;

  /// Create error from exception with automatic categorization
  factory SyncError.fromException({
    required String operation,
    required Object error,
    String? userId,
    Map<String, dynamic> context = const {},
  }) {
    final category = _categorizeError(error);
    final severity = _determineSeverity(category, operation);
    final userMessage = _generateUserMessage(category, operation);
    final technicalMessage = error.toString();
    final recoveryActions = _generateRecoveryActions(category, operation);

    return SyncError(
      category: category,
      severity: severity,
      operation: operation,
      error: error,
      userMessage: userMessage,
      technicalMessage: technicalMessage,
      context: {
        ...context,
        if (userId != null) 'user_id': userId,
        'timestamp': DateTime.now().toIso8601String(),
      },
      recoveryActions: recoveryActions,
    );
  }

  /// Categorize error based on exception type and message
  static SyncErrorCategory _categorizeError(Object error) {
    final errorMessage = error.toString().toLowerCase();
    
    // Network related errors
    if (errorMessage.contains('socket') ||
        errorMessage.contains('network') ||
        errorMessage.contains('connection') ||
        errorMessage.contains('timeout') ||
        errorMessage.contains('unreachable')) {
      return SyncErrorCategory.network;
    }
    
    // Authentication errors
    if (errorMessage.contains('unauthenticated') ||
        errorMessage.contains('permission-denied') ||
        errorMessage.contains('invalid-token') ||
        errorMessage.contains('auth')) {
      return SyncErrorCategory.authentication;
    }
    
    // Firestore permission errors
    if (errorMessage.contains('permission') ||
        errorMessage.contains('security') ||
        errorMessage.contains('rules')) {
      return SyncErrorCategory.permissions;
    }
    
    // Local storage errors
    if (errorMessage.contains('hive') ||
        errorMessage.contains('database') ||
        errorMessage.contains('i/o') ||
        errorMessage.contains('storage')) {
      return SyncErrorCategory.localStorage;
    }
    
    // Circuit breaker
    if (errorMessage.contains('circuit') ||
        errorMessage.contains('breaker')) {
      return SyncErrorCategory.circuitBreaker;
    }
    
    return SyncErrorCategory.unknown;
  }

  /// Determine severity based on category and operation type
  static SyncErrorSeverity _determineSeverity(
    SyncErrorCategory category,
    String operation,
  ) {
    // Critical operations that could cause data loss
    if (operation.contains('delete') || 
        operation.contains('update') || 
        operation.contains('sync')) {
      return switch (category) {
        SyncErrorCategory.localStorage => SyncErrorSeverity.critical,
        SyncErrorCategory.dataIntegrity => SyncErrorSeverity.critical,
        SyncErrorCategory.network => SyncErrorSeverity.error,
        _ => SyncErrorSeverity.error,
      };
    }
    
    // Authentication always needs immediate attention
    if (category == SyncErrorCategory.authentication) {
      return SyncErrorSeverity.critical;
    }
    
    // Circuit breaker indicates systemic issues
    if (category == SyncErrorCategory.circuitBreaker) {
      return SyncErrorSeverity.error;
    }
    
    return SyncErrorSeverity.warning;
  }

  /// Generate user-friendly error messages
  static String _generateUserMessage(
    SyncErrorCategory category,
    String operation,
  ) {
    return switch (category) {
      SyncErrorCategory.network => 
        'Unable to sync your data due to network issues. Your changes are saved locally and will sync when connection improves.',
      
      SyncErrorCategory.authentication => 
        'Authentication expired. Please sign in again to continue syncing your data.',
      
      SyncErrorCategory.permissions => 
        'Unable to access cloud storage. This might be a temporary issue with the service.',
      
      SyncErrorCategory.localStorage => 
        'There was a problem with local data storage. Your data might need recovery.',
      
      SyncErrorCategory.dataIntegrity => 
        'Data validation failed during sync. Some entries may need manual review.',
      
      SyncErrorCategory.circuitBreaker => 
        'Sync is temporarily paused due to repeated failures. It will resume automatically.',
      
      SyncErrorCategory.unknown => 
        'An unexpected error occurred during sync. Your data is safe locally.',
    };
  }

  /// Generate appropriate recovery actions for each category
  static List<SyncRecoveryAction> _generateRecoveryActions(
    SyncErrorCategory category,
    String operation,
  ) {
    return switch (category) {
      SyncErrorCategory.network => [
        SyncRecoveryAction.retryLater(),
        SyncRecoveryAction.checkConnection(),
        SyncRecoveryAction.workOffline(),
      ],
      
      SyncErrorCategory.authentication => [
        SyncRecoveryAction.signInAgain(),
        SyncRecoveryAction.contactSupport(),
      ],
      
      SyncErrorCategory.permissions => [
        SyncRecoveryAction.retryNow(),
        SyncRecoveryAction.checkServiceStatus(),
        SyncRecoveryAction.contactSupport(),
      ],
      
      SyncErrorCategory.localStorage => [
        SyncRecoveryAction.restartApp(),
        SyncRecoveryAction.exportData(),
        SyncRecoveryAction.contactSupport(),
      ],
      
      SyncErrorCategory.dataIntegrity => [
        SyncRecoveryAction.reviewData(),
        SyncRecoveryAction.exportData(),
        SyncRecoveryAction.contactSupport(),
      ],
      
      SyncErrorCategory.circuitBreaker => [
        SyncRecoveryAction.waitAndRetry(),
        SyncRecoveryAction.resetSync(),
      ],
      
      SyncErrorCategory.unknown => [
        SyncRecoveryAction.retryNow(),
        SyncRecoveryAction.restartApp(),
        SyncRecoveryAction.contactSupport(),
      ],
    };
  }
}

/// Represents a recovery action the user can take
class SyncRecoveryAction {
  const SyncRecoveryAction({
    required this.label,
    required this.description,
    required this.action,
    this.isPrimary = false,
    this.isDestructive = false,
  });

  final String label;
  final String description;
  final VoidCallback action;
  final bool isPrimary;
  final bool isDestructive;

  static SyncRecoveryAction retryNow() => SyncRecoveryAction(
        label: 'Retry Now',
        description: 'Attempt the sync operation again',
        isPrimary: true,
        action: () {
          // Will be implemented by the handler
          SyncErrorHandler.instance.retryLastOperation();
        },
      );

  static SyncRecoveryAction retryLater() => SyncRecoveryAction(
        label: 'Retry Later',
        description: 'Sync will resume automatically when conditions improve',
        action: () {
          snacks.text('Sync will resume automatically when possible');
        },
      );

  static SyncRecoveryAction signInAgain() => SyncRecoveryAction(
        label: 'Sign In',
        description: 'Authenticate again to restore sync',
        isPrimary: true,
        action: () {
          // Will trigger sign-in flow
          SyncErrorHandler.instance.triggerSignIn();
        },
      );

  static SyncRecoveryAction checkConnection() => SyncRecoveryAction(
        label: 'Check Network',
        description: 'Verify your internet connection',
        action: () {
          snacks.text('Please check your network connection and try again');
        },
      );

  static SyncRecoveryAction workOffline() => SyncRecoveryAction(
        label: 'Work Offline',
        description: 'Continue without syncing - data will sync later',
        action: () {
          snacks.text('Working offline - your data is saved locally');
        },
      );

  static SyncRecoveryAction checkServiceStatus() => SyncRecoveryAction(
        label: 'Service Status',
        description: 'Check if cloud services are experiencing issues',
        action: () {
          // Could open a service status page or just inform user
          snacks.text('If the issue persists, our cloud services may be experiencing problems');
        },
      );

  static SyncRecoveryAction restartApp() => SyncRecoveryAction(
        label: 'Restart App',
        description: 'Close and reopen FermentaCraft',
        action: () {
          snacks.text('Please close and reopen the app, then try again');
        },
      );

  static SyncRecoveryAction exportData() => SyncRecoveryAction(
        label: 'Export Data',
        description: 'Save your data as a backup',
        action: () {
          SyncErrorHandler.instance.triggerDataExport();
        },
      );

  static SyncRecoveryAction reviewData() => SyncRecoveryAction(
        label: 'Review Data',
        description: 'Check your data for any inconsistencies',
        action: () {
          snacks.text('Please review your recent entries for any missing or incorrect data');
        },
      );

  static SyncRecoveryAction waitAndRetry() => SyncRecoveryAction(
        label: 'Wait & Retry',
        description: 'Sync will resume automatically after a brief pause',
        action: () {
          snacks.text('Sync paused temporarily - will resume automatically');
        },
      );

  static SyncRecoveryAction resetSync() => SyncRecoveryAction(
        label: 'Reset Sync',
        description: 'Clear sync state and start fresh',
        isDestructive: true,
        action: () {
          SyncErrorHandler.instance.resetSyncState();
        },
      );

  static SyncRecoveryAction contactSupport() => SyncRecoveryAction(
        label: 'Get Help',
        description: 'Contact support with error details',
        action: () {
          SyncErrorHandler.instance.contactSupport();
        },
      );
}

/// Central error handler for sync operations
class SyncErrorHandler {
  SyncErrorHandler._();
  static final SyncErrorHandler instance = SyncErrorHandler._();

  String? _lastOperationKey;
  BuildContext? _currentContext;

  /// Handle a sync error with appropriate user feedback
  void handleSyncError(
    SyncError error, {
    BuildContext? context,
    bool showUserFeedback = true,
  }) {
    // Log the error
    _logError(error);

    // Update context for recovery actions - prefer passed context over stored one
    final effectiveContext = context ?? _currentContext;
    if (effectiveContext != null && effectiveContext.mounted) {
      _currentContext = effectiveContext;
    }

    // Show user feedback based on severity
    if (showUserFeedback) {
      _showUserFeedback(error);
    }

    // Handle automatic recovery for certain error types
    _handleAutomaticRecovery(error);
  }

  /// Handle error from retry system with context
  void handleRetryError({
    required String operationKey,
    required Object error,
    required String userId,
    required Map<String, dynamic> context,
    BuildContext? buildContext,
  }) {
    _lastOperationKey = operationKey;

    final syncError = SyncError.fromException(
      operation: operationKey,
      error: error,
      userId: userId,
      context: context,
    );

    handleSyncError(
      syncError,
      context: buildContext,
      showUserFeedback: true,
    );
  }

  /// Show appropriate user feedback based on error severity
  void _showUserFeedback(SyncError error) {
    final context = _currentContext;
    if (context == null || !context.mounted) {
      // Context is invalid, fallback to logging only
      _logError(error);
      return;
    }

    switch (error.severity) {
      case SyncErrorSeverity.info:
        // Just log, no user notification needed
        break;

      case SyncErrorSeverity.warning:
        snacks.show(SnackBar(
          content: Text(error.userMessage),
          backgroundColor: Theme.of(context).colorScheme.secondary,
          duration: const Duration(seconds: 4),
        ));
        break;

      case SyncErrorSeverity.error:
        snacks.show(SnackBar(
          content: Text(error.userMessage),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Details',
            textColor: Theme.of(context).colorScheme.onError,
            onPressed: () => _showErrorDetails(error),
          ),
        ));
        break;

      case SyncErrorSeverity.critical:
        // Show full error dialog for critical issues
        // Use post-frame callback to ensure we're not in the middle of a build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            _showCriticalErrorDialog(error);
          }
        });
        break;
    }
  }

  /// Show detailed error dialog with recovery options
  void _showCriticalErrorDialog(SyncError error) {
    final context = _currentContext;
    if (context == null || !context.mounted) {
      // Context is invalid, fallback to snackbar if possible
      snacks.show(SnackBar(
        content: Text(error.userMessage),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 6),
      ));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false, // Critical errors require action
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.sync_problem,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            const Text('Sync Issue'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.userMessage),
              const SizedBox(height: 16),
              if (error.recoveryActions.isNotEmpty) ...[
                const Text(
                  'What would you like to do?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        actions: [
          ...error.recoveryActions.take(3).map((action) => 
            action.isPrimary 
              ? FilledButton(
                  onPressed: () {
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                      action.action();
                    }
                  },
                  child: Text(action.label),
                )
              : TextButton(
                  onPressed: () {
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                      action.action();
                    }
                  },
                  child: Text(action.label),
                ),
          ),
          if (error.recoveryActions.length > 3)
            TextButton(
              onPressed: () {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                  _showAllRecoveryOptions(error);
                }
              },
              child: const Text('More Options'),
            ),
        ],
      ),
    );
  }

  /// Show all available recovery options
  void _showAllRecoveryOptions(SyncError error) {
    final context = _currentContext;
    if (context == null || !context.mounted) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recovery Options',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ...error.recoveryActions.map((action) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(action.label),
                subtitle: Text(action.description),
                trailing: action.isDestructive 
                  ? Icon(Icons.warning, color: Theme.of(context).colorScheme.error)
                  : null,
                onTap: () {
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                    action.action();
                  }
                },
              ),
            )),
          ],
        ),
      ),
    );
  }

  /// Show error details in a dialog
  void _showErrorDetails(SyncError error) {
    final context = _currentContext;
    if (context == null || !context.mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Error Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Operation', error.operation),
              _buildDetailRow('Category', error.category.name),
              _buildDetailRow('Severity', error.severity.name),
              _buildDetailRow('Error', error.technicalMessage),
              if (error.context.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Context:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                ...error.context.entries.map(
                  (e) => _buildDetailRow(e.key, e.value.toString()),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (dialogContext.mounted) {
                Clipboard.setData(ClipboardData(
                  text: _formatErrorForClipboard(error),
                ));
                snacks.text('Error details copied to clipboard');
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Copy Details'),
          ),
          FilledButton(
            onPressed: () {
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  /// Format error information for clipboard export
  String _formatErrorForClipboard(SyncError error) {
    final buffer = StringBuffer();
    buffer.writeln('FermentaCraft Sync Error Report');
    buffer.writeln('================================');
    buffer.writeln('Operation: ${error.operation}');
    buffer.writeln('Category: ${error.category.name}');
    buffer.writeln('Severity: ${error.severity.name}');
    buffer.writeln('User Message: ${error.userMessage}');
    buffer.writeln('Technical Message: ${error.technicalMessage}');
    
    if (error.context.isNotEmpty) {
      buffer.writeln('\nContext:');
      for (final entry in error.context.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
    }
    
    buffer.writeln('\nGenerated: ${DateTime.now()}');
    return buffer.toString();
  }

  /// Log error with appropriate level
  void _logError(SyncError error) {
    final logLevel = switch (error.severity) {
      SyncErrorSeverity.info => LogLevel.info,
      SyncErrorSeverity.warning => LogLevel.warning,
      SyncErrorSeverity.error => LogLevel.error,
      SyncErrorSeverity.critical => LogLevel.error,
    };

    final logEntry = LogEntry(
      message: 'Sync error in ${error.operation}: ${error.userMessage}',
      level: logLevel,
      category: LogCategory.sync,
      operation: error.operation,
      details: {
        'category': error.category.name,
        'severity': error.severity.name,
        'technical_message': error.technicalMessage,
        ...error.context,
      },
      error: error.error,
      timestamp: DateTime.now(),
    );

    AppLogger.instance.log(logEntry);
  }

  /// Handle automatic recovery for certain error types
  void _handleAutomaticRecovery(SyncError error) {
    // Implement automatic recovery strategies
    switch (error.category) {
      case SyncErrorCategory.network:
        // Network errors might recover automatically
        break;
        
      case SyncErrorCategory.circuitBreaker:
        // Circuit breaker will handle its own recovery
        break;
        
      default:
        // No automatic recovery for other types
        break;
    }
  }

  // Recovery action implementations
  void retryLastOperation() {
    if (_lastOperationKey == null) {
      snacks.text('No operation to retry');
      return;
    }

    // Reset the circuit breaker for this operation
    SyncRetryManager.instance.resetCircuitBreaker(_lastOperationKey!);
    snacks.text('Retrying operation...');
    
    // The actual retry will happen when the sync service attempts the operation again
  }

  void triggerSignIn() {
    // This would trigger the authentication flow
    // Implementation depends on your auth system
    snacks.text('Please sign in to continue syncing');
  }

  void triggerDataExport() {
    // This would trigger data export functionality
    // Implementation depends on your export system
    snacks.text('Data export feature would be triggered here');
  }

  void resetSyncState() {
    // Clear all circuit breakers and retry state
    SyncRetryManager.instance.clearAllCircuitBreakers();
    snacks.text('Sync state reset - trying again...');
  }

  void contactSupport() {
    // This would open support contact options
    snacks.text('Please contact support at developer@fermentacraft.com');
  }

  /// Update the current context for showing dialogs
  /// Use WeakReference to avoid holding onto disposed contexts
  void updateContext(BuildContext? context) {
    _currentContext = context;
  }
}