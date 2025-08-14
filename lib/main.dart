// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'bootstrap/setup.dart';
import 'utils/boxes.dart';
import 'theme/app_theme.dart';
import 'auth_gate.dart';

import 'models/settings_model.dart';
import 'models/tag_manager.dart';

// Migration + Sync
import 'utils/data_management.dart';
import 'package:fermentacraft/services/firestore_sync_service.dart';


// ✅ Premium state (single source of truth) + RC bootstrap
import 'services/feature_gate.dart';
import 'services/revenuecat_service.dart';

// Web bridge (conditional)
import 'web_bridge_stub.dart'
  if (dart.library.html) 'web_bridge_web.dart' as wb;

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // --- Web-only housekeeping (safe no-ops off web)
    wb.hideHtmlSplash();
    wb.ensureFlutterRootCss();
    wb.scrubLegacyOverlays();

    // Debug-only: block surprise reloads and unregister SWs while testing
    assert(() {
      wb.disableServiceWorkers();
      wb.enableReloadDiagnostics(blockReload: true);
      return true;
    }());

    // --- App services (Firebase, Hive adapters, RC configure, etc.)
    await setupAppServices();

    // --- One-time, idempotent migration: Hive key == model.id (or tag name)
    await DataManagementService.migrateHiveKeysToStableIds();

    // --- Cloud sync: enable from saved setting
    final settingsBox = Hive.box(Boxes.settings);
    final syncEnabled = settingsBox.get('syncEnabled') == true;
    final sync = FirestoreSyncService.instance
      ..isEnabled = syncEnabled;
    await sync.init(); // safe if disabled; should internally no-op

    // --- RevenueCat: start listeners & mirror into FeatureGate
    await RevenueCatService.instance.init();

    // --- Build app with providers
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsModel>(
            create: (_) => SettingsModel(Hive.box(Boxes.settings)),
          ),
          ChangeNotifierProvider<TagManager>(create: (_) => TagManager()),
          // 👇 FeatureGate is the reactive premium state used across the app
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

    // Optional watchdog (debug-only) with long timeout so it never races UI/auth
    assert(() {
      wb.startSplashWatchdog(timeout: const Duration(minutes: 2));
      return true;
    }());
  }, (error, stack) {
    // debugPrint('Uncaught: $error\n$stack');
  });
}

class FermentaCraftApp extends StatelessWidget {
  const FermentaCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    return MaterialApp(
      title: 'FermentaCraft',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const AuthGate(),
    );
  }
}
