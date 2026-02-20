// Copyright 2024 Brian Henson
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Application-specific exceptions with user-friendly error messages
/// 
/// This file defines a hierarchy of exceptions that provide:
/// - Specific error types for different failure scenarios
/// - User-friendly messages for UI display
/// - Error codes for logging and analytics
/// - Original error preservation for debugging
library;

/// Base class for all application exceptions
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;
  final StackTrace? stackTrace;
  
  AppException(
    this.message, {
    this.code,
    this.originalError,
    this.stackTrace,
  });
  
  /// User-friendly message to display in UI
  String get userMessage => message;
  
  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (code != null) buffer.write(' (code: $code)');
    if (originalError != null) buffer.write('\nCaused by: $originalError');
    return buffer.toString();
  }
}

// ============================================================================
// Data Access Exceptions
// ============================================================================

/// Thrown when a requested entity is not found
class NotFoundException extends AppException {
  final String entityType;
  final String entityId;
  
  NotFoundException({
    required this.entityType,
    required this.entityId,
  }) : super(
    '$entityType not found: $entityId',
    code: 'NOT_FOUND',
  );
  
  @override
  String get userMessage => 'The $entityType you\'re looking for doesn\'t exist.';
}

/// Specific exception for batch not found
class BatchNotFoundException extends NotFoundException {
  BatchNotFoundException(String id) 
    : super(entityType: 'Batch', entityId: id);
}

/// Specific exception for recipe not found
class RecipeNotFoundException extends NotFoundException {
  RecipeNotFoundException(String id) 
    : super(entityType: 'Recipe', entityId: id);
}

/// Thrown when attempting to save invalid data
class ValidationException extends AppException {
  final Map<String, String> errors;
  
  ValidationException(super.message, this.errors) 
    : super(code: 'VALIDATION_ERROR');
  
  @override
  String get userMessage {
    if (errors.isEmpty) return 'Please check your input and try again.';
    return errors.values.first;
  }
}

/// Thrown when a data integrity constraint is violated
class DataIntegrityException extends AppException {
  DataIntegrityException(super.message) 
    : super(code: 'DATA_INTEGRITY_ERROR');
  
  @override
  String get userMessage => 'Unable to save changes. Please try again.';
}

// ============================================================================
// Synchronization Exceptions
// ============================================================================

/// Thrown when local and remote data conflict
class SyncConflictException extends AppException {
  final String entityType;
  final String entityId;
  final DateTime localTimestamp;
  final DateTime remoteTimestamp;
  
  SyncConflictException({
    required this.entityType,
    required this.entityId,
    required this.localTimestamp,
    required this.remoteTimestamp,
  }) : super(
    'Sync conflict for $entityType $entityId: local=$localTimestamp, remote=$remoteTimestamp',
    code: 'SYNC_CONFLICT',
  );
  
  @override
  String get userMessage => 
    'This $entityType was modified elsewhere. Please review the changes.';
}

/// Thrown when sync fails due to network or server issues
class SyncFailedException extends AppException {
  final int? retryCount;
  
  SyncFailedException(super.message, {this.retryCount, super.originalError}) 
    : super(code: 'SYNC_FAILED');
  
  @override
  String get userMessage {
    if (retryCount != null && retryCount! > 0) {
      return 'Sync failed after $retryCount attempts. Check your connection.';
    }
    return 'Unable to sync. Please check your connection and try again.';
  }
}

// ============================================================================
// Network Exceptions
// ============================================================================

/// Base class for network-related errors
class NetworkException extends AppException {
  NetworkException(super.message, {super.originalError}) 
    : super(code: 'NETWORK_ERROR');
  
  @override
  String get userMessage => 
    'Network error. Please check your connection and try again.';
}

/// Thrown when no internet connection is available
class NoConnectionException extends NetworkException {
  NoConnectionException() : super('No internet connection');
  
  @override
  String get userMessage => 
    'No internet connection. Please check your network settings.';
}

/// Thrown when request times out
class TimeoutException extends NetworkException {
  TimeoutException() : super('Request timed out');
  
  @override
  String get userMessage => 
    'Request timed out. Please try again.';
}

/// Thrown when server returns an error
class ServerException extends NetworkException {
  final int? statusCode;
  
  ServerException(super.message, {this.statusCode, super.originalError});
  
  @override
  String get userMessage {
    if (statusCode == 401 || statusCode == 403) {
      return 'Authentication failed. Please sign in again.';
    } else if (statusCode == 404) {
      return 'The requested resource was not found.';
    } else if (statusCode != null && statusCode! >= 500) {
      return 'Server error. Please try again later.';
    }
    return 'Something went wrong. Please try again.';
  }
}

// ============================================================================
// Authentication & Authorization Exceptions
// ============================================================================

