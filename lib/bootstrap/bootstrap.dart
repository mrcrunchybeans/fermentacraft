// lib/bootstrap/bootstrap.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import '../services/revenuecat_service.dart';

/// One place to initialize platform services in the right order.
/// Call this *before* building your real app widget tree.
class AppBootstrap {
  AppBootstrap._();
  static final instance = AppBootstrap._();

  bool _done = false;
  bool get isDone => _done;

  Future<void> run({required bool safeMode}) async {
    if (_done) return;
    try {
      // 1) Firebase first (works on all platforms)
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // 2) RevenueCat only on Apple platforms; guard and allow skipping in safe mode
      if (!safeMode && (Platform.isIOS || Platform.isMacOS)) {
        await RevenueCatService.instance.configure();
      }

      _done = true;
    } catch (e, st) {
      debugPrint('[BOOTSTRAP] Failed: $e\n$st');
      rethrow;
    }
  }
}
