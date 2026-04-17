/// Comprehensive performance monitoring and profiling system
/// Tracks frame rates, memory usage, widget rebuilds, and sync performance
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'app_logger.dart';

/// Performance metric categories
enum PerformanceCategory {
  frameRate,
  memory,
  widgetRebuild,
  syncOperation,
  navigation,
  database,
  network,
}

/// Individual performance metric data point
class PerformanceMetric {
  const PerformanceMetric({
    required this.category,
    required this.name,
    required this.value,
    required this.unit,
    required this.timestamp,
    this.context = const {},
  });

  final PerformanceCategory category;
  final String name;
  final double value;
  final String unit;
  final DateTime timestamp;
  final Map<String, dynamic> context;

  Map<String, dynamic> toJson() => {
    'category': category.name,
    'name': name,
    'value': value,
    'unit': unit,
    'timestamp': timestamp.toIso8601String(),
    'context': context,
  };
}

/// Aggregated performance statistics
class PerformanceStats {
  const PerformanceStats({
    required this.mean,
    required this.min,
    required this.max,
    required this.p50,
    required this.p95,
    required this.p99,
    required this.count,
  });

  final double mean;
  final double min;
  final double max;
  final double p50;
  final double p95;
  final double p99;
  final int count;

  factory PerformanceStats.fromValues(List<double> values) {
    if (values.isEmpty) {
      return const PerformanceStats(
        mean: 0, min: 0, max: 0, p50: 0, p95: 0, p99: 0, count: 0,
      );
    }

    final sorted = List<double>.from(values)..sort();
    final count = sorted.length;
    final sum = sorted.reduce((a, b) => a + b);
    
    return PerformanceStats(
      mean: sum / count,
      min: sorted.first,
      max: sorted.last,
      p50: _percentile(sorted, 0.5),
      p95: _percentile(sorted, 0.95),
      p99: _percentile(sorted, 0.99),
      count: count,
    );
  }

  static double _percentile(List<double> sorted, double percentile) {
    final index = (sorted.length * percentile).round() - 1;
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  Map<String, dynamic> toJson() => {
    'mean': mean,
    'min': min,
    'max': max,
    'p50': p50,
    'p95': p95,
    'p99': p99,
    'count': count,
  };
}

/// Performance baseline for comparison
class PerformanceBaseline {
  const PerformanceBaseline({
    required this.name,
    required this.category,
    required this.expectedValue,
    required this.tolerance,
    required this.unit,
  });

  final String name;
  final PerformanceCategory category;
  final double expectedValue;
  final double tolerance; // Percentage tolerance (e.g., 0.1 = 10%)
  final String unit;

  bool isWithinTolerance(double actualValue) {
    final delta = (actualValue - expectedValue).abs();
    final maxDelta = expectedValue * tolerance;
    return delta <= maxDelta;
  }

  double getDeviationPercentage(double actualValue) {
    return ((actualValue - expectedValue) / expectedValue) * 100;
  }
}

/// Frame timing monitor using Flutter's SchedulerBinding
class FrameTimingMonitor {
  FrameTimingMonitor._();
  static final FrameTimingMonitor instance = FrameTimingMonitor._();

  final List<Duration> _frameTimes = [];
  final int _maxFrameHistory = 20; // Further reduced to save memory
  bool _isMonitoring = false;
  Timer? _reportTimer;

  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;

    SchedulerBinding.instance.addTimingsCallback(_onFrameTiming);
    
