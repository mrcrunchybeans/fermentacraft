/// Result pattern for consistent error handling across the app
/// 
/// This provides a type-safe way to handle operations that can succeed or fail
/// without throwing exceptions, making error handling more explicit and reliable.

/// Base result class for success/failure operations
sealed class Result<T, E> {
  const Result();
  
  /// Returns true if this is a success result
  bool get isSuccess => this is Success<T, E>;
  
  /// Returns true if this is a failure result
  bool get isFailure => this is Failure<T, E>;
  
  /// Get the value if success, null otherwise
  T? get value => isSuccess ? (this as Success<T, E>).value : null;
  
  /// Get the error if failure, null otherwise
  E? get error => isFailure ? (this as Failure<T, E>).error : null;
  
  /// Transform success value, leave failure unchanged
  Result<R, E> map<R>(R Function(T value) transform) {
    return switch (this) {
      Success(value: final T value) => Success(transform(value)),
      Failure(error: final E error) => Failure(error),
    };
  }
  
  /// Transform failure error, leave success unchanged
  Result<T, R> mapError<R>(R Function(E error) transform) {
    return switch (this) {
      Success(value: final T value) => Success(value),
      Failure(error: final E error) => Failure(transform(error)),
    };
  }
  
  /// Chain operations that return Results
  Result<R, E> flatMap<R>(Result<R, E> Function(T value) transform) {
    return switch (this) {
      Success(value: final T value) => transform(value),
      Failure(error: final E error) => Failure(error),
    };
  }
  
  /// Execute side effect if success
  Result<T, E> onSuccess(void Function(T value) callback) {
    if (isSuccess) {
      callback(value!);
    }
    return this;
  }
  
  /// Execute side effect if failure
  Result<T, E> onFailure(void Function(E error) callback) {
    if (isFailure) {
      callback(error!);
    }
    return this;
  }
  
  /// Get value or provide default
  T valueOr(T defaultValue) => value ?? defaultValue;
  
  /// Get value or compute from error
  T valueOrElse(T Function(E error) compute) {
    return switch (this) {
      Success(value: final T value) => value,
      Failure(error: final E error) => compute(error),
    };
  }
}

/// Successful result containing a value
final class Success<T, E> extends Result<T, E> {
  const Success(this.value);
  
  final T value;
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Success<T, E> && value == other.value;
  
  @override
  int get hashCode => value.hashCode;
  
  @override
  String toString() => 'Success($value)';
}

/// Failed result containing an error
final class Failure<T, E> extends Result<T, E> {
  const Failure(this.error);
  
  final E error;
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure<T, E> && error == other.error;
  
  @override
  int get hashCode => error.hashCode;
  
  @override
  String toString() => 'Failure($error)';
}

/// Common error types for the application
enum AppErrorType {
  network,
  authentication,
  authorization,
  validation,
  storage,
  sync,
  premium,
  unknown,
}

/// Application error with categorization and context
class AppError {
  const AppError({
    required this.type,
    required this.message,
    this.details,
    this.stackTrace,
    this.code,
  });
  
  final AppErrorType type;
  final String message;
  final String? details;
  final StackTrace? stackTrace;
  final String? code;
  
  /// Create network error
  factory AppError.network(String message, {String? details, String? code}) {
    return AppError(
      type: AppErrorType.network,
      message: message,
      details: details,
      code: code,
    );
  }
  
  /// Create authentication error
  factory AppError.authentication(String message, {String? details, String? code}) {
    return AppError(
      type: AppErrorType.authentication,
      message: message,
      details: details,
      code: code,
    );
  }
  
  /// Create validation error
  factory AppError.validation(String message, {String? details, String? code}) {
    return AppError(
      type: AppErrorType.validation,
      message: message,
      details: details,
      code: code,
    );
  }
  
  /// Create storage error
  factory AppError.storage(String message, {String? details, String? code}) {
    return AppError(
      type: AppErrorType.storage,
      message: message,
      details: details,
      code: code,
    );
  }
  
  /// Create sync error
  factory AppError.sync(String message, {String? details, String? code}) {
    return AppError(
      type: AppErrorType.sync,
      message: message,
      details: details,
      code: code,
    );
  }
  
