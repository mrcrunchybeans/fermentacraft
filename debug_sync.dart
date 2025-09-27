// Debug sync status
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fermentacraft/services/firestore_sync_service.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/services/local_mode_service.dart';

void debugSyncStatus() {
  final user = FirebaseAuth.instance.currentUser;
  final sync = FirestoreSyncService.instance;
  final gate = FeatureGate.instance;
  final local = LocalModeService.instance;
  
  debugPrint('=== SYNC DEBUG STATUS ===');
  debugPrint('User signed in: ${user != null} (${user?.uid})');
  debugPrint('Sync enabled: ${sync.isEnabled}');
  debugPrint('Feature gate allowSync: ${gate.allowSync}');
  debugPrint('Local mode: ${local.isLocalOnly}');
  debugPrint('Premium active: ${gate.premiumActive}');
  debugPrint('Pro offline owned: ${gate.proOfflineOwned}');
  debugPrint('========================');
  
  if (!gate.allowSync) {
    debugPrint('🚫 SYNC BLOCKED: Premium subscription required');
  } else if (local.isLocalOnly) {
    debugPrint('🚫 SYNC BLOCKED: Local-only mode enabled');
  } else if (user == null) {
    debugPrint('🚫 SYNC BLOCKED: Not signed in');
  } else if (!sync.isEnabled) {
    debugPrint('🚫 SYNC BLOCKED: Sync disabled in settings');
  } else {
    debugPrint('✅ SYNC SHOULD WORK');
  }
}