    // Report frame performance less frequently to save resources
    _reportTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _reportFramePerformance();
    });
  }

  void stopMonitoring() {
    if (!_isMonitoring) return;
    _isMonitoring = false;

    SchedulerBinding.instance.removeTimingsCallback(_onFrameTiming);
    _reportTimer?.cancel();
    _reportTimer = null;
  }

  void _onFrameTiming(List<FrameTiming> timings) {
    for (final timing in timings) {
      final frameDuration = timing.totalSpan;
      _frameTimes.add(frameDuration);
      
      // Keep only recent frames
      if (_frameTimes.length > _maxFrameHistory) {
        _frameTimes.removeAt(0);
      }

      // Track jank frames (>16.67ms for 60fps)
      if (frameDuration.inMicroseconds > 16670) {
        PerformanceProfiler.instance.recordMetric(PerformanceMetric(
          category: PerformanceCategory.frameRate,
          name: 'jank_frame',
          value: frameDuration.inMicroseconds / 1000.0,
          unit: 'ms',
          timestamp: DateTime.now(),
          context: {
            'build_duration_ms': timing.buildDuration.inMicroseconds / 1000.0,
            'raster_duration_ms': timing.rasterDuration.inMicroseconds / 1000.0,
          },
        ));
      }
    }
  }

  void _reportFramePerformance() {
    if (_frameTimes.isEmpty) return;

    final frameTimesMs = _frameTimes
        .map((d) => d.inMicroseconds / 1000.0)
        .toList();

    final stats = PerformanceStats.fromValues(frameTimesMs);

    PerformanceProfiler.instance.recordMetric(PerformanceMetric(
      category: PerformanceCategory.frameRate,
      name: 'frame_time_summary',
      value: stats.mean,
      unit: 'ms',
      timestamp: DateTime.now(),
      context: {
        'fps_avg': 1000.0 / stats.mean,
        'fps_p99': 1000.0 / stats.p99,
        'jank_frames': _frameTimes.where((d) => d.inMicroseconds > 16670).length,
        'total_frames': stats.count,
        'stats': stats.toJson(),
      },
    ));
  }

  PerformanceStats? get currentFrameStats {
    if (_frameTimes.isEmpty) return null;
    
    final frameTimesMs = _frameTimes
        .map((d) => d.inMicroseconds / 1000.0)
        .toList();
    
    return PerformanceStats.fromValues(frameTimesMs);
  }

  /// Clear frame timing history to free memory
  void clearFrameHistory() {
    _frameTimes.clear();
  }
}

/// Memory usage monitor
class MemoryMonitor {
  MemoryMonitor._();
  static final MemoryMonitor instance = MemoryMonitor._();

  Timer? _monitorTimer;
  int _lastRssBytes = 0;

  void startMonitoring() {
    _monitorTimer?.cancel();
    
    // Reduced frequency to save resources
    _monitorTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _recordMemoryUsage();
    });

    // Initial measurement
    _recordMemoryUsage();
  }

  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  void _recordMemoryUsage() {
    try {
      final info = ProcessInfo.currentRss;
      final memoryMB = info / (1024 * 1024);

      PerformanceProfiler.instance.recordMetric(PerformanceMetric(
        category: PerformanceCategory.memory,
        name: 'rss_memory',
        value: memoryMB,
        unit: 'MB',
        timestamp: DateTime.now(),
        context: {
          'rss_bytes': info,
          'memory_delta_mb': _lastRssBytes > 0 ? (info - _lastRssBytes) / (1024 * 1024) : 0,
        },
      ));

      _lastRssBytes = info;
    } catch (e) {
      // Memory monitoring not available on this platform
      if (kDebugMode) {
        print('Memory monitoring unavailable: $e');
      }
    }
  }

  double? get currentMemoryMB {
    try {
      return ProcessInfo.currentRss / (1024 * 1024);
    } catch (e) {
      return null;
    }
  }
}

/// Widget rebuild tracking
class WidgetRebuildTracker {
  WidgetRebuildTracker._();
  static final WidgetRebuildTracker instance = WidgetRebuildTracker._();

  final Map<String, int> _rebuildCounts = {};
  final Map<String, DateTime> _lastRebuild = {};

