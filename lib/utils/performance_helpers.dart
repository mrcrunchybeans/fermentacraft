/// Widget rebuild tracking helper
/// Makes it easy to track widget rebuilds for performance monitoring
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../utils/performance_profiler.dart';

/// Mixin to automatically track widget rebuilds
/// Add this mixin to any StatefulWidget or StatelessWidget to track its rebuilds
mixin RebuildTrackingMixin on Widget {
  /// Widget name for tracking (defaults to runtimeType)
  String get trackingName => runtimeType.toString();
  
  /// Whether to track this widget's rebuilds
  bool get shouldTrack => kDebugMode;
  
  /// Track a rebuild for this widget
  void trackRebuild([Map<String, dynamic>? context]) {
    if (!shouldTrack) return;
    WidgetRebuildTracker.instance.trackRebuild(trackingName, context: context);
  }
}

/// A wrapper widget that automatically tracks rebuilds of its child
class RebuildTracker extends StatelessWidget {
  const RebuildTracker({
    super.key,
    required this.child,
    this.name,
    this.context,
  });

  final Widget child;
  final String? name;
  final Map<String, dynamic>? context;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      final trackingName = name ?? child.runtimeType.toString();
      WidgetRebuildTracker.instance.trackRebuild(
        trackingName, 
        context: this.context,
      );
    }
    return child;
  }
}

/// Extension on BuildContext to easily track rebuilds
extension RebuildTrackingExtension on BuildContext {
  /// Track a rebuild for the current widget
  void trackRebuild([String? name, Map<String, dynamic>? context]) {
    if (!kDebugMode) return;
    
    final trackingName = name ?? widget.runtimeType.toString();
    WidgetRebuildTracker.instance.trackRebuild(trackingName, context: context);
  }
}

/// A StatefulWidget that automatically tracks its rebuilds
abstract class TrackingStatefulWidget extends StatefulWidget {
  const TrackingStatefulWidget({super.key});
  
  /// Widget name for tracking (defaults to runtimeType)
  String get trackingName => runtimeType.toString();
  
  /// Whether to track this widget's rebuilds
  bool get shouldTrack => kDebugMode;
}

/// A State class that automatically tracks rebuilds
abstract class TrackingState<T extends TrackingStatefulWidget> extends State<T> {
  void _trackRebuild() {
    if (!widget.shouldTrack) return;
    WidgetRebuildTracker.instance.trackRebuild(widget.trackingName);
  }

  @override
  Widget build(BuildContext context) {
    _trackRebuild();
    return buildWithTracking(context);
  }
  
  /// Override this method instead of build() to get automatic rebuild tracking
  Widget buildWithTracking(BuildContext context);
}

/// A StatelessWidget that automatically tracks its rebuilds
abstract class TrackingStatelessWidget extends StatelessWidget {
  const TrackingStatelessWidget({super.key});
  
  /// Widget name for tracking (defaults to runtimeType)
  String get trackingName => runtimeType.toString();
  
  /// Whether to track this widget's rebuilds
  bool get shouldTrack => kDebugMode;

  void _trackRebuild() {
    if (!shouldTrack) return;
    WidgetRebuildTracker.instance.trackRebuild(trackingName);
  }

  @override
  Widget build(BuildContext context) {
    _trackRebuild();
    return buildWithTracking(context);
  }
  
  /// Override this method instead of build() to get automatic rebuild tracking
  Widget buildWithTracking(BuildContext context);
}

/// Performance instrumentation widget
/// Wraps a widget to track various performance metrics
class PerformanceInstrument extends StatefulWidget {
  const PerformanceInstrument({
    super.key,
    required this.child,
    required this.name,
    this.trackMemory = false,
    this.trackFrameTime = false,
    this.trackRebuild = true,
  });

  final Widget child;
  final String name;
  final bool trackMemory;
  final bool trackFrameTime;
  final bool trackRebuild;

  @override
  State<PerformanceInstrument> createState() => _PerformanceInstrumentState();
}

class _PerformanceInstrumentState extends State<PerformanceInstrument> {
  late final Stopwatch _buildStopwatch;
  