  /// Create premium feature error
  factory AppError.premium(String message, {String? details, String? code}) {
    return AppError(
      type: AppErrorType.premium,
      message: message,
      details: details,
      code: code,
    );
  }
  
  /// Create unknown error from exception
  factory AppError.unknown(Object exception, {StackTrace? stackTrace}) {
    return AppError(
      type: AppErrorType.unknown,
      message: exception.toString(),
      stackTrace: stackTrace,
    );
  }
  
  @override
  String toString() {
    final buffer = StringBuffer('AppError(${type.name}: $message');
    if (details != null) buffer.write(', details: $details');
    if (code != null) buffer.write(', code: $code');
    buffer.write(')');
    return buffer.toString();
  }
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppError &&
          type == other.type &&
          message == other.message &&
          details == other.details &&
          code == other.code;
  
  @override
  int get hashCode => Object.hash(type, message, details, code);
}

/// Convenience type alias for common Result usage
typedef AppResult<T> = Result<T, AppError>;

/// Utility functions for working with Results
class ResultUtils {
  /// Wrap a function that might throw into a Result
  static Result<T, AppError> catching<T>(T Function() computation) {
    try {
      return Success(computation());
    } catch (e, stackTrace) {
      return Failure(AppError.unknown(e, stackTrace: stackTrace));
    }
  }
  
  /// Wrap an async function that might throw into a Result
  static Future<Result<T, AppError>> catchingAsync<T>(
    Future<T> Function() computation,
  ) async {
    try {
      final result = await computation();
      return Success(result);
    } catch (e, stackTrace) {
      return Failure(AppError.unknown(e, stackTrace: stackTrace));
    }
  }
  
  /// Combine multiple Results - succeeds only if all succeed
  static Result<List<T>, E> combine<T, E>(List<Result<T, E>> results) {
    final values = <T>[];
    for (final result in results) {
      switch (result) {
        case Success(value: final T value):
          values.add(value);
        case Failure(error: final E error):
          return Failure(error);
      }
    }
    return Success(values);
  }
  
  /// Get the first success result, or the last failure if all fail
  static Result<T, E> firstSuccess<T, E>(List<Result<T, E>> results) {
    if (results.isEmpty) {
      throw ArgumentError('Cannot get first success from empty list');
    }
    
    Result<T, E>? lastFailure;
    for (final result in results) {
      switch (result) {
        case Success():
          return result;
        case Failure():
          lastFailure = result;
      }
    }
    return lastFailure!;
  }
}

/// Extension methods for Future<Result>
extension FutureResultExtensions<T, E> on Future<Result<T, E>> {
  /// Map the success value asynchronously
  Future<Result<R, E>> mapAsync<R>(Future<R> Function(T value) transform) async {
    final result = await this;
    return switch (result) {
      Success(value: final T value) => Success(await transform(value)),
      Failure(error: final E error) => Failure(error),
    };
  }
  
  /// Chain async operations
  Future<Result<R, E>> flatMapAsync<R>(
    Future<Result<R, E>> Function(T value) transform,
  ) async {
    final result = await this;
    return switch (result) {
      Success(value: final T value) => await transform(value),
      Failure(error: final E error) => Failure(error),
    };
  }
}

/// Extension for easier error handling
extension AppResultExtensions<T> on AppResult<T> {
  /// Show user-friendly error message
  String get userMessage {
    return switch (this) {
      Success() => '',
      Failure(error: final AppError error) => switch (error.type) {
        AppErrorType.network => 'Network error: ${error.message}',
        AppErrorType.authentication => 'Authentication failed: ${error.message}',
        AppErrorType.authorization => 'Not authorized: ${error.message}',
        AppErrorType.validation => 'Invalid input: ${error.message}',
        AppErrorType.storage => 'Storage error: ${error.message}',
        AppErrorType.sync => 'Sync error: ${error.message}',
        AppErrorType.premium => 'Premium feature: ${error.message}',
        AppErrorType.unknown => 'Unexpected error: ${error.message}',
      },
    };
  }
  
  /// Check if error requires user attention
  bool get requiresUserAction {
    return switch (this) {
      Success() => false,
      Failure(error: final AppError error) => switch (error.type) {
        AppErrorType.authentication => true,
        AppErrorType.premium => true,
        AppErrorType.validation => true,
        _ => false,
      },
    };
  }
}