/// Thrown when user is not authenticated
class UnauthenticatedException extends AppException {
  UnauthenticatedException() 
    : super('User is not authenticated', code: 'UNAUTHENTICATED');
  
  @override
  String get userMessage => 'Please sign in to continue.';
}

/// Thrown when user lacks required permissions
class UnauthorizedException extends AppException {
  final String? requiredPermission;
  
  UnauthorizedException({this.requiredPermission}) 
    : super(
        'User is not authorized${requiredPermission != null ? " (requires: $requiredPermission)" : ""}',
        code: 'UNAUTHORIZED',
      );
  
  @override
  String get userMessage => 
    'You don\'t have permission to perform this action.';
}

// ============================================================================
// Device Integration Exceptions
// ============================================================================

/// Thrown when device data is malformed or invalid
class InvalidDeviceDataException extends AppException {
  final String deviceName;
  final String field;
  
  InvalidDeviceDataException({
    required this.deviceName,
    required this.field,
    dynamic originalError,
  }) : super(
        'Invalid data from $deviceName: $field',
        code: 'INVALID_DEVICE_DATA',
        originalError: originalError,
      );
  
  @override
  String get userMessage => 
    'Received invalid data from $deviceName. The measurement was skipped.';
}

/// Thrown when device connection fails
class DeviceConnectionException extends AppException {
  final String deviceName;
  
  DeviceConnectionException(this.deviceName, {dynamic originalError}) 
    : super(
        'Failed to connect to $deviceName',
        code: 'DEVICE_CONNECTION_ERROR',
        originalError: originalError,
      );
  
  @override
  String get userMessage => 
    'Unable to connect to $deviceName. Please check the device.';
}

// ============================================================================
// File & Storage Exceptions
// ============================================================================

/// Thrown when file operations fail
class FileOperationException extends AppException {
  final String operation;
  final String? path;
  
  FileOperationException({
    required this.operation,
    this.path,
    dynamic originalError,
  }) : super(
        'File $operation failed${path != null ? ": $path" : ""}',
        code: 'FILE_OPERATION_ERROR',
        originalError: originalError,
      );
  
  @override
  String get userMessage {
    if (operation == 'read') return 'Unable to read file. Please try again.';
    if (operation == 'write') return 'Unable to save file. Please try again.';
    if (operation == 'delete') return 'Unable to delete file. Please try again.';
    return 'File operation failed. Please try again.';
  }
}

/// Thrown when storage quota is exceeded
class StorageQuotaException extends AppException {
  final int? currentUsageBytes;
  final int? limitBytes;
  
  StorageQuotaException({this.currentUsageBytes, this.limitBytes}) 
    : super('Storage quota exceeded', code: 'STORAGE_QUOTA_EXCEEDED');
  
  @override
  String get userMessage => 
    'Storage limit reached. Please free up space and try again.';
}

// ============================================================================
// Business Logic Exceptions
// ============================================================================

/// Thrown when a business rule is violated
class BusinessRuleException extends AppException {
  BusinessRuleException(super.message) 
    : super(code: 'BUSINESS_RULE_VIOLATION');
  
  @override
  String get userMessage => message;
}

/// Thrown when batch is in wrong state for operation
class InvalidBatchStateException extends BusinessRuleException {
  final String batchId;
  final String currentState;
  final String requiredState;
  
  InvalidBatchStateException({
    required this.batchId,
    required this.currentState,
    required this.requiredState,
  }) : super(
    'Batch $batchId is in $currentState state, but $requiredState is required',
  );
  
  @override
  String get userMessage => 
    'This action is not available for batches in $currentState state.';
}

/// Thrown when operation would create duplicate data
class DuplicateException extends BusinessRuleException {
  final String entityType;
  final String duplicateField;
  
  DuplicateException({
    required this.entityType,
    required this.duplicateField,
  }) : super('$entityType with this $duplicateField already exists');
  
  @override
  String get userMessage => 
    'A $entityType with this $duplicateField already exists.';
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Helper to convert generic exceptions to AppException
AppException toAppException(dynamic error, {String? context}) {
  if (error is AppException) return error;
  
  // Try to infer exception type from error message
  final message = error.toString().toLowerCase();
  
  if (message.contains('not found')) {
    return NotFoundException(
      entityType: context ?? 'Resource',
      entityId: 'unknown',
    );
  }
  
  if (message.contains('network') || message.contains('connection')) {
    return NetworkException(error.toString(), originalError: error);
  }
  
  if (message.contains('timeout')) {
    return TimeoutException();
  }
  
  if (message.contains('permission') || message.contains('unauthorized')) {
    return UnauthorizedException();
  }
  
  // Generic exception as fallback
  return AppException(
    context != null ? '$context: ${error.toString()}' : error.toString(),
    code: 'UNKNOWN_ERROR',
    originalError: error,
  );
}