  void trackRebuild(String widgetName, {Map<String, dynamic>? context}) {
    final now = DateTime.now();
    _rebuildCounts[widgetName] = (_rebuildCounts[widgetName] ?? 0) + 1;
    _lastRebuild[widgetName] = now;

    PerformanceProfiler.instance.recordMetric(PerformanceMetric(
      category: PerformanceCategory.widgetRebuild,
      name: 'widget_rebuild',
      value: _rebuildCounts[widgetName]!.toDouble(),
      unit: 'count',
      timestamp: now,
      context: {
        'widget_name': widgetName,
        'total_rebuilds': _rebuildCounts[widgetName],
        ...?context,
      },
    ));
  }

  Map<String, int> get rebuildCounts => Map.unmodifiable(_rebuildCounts);

  void reset() {
    _rebuildCounts.clear();
    _lastRebuild.clear();
  }
}

/// Main performance profiler service
class PerformanceProfiler {
  PerformanceProfiler._();
  static final PerformanceProfiler instance = PerformanceProfiler._();

  final List<PerformanceMetric> _metrics = [];
  final int _maxMetrics = 50; // Further reduced to save memory
  bool _isEnabled = false; // Disabled by default to save memory
  
  // Performance baselines for validation
  final List<PerformanceBaseline> _baselines = [
    const PerformanceBaseline(
      name: 'Average Frame Time',
      category: PerformanceCategory.frameRate,
      expectedValue: 16.67, // 60fps target
      tolerance: 0.2, // 20% tolerance
      unit: 'ms',
    ),
    const PerformanceBaseline(
      name: 'Memory Usage',
      category: PerformanceCategory.memory,
      expectedValue: 150.0, // 150MB baseline
      tolerance: 0.5, // 50% tolerance
      unit: 'MB',
    ),
    const PerformanceBaseline(
      name: 'Sync Operation Duration',
      category: PerformanceCategory.syncOperation,
      expectedValue: 500.0, // 500ms baseline
      tolerance: 1.0, // 100% tolerance
      unit: 'ms',
    ),
  ];

