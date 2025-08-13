// lib/startup/startup_guard.dart
import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web/web.dart' as web;

import '../utils/storage_wipe_web.dart';

/// Starts a watchdog: if splash doesn't post 'splash_complete' within [timeout],
/// we wipe fc_-scoped caches and reload.
void startSplashWatchdog({Duration timeout = const Duration(seconds: 8)}) {
  if (!kIsWeb) return;

  var splashLoaded = false;

  web.window.onMessage.listen((evt) {
    // evt.data is a JS value; convert to Dart.
    final data = (evt.data)?.dartify();
    if (data == 'splash_complete') {
      splashLoaded = true;
    }
  });

  Future.delayed(timeout, () {
    if (!splashLoaded) {
      wipeNamespacedStorage(); // <-- this is the function your code couldn’t find
      web.window.location.reload();
    }
  });
}
