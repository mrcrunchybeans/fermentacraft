// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
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

// Premium state (single source of truth) + RC bootstrap
import 'services/feature_gate.dart';
import 'services/revenuecat_service.dart';

// Web bridge (conditional)
import 'web_bridge_stub.dart'
if (dart.library.html) 'web_bridge_web.dart' as wb;

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Pass all uncaught "fatal" errors from the framework to Crashlytics
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };

    // --- Web-only housekeeping (safe no-ops on mobile)
    wb.hideHtmlSplash();
    wb.ensureFlutterRootCss();
    wb.scrubLegacyOverlays();

    // Debug-only helpers for web dev
    assert(() {
      wb.disableServiceWorkers();
      wb.enableReloadDiagnostics(blockReload: true);
      return true;
    }());

    // --- Core services (adapters, boxes, Firebase, etc.)
    // IMPORTANT: ensure TagAdapter is registered before RecipeModel in setupAppServices().
    await setupAppServices();


    // --- Cloud sync: enable from saved setting
    final settingsBox = Hive.box(Boxes.settings);
    final syncEnabled = settingsBox.get('syncEnabled') == true;
    await (FirestoreSyncService.instance
      ..isEnabled = syncEnabled)
        .init(); // no-op internally if disabled

    // --- RevenueCat: initialize & bind to FeatureGate
    await RevenueCatService.instance.init();

    // --- Build app with providers AFTER services/boxes are ready
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsModel>(
            create: (_) => SettingsModel(Hive.box(Boxes.settings)),
          ),
          // TagManager must not touch Hive during construction; ensure it's lazy inside TagManager.
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
    // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
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