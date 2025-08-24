// lib/main.dart
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// Premium state (single source of truth) + RC bootstrap
import 'services/feature_gate.dart';
import 'services/revenuecat_service.dart';

// Presets (yeast/additives)
import 'services/presets_service.dart';

// Web bridge (conditional)
import 'web_bridge_stub.dart'
  if (dart.library.html) 'web_bridge_web.dart' as wb;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web-only housekeeping (no-op on mobile)
  wb.hideHtmlSplash();
  wb.ensureFlutterRootCss();
  wb.scrubLegacyOverlays();
  assert(() {
    wb.disableServiceWorkers();              // dev-only; safe no-op in release
    wb.enableReloadDiagnostics(blockReload: true);
    return true;
  }());

  // Core services (Firebase/Hive/boxes/etc.)
  await setupAppServices();

  // Now that Firebase is ready, wire Crashlytics handlers.
  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true; // handled
  };

  // Pre-warm SharedPreferences to avoid first-run channel hiccup
  await SharedPreferences.getInstance();

  // Cloud sync: enable from saved setting
  final settingsBox = Hive.box(Boxes.settings);
  final syncEnabled = settingsBox.get('syncEnabled') == true;
  await (FirestoreSyncService.instance..isEnabled = syncEnabled).init();

  // RevenueCat: initialize & bind to FeatureGate
  await RevenueCatService.instance.init();

  // PresetsService: construct once, load persisted customs before runApp
  final presets = PresetsService();
  await presets.ensureLoaded();

  // Build app with providers AFTER services/boxes are ready
  runZonedGuarded(() {
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PresetsService>.value(value: presets),
          ChangeNotifierProvider<SettingsModel>(
            create: (_) => SettingsModel(Hive.box(Boxes.settings)),
          ),
          ChangeNotifierProvider<TagManager>(create: (_) => TagManager()),
          ChangeNotifierProvider<FeatureGate>.value(
            value: FeatureGate.instance,
          ),
        ],
        child: const FermentaCraftApp(),
      ),
    );

    // After first frame: finish splash cleanup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      wb.postSplashComplete();
    });

    // Optional watchdog (debug-only)
    assert(() {
      wb.startSplashWatchdog(timeout: const Duration(minutes: 2));
      return true;
    }());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
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
