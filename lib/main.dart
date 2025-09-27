// lib/main.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'bootstrap/setup.dart';
import 'theme/app_theme.dart';
import 'auth_gate.dart';
import 'utils/boxes.dart';
import 'services/snackbar_service.dart';

// Models / Providers
import 'models/settings_model.dart';
import 'models/tag_manager.dart';

// Migration + Sync
import 'services/firestore_sync_service.dart';

// Premium state (single source of truth)
import 'services/feature_gate.dart';
import 'services/revenuecat_service.dart';

// Presets (yeast/additives)
import 'services/presets_service.dart';

// Memory optimization
import 'services/memory_optimization_service.dart';

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
Future<_BootstrapPayload> _bootstrap() async {
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

  // Cloud sync (honor user setting)
  final settingsBox = Hive.box(Boxes.settings);
  final syncEnabled = settingsBox.get('syncEnabled') == true;
  await (FirestoreSyncService.instance..isEnabled = syncEnabled).init();

  // Presets
  final presets = PresetsService();
  await presets.ensureLoaded();

  // Initialize memory optimization service
  debugPrint('[MEM] Starting memory optimization service...');
  MemoryOptimizationService.instance.initialize();
  debugPrint('[MEM] Memory optimization service started.');

  return _BootstrapPayload(presets: presets);
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final payload = await _bootstrap();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PresetsService>.value(value: payload.presets),
          ChangeNotifierProvider<SettingsModel>(
            create: (_) => SettingsModel(Hive.box(Boxes.settings)),
          ),
          ChangeNotifierProvider<TagManager>(create: (_) => TagManager()),
          ChangeNotifierProvider<FeatureGate>.value(
              value: FeatureGate.instance),
        ],
        child: const FermentaCraftApp(),
      ),
    );

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

class FermentaCraftApp extends StatelessWidget {
  const FermentaCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    return MaterialApp(
      title: 'FermentaCraft',
      scaffoldMessengerKey: SnackbarService.messengerKey,
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const AuthGate(),
    );
  }
}

class _BootstrapPayload {
  final PresetsService presets;
  _BootstrapPayload({required this.presets});
}
