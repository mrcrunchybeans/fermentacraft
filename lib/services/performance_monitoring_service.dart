/// Performance monitoring integration service
/// Integrates performance monitoring with existing app services
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../utils/performance_profiler.dart';
import '../utils/performance_helpers.dart';
import '../utils/app_logger.dart';

/// Service to integrate performance monitoring with app lifecycle
class PerformanceMonitoringService {
  PerformanceMonitoringService._();
  static final PerformanceMonitoringService instance = PerformanceMonitoringService._();

  bool _isInitialized = false;
  Timer? _healthCheckTimer;

  /// Initialize performance monitoring
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    AppLogger.instance.info(
      'Initializing performance monitoring',
      category: LogCategory.performance,
    );
    
    // Start performance profiler
    PerformanceProfiler.instance.setEnabled(kDebugMode);
    
    // Start periodic health checks
    _startHealthChecks();
    
    // Record app startup time
    _recordStartupMetric();
    
    _isInitialized = true;
    
    AppLogger.instance.info(
      'Performance monitoring initialized',
      category: LogCategory.performance,
      details: {
        'enabled': PerformanceProfiler.instance.isEnabled,
        'debug_mode': kDebugMode,
      },
    );
  }

  /// Enable or disable performance monitoring
  void setEnabled(bool enabled) {
    PerformanceProfiler.instance.setEnabled(enabled);
    
    if (enabled && !_isHealthCheckRunning) {
      _startHealthChecks();
    } else if (!enabled && _isHealthCheckRunning) {
      _stopHealthChecks();
    }
    
    AppLogger.instance.info(
      'Performance monitoring ${enabled ? 'enabled' : 'disabled'}',
      category: LogCategory.performance,
    );
  }

  /// Check if monitoring is enabled
  bool get isEnabled => PerformanceProfiler.instance.isEnabled;

  /// Check if health checks are running
  bool get _isHealthCheckRunning => _healthCheckTimer != null;

  /// Start periodic performance health checks
  void _startHealthChecks() {
    _healthCheckTimer?.cancel();
    
    // Reduced frequency to save resources
    _healthCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _performHealthCheck();
    });
  }

  /// Stop periodic health checks
  void _stopHealthChecks() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  /// Perform a health check and log issues
  void _performHealthCheck() {
    final summary = PerformanceProfiler.instance.getPerformanceSummary();
    
    // Check frame performance
    if (summary.containsKey('frame_timing')) {
      final frame = summary['frame_timing'] as Map<String, dynamic>;
      final avgFps = frame['avg_fps'] as double? ?? 0.0;
      final jankPercentage = frame['jank_percentage'] as double? ?? 0.0;
      
      if (avgFps < 30) {
        AppLogger.instance.warning(
          'Low frame rate detected',
          category: LogCategory.performance,
          details: {
            'avg_fps': avgFps,
            'jank_percentage': jankPercentage,
          },
        );
      }
      
      if (jankPercentage > 20) {
        AppLogger.instance.warning(
          'High jank percentage detected',
          category: LogCategory.performance,
          details: {
            'avg_fps': avgFps,
            'jank_percentage': jankPercentage,
          },
        );
      }
    }
    
    // Check memory usage
    if (summary.containsKey('memory')) {
      final memory = summary['memory'] as Map<String, dynamic>;
      final currentMB = memory['current_mb'] as double? ?? 0.0;
      final withinBaseline = memory['within_baseline'] as bool? ?? true;
      
      if (!withinBaseline) {
        AppLogger.instance.warning(
          'Memory usage above baseline',
          category: LogCategory.performance,
          details: {
            'current_mb': currentMB,
            'baseline_mb': memory['baseline_mb'],
          },
        );
      }
    }
    
    // Check widget rebuild patterns
    if (summary.containsKey('widget_rebuilds')) {
      final rebuilds = summary['widget_rebuilds'] as Map<String, dynamic>;
      final totalRebuilds = rebuilds['total_rebuilds'] as int? ?? 0;
      final totalWidgets = rebuilds['total_widgets'] as int? ?? 1;
      final avgRebuilds = totalRebuilds / totalWidgets;
      
      if (avgRebuilds > 20) {
        AppLogger.instance.warning(
          'High widget rebuild rate detected',
          category: LogCategory.performance,
          details: {
            'avg_rebuilds_per_widget': avgRebuilds,
            'total_rebuilds': totalRebuilds,
            'total_widgets': totalWidgets,
            'most_rebuilt_widget': rebuilds['most_rebuilt_widget'],
          },
        );
      }
    }
  }

  /// Record app startup performance
  void _recordStartupMetric() {
    // This would typically measure from app start to UI ready
    // For now, we'll record that monitoring has started
    PerformanceUtils.recordMetric(
      name: 'monitoring_startup',
      value: DateTime.now().millisecondsSinceEpoch.toDouble(),
      unit: 'timestamp',
      category: PerformanceCategory.navigation,
      context: {
        'event': 'performance_monitoring_started',
      },
    );
  }

  /// Get current performance status
  Map<String, dynamic> getStatus() {
    return {
      'initialized': _isInitialized,
      'enabled': isEnabled,
      'health_checks_running': _isHealthCheckRunning,
      'profiler_status': PerformanceProfiler.instance.getPerformanceSummary(),
    };
  }

  /// Record sync operation performance
  void recordSyncOperation({
    required String operation,
    required Duration duration,
    bool success = true,
    String? errorMessage,
    Map<String, dynamic>? context,
  }) {
    PerformanceUtils.recordSyncOperation(
      operationName: operation,
      duration: duration,
      success: success,
      errorMessage: errorMessage,
      context: context,
    );
  }

  /// Record database operation performance
  void recordDatabaseOperation({
    required String operation,
    required Duration duration,
    int? recordCount,
    bool success = true,
    String? errorMessage,
    Map<String, dynamic>? context,
  }) {
    PerformanceUtils.recordDatabaseOperation(
      operationName: operation,
      duration: duration,
      recordCount: recordCount,
      success: success,
      errorMessage: errorMessage,
      context: context,
    );
  }

  /// Record navigation performance
  void recordNavigation({
    required String routeName,
    required Duration duration,
    String? fromRoute,
    Map<String, dynamic>? context,
  }) {
    PerformanceUtils.recordNavigation(
      routeName: routeName,
      duration: duration,
      fromRoute: fromRoute,
      context: context,
    );
  }

  /// Export performance data
  Map<String, dynamic> exportData() {
    return PerformanceProfiler.instance.exportData();
  }

  /// Clear all performance metrics
  void clearMetrics() {
    PerformanceProfiler.instance.clearMetrics();
    AppLogger.instance.info(
      'Performance metrics cleared',
      category: LogCategory.performance,
    );
  }

  /// Dispose of resources
  void dispose() {
    _stopHealthChecks();
    PerformanceProfiler.instance.stopMonitoring();
    _isInitialized = false;
    
    AppLogger.instance.info(
      'Performance monitoring disposed',
      category: LogCategory.performance,
    );
  }

  /// Run performance validation tests
  Future<Map<String, dynamic>> runValidationTests() async {
    AppLogger.instance.info(
      'Starting performance validation tests',
      category: LogCategory.performance,
    );

    final results = <String, dynamic>{};
    
    try {
      // Frame rate test
      results['frame_test'] = await _runFrameRateTest();
      
      // Memory test
      results['memory_test'] = await _runMemoryTest();
      
      // Widget rebuild test
      results['rebuild_test'] = await _runRebuildTest();
      
      results['overall_status'] = 'completed';
      results['timestamp'] = DateTime.now().toIso8601String();
      
      AppLogger.instance.info(
        'Performance validation tests completed',
        category: LogCategory.performance,
        details: results,
      );
      
    } catch (e) {
      results['overall_status'] = 'failed';
      results['error'] = e.toString();
      
      AppLogger.instance.error(
        'Performance validation tests failed',
        category: LogCategory.performance,
        details: results,
        error: e,
      );
    }
    
    return results;
  }

  /// Run frame rate validation test
  Future<Map<String, dynamic>> _runFrameRateTest() async {
    final results = <String, dynamic>{};
    
    // Record baseline frame stats
    final initialStats = FrameTimingMonitor.instance.currentFrameStats;
    results['initial_frame_stats'] = initialStats?.toJson();
    
    // Simulate load and measure frame impact
    final stopwatch = Stopwatch()..start();
    for (int i = 0; i < 60; i++) { // 1 second at 60fps
      await Future.delayed(const Duration(milliseconds: 16));
    }
    stopwatch.stop();
    
    results['test_duration_ms'] = stopwatch.elapsedMilliseconds;
    
    // Get final stats
    await Future.delayed(const Duration(milliseconds: 500)); // Let frames settle
    final finalStats = FrameTimingMonitor.instance.currentFrameStats;
    results['final_frame_stats'] = finalStats?.toJson();
    
    // Calculate results
    if (finalStats != null) {
      final avgFps = 1000.0 / finalStats.mean;
      results['avg_fps'] = avgFps;
      results['passed'] = avgFps >= 30; // 30fps minimum
      results['rating'] = avgFps >= 55 ? 'excellent' : 
                         avgFps >= 45 ? 'good' : 
                         avgFps >= 30 ? 'acceptable' : 'poor';
    } else {
      results['passed'] = false;
      results['error'] = 'No frame timing data available';
    }
    
    return results;
  }

  /// Run memory usage validation test
  Future<Map<String, dynamic>> _runMemoryTest() async {
    final results = <String, dynamic>{};
    
    final initialMemory = MemoryMonitor.instance.currentMemoryMB;
    results['initial_memory_mb'] = initialMemory;
    
    // Create temporary memory load
    final heavyData = <List<int>>[];
    try {
      for (int i = 0; i < 50; i++) {
        heavyData.add(List.filled(10000, i));
      }
      
      await Future.delayed(const Duration(milliseconds: 100));
      final peakMemory = MemoryMonitor.instance.currentMemoryMB;
      results['peak_memory_mb'] = peakMemory;
      
      // Clear load
      heavyData.clear();
      
      await Future.delayed(const Duration(milliseconds: 500));
      final finalMemory = MemoryMonitor.instance.currentMemoryMB;
      results['final_memory_mb'] = finalMemory;
      
      if (initialMemory != null && finalMemory != null) {
        final memoryIncrease = finalMemory - initialMemory;
        results['memory_increase_mb'] = memoryIncrease;
        results['passed'] = memoryIncrease < 50; // Less than 50MB increase
        results['rating'] = memoryIncrease < 10 ? 'excellent' :
                           memoryIncrease < 25 ? 'good' :
                           memoryIncrease < 50 ? 'acceptable' : 'poor';
      } else {
        results['passed'] = false;
        results['error'] = 'Memory monitoring not available';
      }
      
    } catch (e) {
      results['passed'] = false;
      results['error'] = e.toString();
    }
    
    return results;
  }

  /// Run widget rebuild validation test
  Future<Map<String, dynamic>> _runRebuildTest() async {
    final results = <String, dynamic>{};
    
    final initialRebuilds = Map<String, int>.from(
      WidgetRebuildTracker.instance.rebuildCounts
    );
    results['initial_rebuild_count'] = initialRebuilds.values.fold(0, (a, b) => a + b);
    
    // Simulate rebuilds
    for (int i = 0; i < 10; i++) {
      WidgetRebuildTracker.instance.trackRebuild('test_widget_$i');
    }
    
    await Future.delayed(const Duration(milliseconds: 100));
    
    final finalRebuilds = Map<String, int>.from(
      WidgetRebuildTracker.instance.rebuildCounts
    );
    results['final_rebuild_count'] = finalRebuilds.values.fold(0, (a, b) => a + b);
    
    final rebuildIncrease = results['final_rebuild_count'] - results['initial_rebuild_count'];
    results['rebuild_increase'] = rebuildIncrease;
    results['passed'] = rebuildIncrease >= 10; // Should have recorded our test rebuilds
    results['tracking_working'] = rebuildIncrease >= 10;
    
    return results;
  }
}