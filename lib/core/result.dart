// Copyright 2024 Brian Henson
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'errors.dart';

/// A Result type for handling success and failure cases
/// 
/// This provides a type-safe way to handle operations that can fail
/// without throwing exceptions. Inspired by Rust's Result<T, E> type.
/// 
/// Example usage:
/// ```dart
/// Future<Result<BatchModel>> getBatch(String id) async {
///   try {
///     final batch = await repository.getById(id);
///     return Result.success(batch);
///   } on AppException catch (e) {
///     return Result.failure(e);
///   }
/// }
/// 
/// // Using the result
/// final result = await getBatch('123');
/// result.when(
///   success: (batch) => print('Got batch: ${batch.name}'),
///   failure: (error) => print('Error: ${error.userMessage}'),
/// );
/// ```

class Result<T> {
  final T? _value;
  final AppException? _error;
  
  const Result._(this._value, this._error);
  
  /// Creates a successful result with a value
  factory Result.success(T value) => Result._(value, null);
  
  /// Creates a failed result with an error
  factory Result.failure(AppException error) => Result._(null, error);
  
  /// Creates a failed result from any exception
  factory Result.failureFrom(dynamic error, {String? context}) {
    return Result.failure(toAppException(error, context: context));
  }
  
  /// Whether this result is successful
  bool get isSuccess => _error == null;
  
  /// Whether this result is a failure
  bool get isFailure => _error != null;
  
  /// Gets the value if successful, throws if failed
  T get value {
    if (_error != null) throw _error;
    return _value as T;
  }
  
  /// Gets the error if failed, null if successful
  AppException? get error => _error;
  
  /// Gets the value or returns a default if failed
  T getOrElse(T defaultValue) => _value ?? defaultValue;
  
  /// Gets the value or computes a default if failed
  T getOrElseGet(T Function() defaultValue) => _value ?? defaultValue();
  
  /// Gets the value or null if failed
  T? get valueOrNull => _value;
  
  /// Transforms the value if successful
  Result<U> map<U>(U Function(T) transform) {
    if (_error != null) return Result.failure(_error);
    return Result.success(transform(_value as T));
  }
  
  /// Transforms the value if successful, returning a new Result
  Result<U> flatMap<U>(Result<U> Function(T) transform) {
    if (_error != null) return Result.failure(_error);
    return transform(_value as T);
  }
  
  /// Transforms the error if failed
  Result<T> mapError(AppException Function(AppException) transform) {
    if (_error == null) return Result.success(_value as T);
    return Result.failure(transform(_error));
  }
  
  /// Pattern matching on the result
  R when<R>({
    required R Function(T) success,
    required R Function(AppException) failure,
  }) {
    if (_error != null) return failure(_error);
    return success(_value as T);
  }
  
  /// Runs a function if successful
  Result<T> onSuccess(void Function(T) action) {
    if (_error == null) action(_value as T);
    return this;
  }
  
  /// Runs a function if failed
  Result<T> onFailure(void Function(AppException) action) {
    if (_error != null) action(_error);
    return this;
  }
  
  /// Runs different functions based on success/failure
  void fold({
    required void Function(T) onSuccess,
    required void Function(AppException) onFailure,
  }) {
    if (_error != null) {
      onFailure(_error);
    } else {
      onSuccess(_value as T);
    }
  }
  
  @override
  String toString() {
    if (_error != null) return 'Result.failure($_error)';
    return 'Result.success($_value)';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Result<T> && 
           other._value == _value && 
           other._error == _error;
  }
  
  @override
  int get hashCode => Object.hash(_value, _error);
}

/// Extension to convert Future<T> to Future<Result<T>>
extension FutureResultExtension<T> on Future<T> {
  /// Catches any error and wraps it in a Result
  Future<Result<T>> toResult({String? context}) async {
    try {
      final value = await this;
      return Result.success(value);
    } catch (error) {
      return Result.failureFrom(error, context: context);
    }
  }
  
  /// Catches specific exception types and wraps in Result
  Future<Result<T>> toResultCatching({
    String? context,
    AppException Function(dynamic)? onError,
  }) async {
    try {
      final value = await this;
      return Result.success(value);
    } catch (error) {
      if (onError != null) {
        return Result.failure(onError(error));
      }
      return Result.failureFrom(error, context: context);
    }
  }
}

/// Extension for List<Result<T>>
extension ResultListExtension<T> on List<Result<T>> {
  /// Combines results, failing if any failed
  Result<List<T>> combine() {
    final values = <T>[];
    for (final result in this) {
      if (result.isFailure) {
        return Result.failure(result.error!);
      }
      values.add(result.value);
    }
    return Result.success(values);
  }
  
  /// Gets only successful values
  List<T> getSuccesses() {
    return where((r) => r.isSuccess).map((r) => r.value).toList();
  }
  
  /// Gets only failures
  List<AppException> getFailures() {
    return where((r) => r.isFailure).map((r) => r.error!).toList();
  }
}
