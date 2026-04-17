// lib/bootstrap/bootstrap.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

import '../services/revenuecat_service.dart';

Future<void> bootstrap({required bool prewarmOnly}) async {
  try {
    if (Firebase.apps.isEmpty) {
      if (Platform.isIOS) {
        await Firebase.initializeApp(); // plist-based on iOS
      } else {
        await Firebase.initializeApp(); // or use DefaultFirebaseOptions if present
      }
    }
  } catch (e, st) {
    debugPrint('Firebase init failed (continuing for SAFE MODE / diag): $e\n$st');
  }

  if (prewarmOnly) return;

  try {
    await RevenueCatService.instance.init();
  } catch (e, st) {
    debugPrint('RevenueCat init failed (non-fatal): $e\n$st');
  }
}
