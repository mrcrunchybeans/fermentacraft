// lib/bootstrap/firebase_boot.dart
//
// Uses iOS auto-config via GoogleService-Info.plist (no options needed).
// Safe to call multiple times and safe on non-iOS platforms.

import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseBoot {
  FirebaseBoot._();
  static final FirebaseBoot instance = FirebaseBoot._();
  static bool _initialized = false;
  static Completer<void>? _pending;

  Future<void> ensure() async {
    if (_initialized) return;

    if (_pending != null) {
      await _pending!.future;
      return;
    }
    _pending = Completer<void>();

    try {
      if (Firebase.apps.isEmpty) {
        // ⬇️ This will read GoogleService-Info.plist on iOS automatically
        await Firebase.initializeApp();
      }
      _initialized = true;
      _pending!.complete();
    } catch (e, st) {
      _pending!.completeError(e, st);
      rethrow;
    } finally {
      _pending = null;
      if (kDebugMode) {
        debugPrint('[BOOT] Firebase initialized (plist auto-config): $_initialized');
      }
    }
  }
}
