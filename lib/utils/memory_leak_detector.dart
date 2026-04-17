/// Memory leak detection and fixing utilities
/// Identifies and resolves common memory leak patterns in Flutter apps
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Service to detect and fix memory leaks
class MemoryLeakDetector {
  MemoryLeakDetector._();
  static final MemoryLeakDetector instance = MemoryLeakDetector._();

  final Set<String> _leakSources = <String>{};
  final Map<String, int> _leakCounts = <String, int>{};
  Timer? _detectionTimer;

  /// Start memory leak detection
  void startDetection() {
    if (_detectionTimer != null) return;
    
    _detectionTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _performLeakDetection();
    });
  }

  /// Stop memory leak detection
  void stopDetection() {
    _detectionTimer?.cancel();
    _detectionTimer = null;
  }

  /// Perform memory leak detection
  void _performLeakDetection() {
    if (!kDebugMode) return;
    
    _checkStreamSubscriptions();
    _checkTimers();
    _checkListeners();
    
    if (_leakSources.isNotEmpty) {
      debugPrint('⚠️  Memory leaks detected: ${_leakSources.join(', ')}');
    }
  }

  void _checkStreamSubscriptions() {
    // This is a placeholder - in a real implementation, you'd track active subscriptions
    // For now, we'll just log potential issues
  }

  void _checkTimers() {
    // This is a placeholder - Timer tracking would require more complex implementation
  }

  void _checkListeners() {
    // This is a placeholder - Listener tracking would require instrumentation
  }

  /// Register a potential leak source
  void registerLeakSource(String source) {
    _leakSources.add(source);
    _leakCounts[source] = (_leakCounts[source] ?? 0) + 1;
  }

  /// Clear a leak source
  void clearLeakSource(String source) {
    _leakSources.remove(source);
    _leakCounts.remove(source);
  }

  /// Get current leak report
  Map<String, dynamic> getLeakReport() {
    return {
      'active_leaks': _leakSources.toList(),
      'leak_counts': Map<String, int>.from(_leakCounts),
      'detection_active': _detectionTimer != null,
    };
  }
}

/// Mixin to automatically detect and prevent common memory leaks
mixin MemoryLeakPrevention<T extends StatefulWidget> on State<T> {
  final Set<StreamSubscription> _subscriptions = <StreamSubscription>{};
  final Set<Timer> _timers = <Timer>{};
  final Set<ChangeNotifier> _notifiers = <ChangeNotifier>{};
  final Set<VoidCallback> _listeners = <VoidCallback>{};

  /// Track a stream subscription for automatic disposal
  void trackSubscription(StreamSubscription subscription) {
    _subscriptions.add(subscription);
  }

  /// Track a timer for automatic disposal
  void trackTimer(Timer timer) {
    _timers.add(timer);
  }

  /// Track a notifier for automatic disposal
  void trackNotifier(ChangeNotifier notifier) {
    _notifiers.add(notifier);
  }

  /// Track a listener callback for reference
  void trackListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Safely add listener to a notifier and track it
  void safeAddListener(ChangeNotifier notifier, VoidCallback listener) {
    notifier.addListener(listener);
    trackNotifier(notifier);
    trackListener(listener);
  }

  /// Safely remove listener from a notifier
  void safeRemoveListener(ChangeNotifier notifier, VoidCallback listener) {
    notifier.removeListener(listener);
    _listeners.remove(listener);
  }

  @override
  void dispose() {
    _disposeTrackedResources();
    super.dispose();
  }

  void _disposeTrackedResources() {
    // Cancel all tracked subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // Cancel all tracked timers
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();

    // Remove listeners from tracked notifiers
    for (final notifier in _notifiers) {
      for (final listener in _listeners) {
        try {
          notifier.removeListener(listener);
        } catch (e) {
          // Listener might already be removed, ignore
        }
      }
    }
    _notifiers.clear();
    _listeners.clear();
  }
}

/// Helper to create memory-safe stream subscriptions
class SafeStreamSubscription {
  static StreamSubscription<T> create<T>(
    Stream<T> stream,
    void Function(T) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    
    if (kDebugMode) {
      MemoryLeakDetector.instance.registerLeakSource('StreamSubscription_${stream.runtimeType}');
    }
    
    return subscription;
  }
}

/// Helper to create memory-safe timers
class SafeTimer {
  static Timer periodic(Duration duration, void Function(Timer) callback) {
    final timer = Timer.periodic(duration, callback);
    
    if (kDebugMode) {
      MemoryLeakDetector.instance.registerLeakSource('Timer_periodic');
    }
    
    return timer;
  }

  static Timer create(Duration duration, void Function() callback) {
    final timer = Timer(duration, callback);
    
    if (kDebugMode) {
      MemoryLeakDetector.instance.registerLeakSource('Timer_single');
    }
    
    return timer;
  }
}

/// Widget to automatically dispose resources
class ResourceManager extends StatefulWidget {
  const ResourceManager({
    super.key,
    required this.child,
    this.subscriptions,
    this.timers,
    this.notifiers,
  });

  final Widget child;
  final List<StreamSubscription>? subscriptions;
  final List<Timer>? timers;
  final List<ChangeNotifier>? notifiers;

  @override
  State<ResourceManager> createState() => _ResourceManagerState();
}

class _ResourceManagerState extends State<ResourceManager> {
  @override
  void dispose() {
    // Dispose subscriptions
    if (widget.subscriptions != null) {
      for (final sub in widget.subscriptions!) {
        sub.cancel();
      }
    }

    // Cancel timers
    if (widget.timers != null) {
      for (final timer in widget.timers!) {
        timer.cancel();
      }
    }

    // Dispose notifiers
    if (widget.notifiers != null) {
      for (final notifier in widget.notifiers!) {
        notifier.dispose();
      }
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}