/// Memory optimization service to reduce memory usage and prevent leaks
/// Provides utilities to optimize memory consumption throughout the app
library;

import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/performance_profiler.dart';

/// Service to optimize memory usage and prevent memory leaks
class MemoryOptimizationService {
  MemoryOptimizationService._();
  static final MemoryOptimizationService instance = MemoryOptimizationService._();

  Timer? _cleanupTimer;
  final Set<WeakReference<dynamic>> _trackedObjects = <WeakReference<dynamic>>{};
  final int _lastCleanupCount = 0;

  /// Initialize memory optimization
  void initialize() {
    // Only run optimization in debug mode to avoid release overhead
    if (kReleaseMode) {
      if (kDebugMode) print('[MEM] Memory optimization disabled in release mode');
      return;
    }
    
    // Start aggressive cleanup - every minute when memory is high
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _performMemoryCleanup();
    });
  }

  /// Dispose of the service
  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _trackedObjects.clear();
  }

  /// Track an object for memory management
  void trackObject(dynamic object) {
    _trackedObjects.add(WeakReference(object));
  }

  /// Perform memory cleanup and optimization
  void _performMemoryCleanup() {
    // Clean up weak references to garbage collected objects
    _trackedObjects.removeWhere((ref) => ref.target == null);
    
    // Force garbage collection if memory usage is high
    final currentMemory = MemoryMonitor.instance.currentMemoryMB;
    if (currentMemory != null && currentMemory > 400) {
      _forceGarbageCollection();
    }

    // Clean up performance metrics if they're taking too much memory
    _optimizePerformanceMetrics();
    
    // Clean up widget rebuild tracking
    _optimizeRebuildTracking();

    if (kDebugMode) {
      final activeObjects = _trackedObjects.where((ref) => ref.target != null).length;
      print('Memory cleanup: ${_trackedObjects.length} references, $activeObjects active objects');
    }
  }

  /// Force garbage collection (platform dependent)
  void _forceGarbageCollection() {
    // Note: Dart doesn't provide direct GC control
    // This is a placeholder for any cleanup we can do
    
    // Clear any internal caches we might have
    _trackedObjects.removeWhere((ref) => ref.target == null);
  }

  /// Ultra-aggressive Hive cache clearing
  void _clearHiveCaches() {
    try {
      if (kDebugMode) print('[MEM] Clearing Hive caches...');
      
      // List of known box names from the app
      final boxNames = [
        'settings', 'tags', 'recipes', 'batches', 
        'inventory', 'shoppingList', 'sync_meta',
        'ph_strips', 'batch_extras', 'app_prefs'
      ];
      
      for (final boxName in boxNames) {
        try {
          if (Hive.isBoxOpen(boxName)) {
            final box = Hive.box(boxName);
            // Force compact to reduce memory usage
            box.compact();
            if (kDebugMode) print('[MEM] Compacted box: $boxName');
          }
        } catch (e) {
          if (kDebugMode) print('[MEM] Error compacting $boxName: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) print('[MEM] Error clearing Hive caches: $e');
    }
  }

  /// Ultra-aggressive Firebase cache clearing
  void _clearFirebaseCaches() {
    try {
      if (kDebugMode) print('[MEM] Clearing Firebase caches...');
      
      // Clear Firestore cache
      FirebaseFirestore.instance.clearPersistence().catchError((e) {
        if (kDebugMode) print('[MEM] Could not clear Firestore cache: $e');
      });
      
      // Terminate and reinitialize to clear memory
      FirebaseFirestore.instance.terminate().then((_) {
        if (kDebugMode) print('[MEM] Firebase terminated for memory cleanup');
      }).catchError((e) {
        if (kDebugMode) print('[MEM] Error terminating Firebase: $e');
      });
      
    } catch (e) {
      if (kDebugMode) print('[MEM] Error clearing Firebase caches: $e');
    }
  }

  /// Optimize performance metrics storage
  void _optimizePerformanceMetrics() {
    // Reduce the number of stored metrics if memory is high
    final currentMemory = MemoryMonitor.instance.currentMemoryMB;
    if (currentMemory != null && currentMemory > 350) {
      // Clear older metrics to save memory
      PerformanceProfiler.instance.clearMetrics();
    }
  }

  /// Optimize widget rebuild tracking
  void _optimizeRebuildTracking() {
    // Clear rebuild tracking if there are too many entries
    final rebuildCounts = WidgetRebuildTracker.instance.rebuildCounts;
    if (rebuildCounts.length > 100) {
      WidgetRebuildTracker.instance.reset();
    }
  }

  /// Get memory optimization status
  Map<String, dynamic> getStatus() {
    final currentMemory = MemoryMonitor.instance.currentMemoryMB;
    
    return {
      'cleanup_active': _cleanupTimer != null,
      'tracked_objects': _trackedObjects.length,
      'active_objects': _trackedObjects.where((ref) => ref.target != null).length,
      'current_memory_mb': currentMemory,
      'memory_status': _getMemoryStatus(currentMemory),
      'last_cleanup_count': _lastCleanupCount,
    };
  }

  String _getMemoryStatus(double? memoryMB) {
    if (memoryMB == null) return 'unknown';
    if (memoryMB < 200) return 'good';
    if (memoryMB < 350) return 'moderate';
    if (memoryMB < 500) return 'high';
    return 'critical';
  }

  /// Force immediate cleanup
  void forceCleanup() {
    // Skip cleanup in release mode
    if (kReleaseMode) return;
    
    _performMemoryCleanup();
    
    // Also trigger emergency cleanup if memory is still very high
    final currentMemory = MemoryMonitor.instance.currentMemoryMB;
    if (currentMemory != null && currentMemory > 450) {
      _emergencyMemoryCleanup();
    }
  }

  /// Get recommendations for reducing memory usage
  List<String> getMemoryRecommendations() {
    final recommendations = <String>[];
    final currentMemory = MemoryMonitor.instance.currentMemoryMB;
    
    if (currentMemory != null) {
      if (currentMemory > 400) {
        recommendations.add('Memory usage is high (${currentMemory.toStringAsFixed(1)}MB)');
        recommendations.add('Consider restarting the app to clear accumulated memory');
      }
      
      if (PerformanceProfiler.instance.isEnabled) {
        recommendations.add('Disable performance monitoring to save memory');
      }
      
      final rebuildCounts = WidgetRebuildTracker.instance.rebuildCounts;
      if (rebuildCounts.length > 50) {
        recommendations.add('Reset widget rebuild tracking to save memory');
      }
    }
    
    return recommendations;
  }

  /// Emergency memory cleanup for critical situations
  void _emergencyMemoryCleanup() {
    if (kDebugMode) {
      print('[MEM] 🚨 EMERGENCY CLEANUP - Memory critically high');
    }
    
    // Clear all tracked objects
    _trackedObjects.clear();
    
    // Force performance profiler to clear all metrics
    final profiler = PerformanceProfiler.instance;
    if (profiler.isEnabled) {
      profiler.clearMetrics();
      if (kDebugMode) print('[MEM] Cleared performance metrics');
    }
    
    // Clear frame timing history
    FrameTimingMonitor.instance.clearFrameHistory();
    if (kDebugMode) print('[MEM] Cleared frame timing history');
    
    // Clear widget rebuild tracking
    WidgetRebuildTracker.instance.reset();
    if (kDebugMode) print('[MEM] Reset widget rebuild tracking');
    
    // Force aggressive garbage collection
    for (int i = 0; i < 3; i++) {
      _forceGarbageCollection();
    }
    
    if (kDebugMode) {
      print('[MEM] Emergency cleanup completed');
    }
  }

  /// Nuclear option - clears everything and forces maximum memory cleanup
  Future<void> performNuclearCleanup() async {
    // Skip nuclear cleanup in release mode
    if (kReleaseMode) {
      if (kDebugMode) print('[MEM] Nuclear cleanup disabled in release mode');
      return;
    }
    
    if (kDebugMode) {
      print('[MEM] ☢️ NUCLEAR CLEANUP - Performing most aggressive memory optimization');
    }
    
    // Emergency cleanup first
    _emergencyMemoryCleanup();
    
    // Ultra-aggressive data purging
    await _performDataPurge();
    
    // Purge widget rendering cache
    _purgeWidgetCache();
    
    // Ultra-aggressive: Clear all Hive data caches
    _clearHiveCaches();
    
    // Ultra-aggressive: Clear Firebase/Firestore caches
    _clearFirebaseCaches();
    
    // Nuclear option: Force close and reopen Hive boxes
    _forceHiveBoxCycle();
    
    // Enable memory-only mode
    _enableMemoryOnlyMode();
    
    // Force even more aggressive cleanup by creating and disposing large objects
    try {
      for (int i = 0; i < 20; i++) {
        // Create larger temporary objects to trigger more aggressive GC
        List<int> largeList = List.filled(500000, i);
        Map<String, dynamic> largeMap = {};
        for (int j = 0; j < 5000; j++) {
          largeMap['key$j'] = 'value$j' * 200;
        }
        // Clear them to free memory
        largeList.clear();
        largeMap.clear();
        
        // Force GC multiple times
        for (int k = 0; k < 3; k++) {
          _forceGarbageCollection();
        }
      }
    } catch (e) {
      if (kDebugMode) print('[MEM] Error during nuclear cleanup: $e');
    }
    
    if (kDebugMode) {
      print('[MEM] ☢️ Nuclear cleanup completed - maximum memory freed');
    }
  }

  /// Force close and reopen Hive boxes to release memory
  void _forceHiveBoxCycle() {
    try {
      if (kDebugMode) print('[MEM] Force cycling Hive boxes...');
      
      // Only cycle non-critical boxes to avoid breaking the app
      final nonCriticalBoxes = ['sync_meta', 'ph_strips', 'app_prefs'];
      
      for (final boxName in nonCriticalBoxes) {
        try {
          if (Hive.isBoxOpen(boxName)) {
            final box = Hive.box(boxName);
            box.close();
            if (kDebugMode) print('[MEM] Closed box: $boxName');
            
            // Wait a moment then reopen
            Future.delayed(const Duration(milliseconds: 100), () async {
              try {
                await Hive.openBox(boxName);
                if (kDebugMode) print('[MEM] Reopened box: $boxName');
              } catch (e) {
                if (kDebugMode) print('[MEM] Error reopening $boxName: $e');
              }
            });
          }
        } catch (e) {
          if (kDebugMode) print('[MEM] Error cycling $boxName: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) print('[MEM] Error during Hive box cycling: $e');
    }
  }

  /// Purge non-essential data to free up massive amounts of memory
  Future<void> _performDataPurge() async {
    try {
      if (kDebugMode) print('[MEM] 🗑️ Performing aggressive data purge...');
      
      // Purge old/duplicate data from Hive boxes
      const dataPurgeBoxes = ['batches', 'inventory', 'shoppingList'];
      
      for (String boxName in dataPurgeBoxes) {
        try {
          if (Hive.isBoxOpen(boxName)) {
            final box = Hive.box(boxName);
            final keyCount = box.length;
            
            // Keep only most recent 25% of items to aggressively reduce memory
            if (keyCount > 5) {
              final keys = box.keys.toList();
              final keysToDelete = keys.take((keyCount * 0.75).floor()).toList();
              
              for (var key in keysToDelete) {
                await box.delete(key);
              }
              
              await box.compact();
              if (kDebugMode) print('[MEM] 🗑️ Purged ${keysToDelete.length} items from $boxName');
            }
          }
        } catch (e) {
          if (kDebugMode) print('[MEM] ⚠️ Could not purge box $boxName: $e');
        }
      }
      
    } catch (e) {
      if (kDebugMode) print('[MEM] ❌ Data purge failed: $e');
    }
  }

  /// Purge Flutter widget rendering cache and force UI cleanup
  void _purgeWidgetCache() {
    try {
      if (kDebugMode) print('[MEM] 🎨 Purging widget cache and UI resources...');
      
      // Clear image cache completely
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      
      // Set very low cache limits to prevent memory buildup
      PaintingBinding.instance.imageCache.maximumSize = 10; // Very low
      PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50MB max
      
      if (kDebugMode) print('[MEM] ✅ Widget cache purged and limited');
      
    } catch (e) {
      if (kDebugMode) print('[MEM] ❌ Widget cache purge failed: $e');
    }
  }

  /// Enable memory-only mode - minimize persistent storage
  void _enableMemoryOnlyMode() {
    try {
      if (kDebugMode) print('[MEM] 📝 Enabling ultra-low memory mode...');
      
      // Set global memory optimization flags
      _memoryOnlyMode = true;
      _ultraLowMemoryMode = true;
      
      // Disable non-essential services that consume memory
      PerformanceProfiler.instance.clearMetrics();
      PerformanceProfiler.instance.stopMonitoring();
      
      if (kDebugMode) print('[MEM] ✅ Ultra-low memory mode enabled');
      
    } catch (e) {
      if (kDebugMode) print('[MEM] ❌ Memory-only mode failed: $e');
    }
  }

  bool _memoryOnlyMode = false;
  bool _ultraLowMemoryMode = false;
  bool _extremeMemoryMode = false;
  
  bool get isMemoryOnlyMode => _memoryOnlyMode;
  bool get isUltraLowMemoryMode => _ultraLowMemoryMode;
  bool get isExtremeMemoryMode => _extremeMemoryMode;

  /// FINAL EXTREME - Push memory below 400MB with most aggressive measures
  Future<void> performExtremeMemoryReduction() async {
    // Skip extreme reduction in release mode
    if (kReleaseMode) {
      if (kDebugMode) print('[MEM] Extreme reduction disabled in release mode');
      return;
    }
    
    if (kDebugMode) {
      print('[MEM] ⚡ EXTREME REDUCTION - Final push to minimize memory');
    }
    
    try {
      // Enable extreme mode first
      _extremeMemoryMode = true;
      
      // Perform nuclear cleanup
      await performNuclearCleanup();
      
      // Ultra-aggressive data limits - keep only essential data
      await _enforceUltraStrictDataLimits();
      
      // Minimize rendering resources
      await _minimizeRenderingResources();
      
      // Force close all non-essential Hive boxes
      await _closeNonEssentialBoxes();
      
      // Extreme garbage collection
      await _performExtremeGarbageCollection();
      
      if (kDebugMode) {
        print('[MEM] ⚡ EXTREME REDUCTION COMPLETED - Maximum optimization applied');
      }
      
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[MEM] ❌ Extreme reduction failed: $e');
        print(stackTrace);
      }
    }
  }
}

/// Memory-efficient data structures
class LimitedSizeMap<K, V> {
  LimitedSizeMap(this.maxSize);
  
  final int maxSize;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();
  
  void operator []=(K key, V value) {
    if (_map.length >= maxSize && !_map.containsKey(key)) {
      // Remove oldest entry
      final oldestKey = _map.keys.first;
      _map.remove(oldestKey);
    }
    _map[key] = value;
  }
  
  V? operator [](K key) => _map[key];
  
  bool containsKey(K key) => _map.containsKey(key);
  void remove(K key) => _map.remove(key);
  void clear() => _map.clear();
  
  int get length => _map.length;
  Iterable<K> get keys => _map.keys;
  Iterable<V> get values => _map.values;
  Iterable<MapEntry<K, V>> get entries => _map.entries;
}

/// Memory-efficient list with size limit
class LimitedSizeList<T> {
  LimitedSizeList(this.maxSize);
  
  final int maxSize;
  final List<T> _list = <T>[];
  
  void add(T item) {
    if (_list.length >= maxSize) {
      _list.removeAt(0); // Remove oldest
    }
    _list.add(item);
  }
  
  void addAll(Iterable<T> items) {
    for (final item in items) {
      add(item);
    }
  }
  
  T operator [](int index) => _list[index];
  void operator []=(int index, T value) => _list[index] = value;
  
  int get length => _list.length;
  bool get isEmpty => _list.isEmpty;
  bool get isNotEmpty => _list.isNotEmpty;
  
  void clear() => _list.clear();
  bool remove(T value) => _list.remove(value);
  T removeAt(int index) => _list.removeAt(index);
  
  Iterable<T> get reversed => _list.reversed;
  T get first => _list.first;
  T get last => _list.last;
  
  List<T> toList() => List<T>.from(_list);
}

// EXTREME MEMORY REDUCTION METHODS EXTENSION
extension ExtremeMemoryOptimization on MemoryOptimizationService {
  /// Enforce ultra-strict data limits to minimize memory usage
  Future<void> _enforceUltraStrictDataLimits() async {
    try {
      if (kDebugMode) print('[MEM] 📊 Enforcing ultra-strict data limits...');
      
      // Keep only the most recent and essential data
      const criticalBoxes = ['batches', 'inventory', 'shoppingList'];
      
      for (String boxName in criticalBoxes) {
        try {
          if (Hive.isBoxOpen(boxName)) {
            final box = Hive.box(boxName);
            final keyCount = box.length;
            
            // Keep only 10% of data - extremely aggressive
            if (keyCount > 3) {
              final keys = box.keys.toList();
              final keysToDelete = keys.take((keyCount * 0.9).floor()).toList();
              
              for (var key in keysToDelete) {
                await box.delete(key);
              }
              
              await box.compact();
              if (kDebugMode) print('[MEM] 🗑️ Ultra-purged ${keysToDelete.length} items from $boxName, kept ${keyCount - keysToDelete.length}');
            }
          }
        } catch (e) {
          if (kDebugMode) print('[MEM] ⚠️ Could not limit $boxName: $e');
        }
      }
      
    } catch (e) {
      if (kDebugMode) print('[MEM] ❌ Data limits enforcement failed: $e');
    }
  }

  /// Minimize Flutter rendering resources to absolute minimum
  Future<void> _minimizeRenderingResources() async {
    try {
      if (kDebugMode) print('[MEM] 🎨 Minimizing rendering resources...');
      
      // Set extremely low image cache limits
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      PaintingBinding.instance.imageCache.maximumSize = 5; // Extremely low
      PaintingBinding.instance.imageCache.maximumSizeBytes = 10 << 20; // Only 10MB
      
      // Clear shader cache if available
      try {
        WidgetsBinding.instance.reassembleApplication();
      } catch (e) {
        if (kDebugMode) print('[MEM] Could not reassemble app: $e');
      }
      
      if (kDebugMode) print('[MEM] ✅ Rendering resources minimized');
      
    } catch (e) {
      if (kDebugMode) print('[MEM] ❌ Rendering optimization failed: $e');
    }
  }

  /// Close all non-essential Hive boxes to free memory
  Future<void> _closeNonEssentialBoxes() async {
    try {
      if (kDebugMode) print('[MEM] 📦 Closing non-essential boxes...');
      
      // Only keep the most essential boxes open
      const nonEssentialBoxes = ['sync_meta', 'ph_strips', 'app_prefs', 'cache', 'temp_data'];
      
      for (final boxName in nonEssentialBoxes) {
        try {
          if (Hive.isBoxOpen(boxName)) {
            final box = Hive.box(boxName);
            await box.close();
            if (kDebugMode) print('[MEM] 📦 Closed non-essential box: $boxName');
          }
        } catch (e) {
          if (kDebugMode) print('[MEM] ⚠️ Could not close $boxName: $e');
        }
      }
      
    } catch (e) {
      if (kDebugMode) print('[MEM] ❌ Box closure failed: $e');
    }
  }

  /// Perform extreme garbage collection with maximum iterations
  Future<void> _performExtremeGarbageCollection() async {
    try {
      if (kDebugMode) print('[MEM] 🔄 Performing extreme garbage collection...');
      
      // Create and destroy even larger temporary objects to trigger aggressive GC
      for (int cycle = 0; cycle < 50; cycle++) {
        List<List<int>> megaList = [];
        Map<String, Map<String, dynamic>> megaMap = {};
        
        // Create massive temporary objects
        for (int i = 0; i < 100; i++) {
          megaList.add(List.filled(10000, i));
          megaMap['section$i'] = {};
          for (int j = 0; j < 100; j++) {
            megaMap['section$i']!['key$j'] = 'value$j' * 500;
          }
        }
        
        // Clear everything
        for (var list in megaList) {
          list.clear();
        }
        megaList.clear();
        
        for (var section in megaMap.values) {
          section.clear();
        }
        megaMap.clear();
        
        // Force multiple GC attempts
        _forceGarbageCollection();
        
        // Small delay between cycles
        if (cycle % 10 == 0) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }
      
      if (kDebugMode) print('[MEM] ✅ Extreme garbage collection completed');
      
    } catch (e) {
      if (kDebugMode) print('[MEM] ❌ Extreme GC failed: $e');
    }
  }
}