  @override
  void initState() {
    super.initState();
    _buildStopwatch = Stopwatch();
    
    if (widget.trackMemory && kDebugMode) {
      // Record memory usage
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentMemory = MemoryMonitor.instance.currentMemoryMB;
        if (currentMemory != null) {
          PerformanceProfiler.instance.recordMetric(PerformanceMetric(
            category: PerformanceCategory.widgetRebuild,
            name: '${widget.name}_memory',
            value: currentMemory,
            unit: 'MB',
            timestamp: DateTime.now(),
            context: {'widget_name': widget.name},
          ));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.child;
    
    _buildStopwatch.reset();
    _buildStopwatch.start();
    
    // Track rebuild
    if (widget.trackRebuild) {
      WidgetRebuildTracker.instance.trackRebuild(widget.name);
    }
    
    final child = widget.child;
    
    _buildStopwatch.stop();
    
    // Track build time
    if (widget.trackFrameTime) {
      PerformanceProfiler.instance.recordMetric(PerformanceMetric(
        category: PerformanceCategory.widgetRebuild,
        name: '${widget.name}_build_time',
        value: _buildStopwatch.elapsedMicroseconds / 1000.0,
        unit: 'ms',
        timestamp: DateTime.now(),
        context: {'widget_name': widget.name},
      ));
    }
    
    return child;
  }
}

/// Performance monitoring utilities
class PerformanceUtils {
  /// Measure the execution time of a function
  static Future<T> measureAsync<T>(
    String operationName,
    Future<T> Function() operation, {
    PerformanceCategory category = PerformanceCategory.network,
    Map<String, dynamic>? context,
  }) async {
    if (!kDebugMode) return await operation();
    
    final stopwatch = Stopwatch()..start();
    try {
      final result = await operation();
      stopwatch.stop();
      
      PerformanceProfiler.instance.recordMetric(PerformanceMetric(
        category: category,
        name: operationName,
        value: stopwatch.elapsedMilliseconds.toDouble(),
        unit: 'ms',
        timestamp: DateTime.now(),
        context: context ?? {},
      ));
      
      return result;
    } catch (e) {
      stopwatch.stop();
      
      PerformanceProfiler.instance.recordMetric(PerformanceMetric(
        category: category,
        name: '${operationName}_error',
        value: stopwatch.elapsedMilliseconds.toDouble(),
        unit: 'ms',
        timestamp: DateTime.now(),
        context: {
          'error': e.toString(),
          ...?context,
        },
      ));
      
      rethrow;
    }
  }

  /// Measure the execution time of a synchronous function
  static T measureSync<T>(
    String operationName,
    T Function() operation, {
    PerformanceCategory category = PerformanceCategory.network,
    Map<String, dynamic>? context,
  }) {
    if (!kDebugMode) return operation();
    
    final stopwatch = Stopwatch()..start();
    try {
      final result = operation();
      stopwatch.stop();
      
      PerformanceProfiler.instance.recordMetric(PerformanceMetric(
        category: category,
        name: operationName,
        value: stopwatch.elapsedMilliseconds.toDouble(),
        unit: 'ms',
        timestamp: DateTime.now(),
        context: context ?? {},
      ));
      
      return result;
    } catch (e) {
      stopwatch.stop();
      
      PerformanceProfiler.instance.recordMetric(PerformanceMetric(
        category: category,
        name: '${operationName}_error',
        value: stopwatch.elapsedMilliseconds.toDouble(),
        unit: 'ms',
        timestamp: DateTime.now(),
        context: {
          'error': e.toString(),
          ...?context,
        },
      ));
      
      rethrow;
    }
  }

  /// Record a custom performance metric
  static void recordMetric({
    required String name,
    required double value,
    required String unit,
    PerformanceCategory category = PerformanceCategory.network,
    Map<String, dynamic>? context,
  }) {
    if (!kDebugMode) return;
    
    PerformanceProfiler.instance.recordMetric(PerformanceMetric(
      category: category,
      name: name,
      value: value,
      unit: unit,
      timestamp: DateTime.now(),
      context: context ?? {},
    ));
  }

  /// Record a sync operation performance metric
  static void recordSyncOperation({
    required String operationName,
    required Duration duration,
    bool success = true,
    String? errorMessage,
    Map<String, dynamic>? context,
  }) {
    if (!kDebugMode) return;
    
    PerformanceProfiler.instance.recordMetric(PerformanceMetric(
      category: PerformanceCategory.syncOperation,
      name: operationName,
      value: duration.inMilliseconds.toDouble(),
      unit: 'ms',
      timestamp: DateTime.now(),
      context: {
        'success': success,
        'error_message': errorMessage,
        ...?context,
      },
    ));
  }

  /// Record a database operation performance metric
  static void recordDatabaseOperation({
    required String operationName,
    required Duration duration,
    int? recordCount,
    bool success = true,
    String? errorMessage,
    Map<String, dynamic>? context,
  }) {
    if (!kDebugMode) return;
    
    PerformanceProfiler.instance.recordMetric(PerformanceMetric(
      category: PerformanceCategory.database,
      name: operationName,
      value: duration.inMilliseconds.toDouble(),
      unit: 'ms',
      timestamp: DateTime.now(),
      context: {
        'success': success,
        'record_count': recordCount,
        'error_message': errorMessage,
        ...?context,
      },
    ));
  }

  /// Record a navigation operation performance metric
  static void recordNavigation({
    required String routeName,
    required Duration duration,
    String? fromRoute,
    Map<String, dynamic>? context,
  }) {
    if (!kDebugMode) return;
    
    PerformanceProfiler.instance.recordMetric(PerformanceMetric(
      category: PerformanceCategory.navigation,
      name: 'navigation',
      value: duration.inMilliseconds.toDouble(),
      unit: 'ms',
      timestamp: DateTime.now(),
      context: {
        'route_name': routeName,
        'from_route': fromRoute,
        ...?context,
      },
    ));
  }
}