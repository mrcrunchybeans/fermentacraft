// lib/main.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'bootstrap/setup.dart';
import 'theme/app_theme.dart';
import 'auth_gate.dart';
import 'services/snackbar_service.dart';
import 'services/service_locator.dart';
import 'services/firestore_sync_service.dart';
import 'services/feature_gate.dart';
import 'services/revenuecat_service.dart';
import 'services/memory_optimization_service.dart';
import 'models/settings_model.dart';
import 'models/tag_manager.dart';
import 'services/presets_service.dart';

// Web bridge (conditional)
import 'web_bridge_stub.dart'
  if (dart.library.html) 'web_bridge_web.dart' as wb;

bool get _crashlyticsSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

Future<void> _wireCrashlytics() async {
  if (!_crashlyticsSupported) return;
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
}

/// Initialize core services in a safe, deterministic order:
/// 1) Firebase/Hive/etc.
/// 2) RevenueCat (mobile only)
/// 3) FeatureGate (now safe to read from RC)
/// 4) Crashlytics
/// 5) SharedPrefs prewarm
/// 6) Firestore Sync
/// 7) Presets
/// Initialize core services in a clean, dependency-aware order
Future<void> _bootstrap() async {
  // Android edge-to-edge early for smoother first frame
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Web-only housekeeping (no-op on mobile/desktop)
  wb.hideHtmlSplash();
  wb.ensureFlutterRootCss();
  wb.scrubLegacyOverlays();
  assert(() {
    wb.disableServiceWorkers();
    wb.enableReloadDiagnostics(blockReload: true);
    return true;
  }());

  // Core services (Firebase init, Hive, adapters, boxes, etc.)
  await setupAppServices();

  // RevenueCat FIRST (creates Purchases singleton)
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      debugPrint('[RC] configuring…');
      await RevenueCatService.instance.init();
      debugPrint('[RC] configured.');
    } catch (e, st) {
      debugPrint('[RC] init failed: $e');
      // Don't block startup; FeatureGate still loads local Pro-Offline
      if (_crashlyticsSupported) {
        unawaited(FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'RevenueCat init'));
      }
    }
  }

  // FeatureGate: loads local plan and (if RC ready) attaches listeners
  await FeatureGate.instance.bootstrap();

  // Crashlytics next (so subsequent errors are captured)
  await _wireCrashlytics();

  // Pre-warm SharedPreferences (avoids first access hitches)
  unawaited(SharedPreferences.getInstance());

  // Initialize memory optimization service
  debugPrint('[MEM] Starting memory optimization service...');
  MemoryOptimizationService.instance.initialize();
  debugPrint('[MEM] Memory optimization service started.');

  // Initialize modern service locator with dependency injection
  debugPrint('[DI] Initializing service locator...');
  await ServiceLocator.initialize();
  debugPrint('[DI] Service locator initialized.');

  // Legacy sync service (will be phased out in favor of SyncCoordinator)
  // Keep for compatibility during transition
  try {
    await FirestoreSyncService.instance.init();
    debugPrint('[SYNC] Legacy sync service initialized');
  } catch (e) {
    debugPrint('[SYNC] Legacy sync init failed: $e (using new coordinator)');
  }
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await _bootstrap();

    runApp(const FermentaCraftApp());

    WidgetsBinding.instance
        .addPostFrameCallback((_) => wb.postSplashComplete());

    assert(() {
      wb.startSplashWatchdog(timeout: const Duration(minutes: 2));
      return true;
    }());
  }, (error, stack) async {
    if (_crashlyticsSupported) {
      await FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: true);
    } else {
      // ignore: avoid_print
      print('Uncaught error: $error\n$stack');
    }
  });
}

/// Root application widget with clean Provider architecture
class FermentaCraftApp extends StatelessWidget {
  const FermentaCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: _buildProviders(),
      child: Consumer<SettingsModel>(
        builder: (context, settings, child) {
          return MaterialApp(
            title: 'FermentaCraft',
            scaffoldMessengerKey: SnackbarService.messengerKey,
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const AuthGate(),
          );
        },
      ),
    );
  }

  /// Build provider list with proper organization
  List<ChangeNotifierProvider> _buildProviders() {
    return [
      // Core services
      ChangeNotifierProvider<FeatureGate>.value(
        value: ServiceLocator.get<FeatureGate>(),
      ),
      
      // Data models
      ChangeNotifierProvider<SettingsModel>.value(
        value: ServiceLocator.get<SettingsModel>(),
      ),
      ChangeNotifierProvider<TagManager>.value(
        value: ServiceLocator.get<TagManager>(),
      ),
      
      // Business services
      ChangeNotifierProvider<PresetsService>.value(
        value: ServiceLocator.get<PresetsService>(),
      ),
    ];
  }
}

/// Cleanup services on app termination
class AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      ServiceLocator.dispose();
    }
  }
}
