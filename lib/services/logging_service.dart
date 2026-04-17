// lib/services/logging_service.dart
// Copyright 2024 Brian Henson
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import '../core/errors.dart';

/// Structured logging service for consistent debug output
class LoggingService {
  static const String _prefix = '[FermentaCraft]';

  /// Log general information
  static void info(String message, {String? tag, Map<String, dynamic>? data}) {
    _log('INFO', message, tag: tag, data: data);
  }

  /// Log debug information
  static void debug(String message, {String? tag, Map<String, dynamic>? data}) {
    _log('DEBUG', message, tag: tag, data: data);
  }

  /// Log warnings
  static void warning(String message, {String? tag, Map<String, dynamic>? data}) {
    _log('WARN', message, tag: tag, data: data);
  }

  /// Log errors
  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? data,
  }) {
    _log('ERROR', message, tag: tag, data: data);
    if (error != null) {
      debugPrint('$_prefix Exception: $error');
    }
    if (stackTrace != null && kDebugMode) {
      debugPrint('$_prefix StackTrace:\n$stackTrace');
    }
  }

  /// Log Firebase operations
  static void firebase(String operation, {bool success = true, dynamic result}) {
    final status = success ? 'SUCCESS' : 'FAILED';
    final message = 'Firebase: $operation [$status]';
    if (success) {
      debug(message, tag: 'Firebase', data: {'operation': operation, 'result': result.toString()});
    } else {
      error(message, tag: 'Firebase', data: {'operation': operation, 'error': result});
    }
  }

  /// Log sync operations
  static void sync(String operation, {bool success = true, dynamic data}) {
    final status = success ? 'SUCCESS' : 'FAILED';
    final message = 'Sync: $operation [$status]';
    debug(message, tag: 'Sync', data: {'operation': operation, 'status': status});
  }

  /// Log measurement operations
  static void measurement(
    String operation, {
    required String batchId,
    bool success = true,
    dynamic data,
  }) {
    final status = success ? 'SUCCESS' : 'FAILED';
    final message = 'Measurement: $operation [$status]';
    debug(message, tag: 'Measurement', data: {
      'operation': operation,
      'batchId': batchId,
      'status': status,
      'details': data?.toString(),
    });
  }

  /// Log device operations (hydrometers, sensors)
  static void device(
    String operation, {
    required String deviceName,
    bool success = true,
    dynamic data,
  }) {
    final status = success ? 'SUCCESS' : 'FAILED';
    final message = 'Device: $operation [$status]';
    debug(message, tag: 'Device', data: {
      'operation': operation,
      'device': deviceName,
      'status': status,
      'details': data?.toString(),
    });
  }

  /// Log AppException with structured context
  static void appException(
    AppException exception, {
    String? context,
    Map<String, dynamic>? additionalData,
  }) {
    final data = {
      'type': exception.runtimeType.toString(),
      'userMessage': exception.userMessage,
      'context': context,
      ...?additionalData,
    };

    error(
      'AppException: ${exception.runtimeType}',
      tag: 'Exception',
      error: exception,
      data: data,
    );
  }

  /// Log batch operations
  static void batch(
    String operation, {
    required String batchId,
    required String batchName,
    bool success = true,
    dynamic data,
  }) {
    final status = success ? 'SUCCESS' : 'FAILED';
    final message = 'Batch: $operation [$status]';
    debug(message, tag: 'Batch', data: {
      'operation': operation,
      'batchId': batchId,
      'batchName': batchName,
      'status': status,
      'details': data?.toString(),
    });
  }

  /// Log validation operations
  static void validation(
    String fieldName, {
    bool valid = true,
    String? reason,
    dynamic value,
  }) {
    final status = valid ? 'VALID' : 'INVALID';
    final message = 'Validation: $fieldName [$status]';
    debug(message, tag: 'Validation', data: {
      'field': fieldName,
      'status': status,
      'reason': reason,
      'value': value?.toString(),
    });
  }

  // Private logging implementation
  static void _log(
    String level,
    String message, {
    String? tag,
    Map<String, dynamic>? data,
  }) {
    final tagStr = tag != null ? '[$tag]' : '';
    final timestamp = _getTimestamp();
    final dataStr = data != null ? ' | ${_formatData(data)}' : '';

    final fullMessage = '$_prefix [$level] $timestamp $tagStr $message$dataStr';
    debugPrint(fullMessage);
  }

  static String _getTimestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  static String _formatData(Map<String, dynamic> data) {
    final entries = data.entries.where((e) => e.value != null).map(
          (e) => '${e.key}=${e.value}',
        );
    return '{${entries.join(', ')}}';
  }
}
