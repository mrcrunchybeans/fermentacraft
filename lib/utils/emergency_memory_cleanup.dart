// Emergency memory cleanup utility
// Call this from the Performance Dashboard when memory is critically high

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/firestore_sync_service.dart';
import '../services/memory_optimization_service.dart';
import 'performance_profiler.dart';

/// Emergency memory cleanup that can reduce memory usage dramatically
class EmergencyMemoryCleanup {
  static Future<void> performEmergencyCleanup() async {
    if (kDebugMode) {
      print('[EMERGENCY] 🚨 Starting aggressive memory cleanup...');
    }
    
    int initialMemory = 0;
    try {
      final processInfo = ProcessInfo.currentRss;
      initialMemory = (processInfo / 1024 / 1024).round();
      if (kDebugMode) print('[EMERGENCY] Initial memory: ${initialMemory}MB');
    } catch (e) {
      if (kDebugMode) print('[EMERGENCY] Could not read initial memory: $e');
    }

    // 1. Force memory optimization service cleanup
    MemoryOptimizationService.instance.forceCleanup();
    
    // 2. Disable and clear all performance monitoring
    final profiler = PerformanceProfiler.instance;
    profiler.stopMonitoring();  // Use correct method name
    profiler.clearMetrics();
    
    FrameTimingMonitor.instance.clearFrameHistory();
    MemoryMonitor.instance.stopMonitoring();
    WidgetRebuildTracker.instance.reset();
    
    // 3. Temporarily disable sync to prevent memory buildup
    // 4. Clear sync service (use public methods only)
    final sync = FirestoreSyncService.instance;
    final wasEnabled = sync.isEnabled;
    if (wasEnabled) {
      sync.disable();
      if (kDebugMode) print('[EMERGENCY] Temporarily disabled sync');
    }
    
    // 5. Force garbage collection multiple times
    for (int i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      // Force GC by creating and discarding large objects
      List<int> temp = List.filled(10000, 0);
      temp.clear();
    }
    
    // 6. Give system time to clean up
    await Future.delayed(const Duration(seconds: 2));
    
    // 7. Re-enable sync if it was enabled
    if (wasEnabled) {
      sync.enable();
      if (kDebugMode) print('[EMERGENCY] Re-enabled sync');
    }
    
    // 8. Check final memory
    try {
      final processInfo = ProcessInfo.currentRss;
      final finalMemory = (processInfo / 1024 / 1024).round();
      final saved = initialMemory - finalMemory;
      if (kDebugMode) {
        print('[EMERGENCY] Final memory: ${finalMemory}MB');
        print('[EMERGENCY] Memory saved: ${saved}MB');
        print('[EMERGENCY] 🎉 Emergency cleanup completed');
      }
    } catch (e) {
      if (kDebugMode) print('[EMERGENCY] Could not read final memory: $e');
    }
  }
}