  bool get isEnabled => _isEnabled;
  
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    
    if (enabled) {
      startMonitoring();
    } else {
      stopMonitoring();
    }
  }

  void startMonitoring() {
    // Disabled by default to save memory - only enable when explicitly needed
    if (kDebugMode) print('Performance monitoring disabled for memory optimization');
    return;
  }

  void stopMonitoring() {
    FrameTimingMonitor.instance.stopMonitoring();
    MemoryMonitor.instance.stopMonitoring();
    
    AppLogger.instance.info(
      'Performance monitoring stopped',
      category: LogCategory.performance,
    );
  }

  void recordMetric(PerformanceMetric metric) {
    if (!_isEnabled) return;

    _metrics.add(metric);
    
    // Keep only recent metrics
    if (_metrics.length > _maxMetrics) {
      _metrics.removeAt(0);
    }

    // Log significant performance issues
    _checkForPerformanceIssues(metric);
  }

  void _checkForPerformanceIssues(PerformanceMetric metric) {
    // Check against baselines
    for (final baseline in _baselines) {
      if (baseline.category == metric.category && 
          baseline.name.toLowerCase().contains(metric.name.toLowerCase())) {
        
        if (!baseline.isWithinTolerance(metric.value)) {
          final deviation = baseline.getDeviationPercentage(metric.value);
          
          AppLogger.instance.warning(
            'Performance baseline exceeded: ${metric.name}',
            category: LogCategory.performance,
            details: {
              'actual_value': metric.value,
              'expected_value': baseline.expectedValue,
              'deviation_percent': deviation,
              'unit': metric.unit,
              'context': metric.context,
            },
          );
        }
        break;
      }
    }

    // Check for specific critical thresholds
    switch (metric.category) {
      case PerformanceCategory.frameRate:
        if (metric.name == 'jank_frame' && metric.value > 50.0) {
          AppLogger.instance.error(
            'Severe jank detected: ${metric.value}ms frame',
            category: LogCategory.performance,
            details: metric.context,
          );
        }
        break;
        
      case PerformanceCategory.memory:
        if (metric.name == 'rss_memory' && metric.value > 500.0) {
          AppLogger.instance.warning(
            'High memory usage: ${metric.value}MB',
            category: LogCategory.performance,
            details: metric.context,
          );
        }
        break;
        
      case PerformanceCategory.syncOperation:
        if (metric.value > 5000.0) { // 5 seconds
          AppLogger.instance.warning(
            'Slow sync operation: ${metric.name} took ${metric.value}ms',
            category: LogCategory.performance,
            details: metric.context,
          );
        }
        break;
        
      default:
        break;
    }
  }

  /// Get performance statistics for a specific category and metric
  PerformanceStats? getStats(PerformanceCategory category, String metricName) {
    final metrics = _metrics
        .where((m) => m.category == category && m.name == metricName)
        .map((m) => m.value)
        .toList();

    return metrics.isEmpty ? null : PerformanceStats.fromValues(metrics);
  }

  /// Get all metrics for a category
  List<PerformanceMetric> getMetrics(PerformanceCategory category) {
    return _metrics.where((m) => m.category == category).toList();
  }

  /// Get current performance summary
  Map<String, dynamic> getPerformanceSummary() {
    final summary = <String, dynamic>{};
    
    // Frame timing
    final frameStats = FrameTimingMonitor.instance.currentFrameStats;
    if (frameStats != null) {
      summary['frame_timing'] = {
        'avg_fps': 1000.0 / frameStats.mean,
        'avg_frame_time_ms': frameStats.mean,
        'p99_frame_time_ms': frameStats.p99,
        'jank_percentage': frameStats.count > 0 
          ? (_metrics.where((m) => m.category == PerformanceCategory.frameRate && m.name == 'jank_frame').length / frameStats.count * 100)
          : 0.0,
      };
    }

    // Memory
    final currentMemory = MemoryMonitor.instance.currentMemoryMB;
    if (currentMemory != null) {
      summary['memory'] = {
        'current_mb': currentMemory,
        'baseline_mb': 150.0,
        'within_baseline': currentMemory < 300.0,
      };
    }

    // Widget rebuilds
    final rebuilds = WidgetRebuildTracker.instance.rebuildCounts;
    if (rebuilds.isNotEmpty) {
      summary['widget_rebuilds'] = {
        'total_widgets': rebuilds.length,
        'total_rebuilds': rebuilds.values.reduce((a, b) => a + b),
        'most_rebuilt_widget': rebuilds.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key,
        'max_rebuilds': rebuilds.values.reduce((a, b) => a > b ? a : b),
      };
    }

    // Recent metrics count
    summary['metrics'] = {
      'total_recorded': _metrics.length,
      'by_category': {
        for (final category in PerformanceCategory.values)
          category.name: _metrics.where((m) => m.category == category).length,
      },
    };

    summary['monitoring'] = {
      'enabled': _isEnabled,
      'started_at': DateTime.now().toIso8601String(), // This should be tracked properly
    };

    return summary;
  }

  /// Clear all recorded metrics
  void clearMetrics() {
    _metrics.clear();
    WidgetRebuildTracker.instance.reset();
    
    AppLogger.instance.info(
      'Performance metrics cleared',
      category: LogCategory.performance,
    );
  }

  /// Export performance data for analysis
  Map<String, dynamic> exportData() {
    return {
      'exported_at': DateTime.now().toIso8601String(),
      'enabled': _isEnabled,
      'baselines': _baselines.map((b) => {
        'name': b.name,
        'category': b.category.name,
        'expected_value': b.expectedValue,
        'tolerance': b.tolerance,
        'unit': b.unit,
      }).toList(),
      'metrics': _metrics.map((m) => m.toJson()).toList(),
      'summary': getPerformanceSummary(),
    };
  }
}