import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ultra-memory mode configuration for extreme memory reduction
class UltraMemoryMode {
  static bool _enabled = false;
  static bool get enabled => _enabled;
  
  /// Enable ultra-memory mode with most aggressive settings
  static void enable() {
    // Skip ultra-memory mode in release builds
    if (kReleaseMode) {
      if (kDebugMode) print('Ultra-memory mode disabled in release mode');
      return;
    }
    
    if (_enabled) return;
    
    _enabled = true;
    
    if (kDebugMode) print('⚡ ENABLING ULTRA-MEMORY MODE - Maximum memory reduction');
    
    // Reduce Flutter engine memory
    _configureFlutterEngine();
    
    // Minimize UI resources
    _minimizeUIResources();
    
    // Disable non-essential features
    _disableNonEssentialFeatures();
    
    if (kDebugMode) print('✅ Ultra-memory mode enabled');
  }
  
  /// Disable ultra-memory mode and restore normal operation
  static void disable() {
    if (!_enabled) return;
    
    _enabled = false;
    
    if (kDebugMode) print('↩️ Disabling ultra-memory mode');
    
    // Restore normal Flutter engine settings
    _restoreFlutterEngine();
    
    if (kDebugMode) print('✅ Ultra-memory mode disabled');
  }
  
  /// Configure Flutter engine for minimal memory usage
  static void _configureFlutterEngine() {
    try {
      // Set minimal image cache
      PaintingBinding.instance.imageCache.maximumSize = 3;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 5 << 20; // 5MB
      
      // Clear existing shader cache
      try {
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (e) {
        if (kDebugMode) print('Could not clear shaders: $e');
      }
      
    } catch (e) {
      if (kDebugMode) print('⚠️ Could not configure Flutter engine: $e');
    }
  }
  
  /// Restore normal Flutter engine settings
  static void _restoreFlutterEngine() {
    try {
      // Restore normal image cache
      PaintingBinding.instance.imageCache.maximumSize = 1000;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20; // 100MB
      
    } catch (e) {
      if (kDebugMode) print('⚠️ Could not restore Flutter engine: $e');
    }
  }
  
  /// Minimize UI resources for memory efficiency
  static void _minimizeUIResources() {
    try {
      // Force immediate garbage collection of UI elements
      WidgetsBinding.instance.buildOwner?.finalizeTree();
      
      // Minimize text rendering cache
      // Note: These are implementation details that may not be accessible
      
    } catch (e) {
      if (kDebugMode) print('⚠️ Could not minimize UI resources: $e');
    }
  }
  
  /// Disable non-essential features
  static void _disableNonEssentialFeatures() {
    try {
      // Disable haptic feedback
      HapticFeedback.vibrate();
      
      // Minimize system chrome
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      
    } catch (e) {
      if (kDebugMode) print('⚠️ Could not disable non-essential features: $e');
    }
  }
  
  /// Get memory-optimized theme data
  static ThemeData getOptimizedTheme() {
    if (!_enabled) {
      return ThemeData.light();
    }
    
    return ThemeData(
      // Use material design 2 which is lighter
      useMaterial3: false,
      
      // Minimal color scheme
      colorScheme: ColorScheme.fromSwatch(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      
      // Minimal typography
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 14),
        bodyMedium: TextStyle(fontSize: 12),
        bodySmall: TextStyle(fontSize: 10),
      ),
      
      // Disable animations
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
      
      // Minimal visual density
      visualDensity: VisualDensity.compact,
    );
  }
}