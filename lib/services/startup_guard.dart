// lib/services/startup_guard.dart
import 'dart:async';

import 'startup_guard_impl_io.dart'
    if (dart.library.html) 'startup_guard_impl_web.dart' as impl;

/// Platform-safe startup guard facade.
class StartupGuard {
  /// Optionally schedule a soft reset if boot appears stuck (web impl only).
  static Future<void> run({Duration? softResetAfter}) =>
      impl.run(softResetAfter: softResetAfter);

  /// Remove the HTML splash elements if present (web impl only; no-op elsewhere).
  static void removeSplash() => impl.removeSplash();

  /// Clear client-side caches that use the `fc_` key prefix (web impl; no-op elsewhere).
  static void triggerSoftReset({String prefix = 'fc_'}) =>
      impl.triggerSoftReset(prefix: prefix);

  /// Mark boot as successful (web impl stores a tiny session flag; no-op elsewhere).
  static void markBootOk() => impl.markBootOk();
}
