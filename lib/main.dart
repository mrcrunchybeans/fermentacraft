// lib/main.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <-- added (edge-to-edge)
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

// Premium state (single source offruth) + RC bootstrap
import 'services/feature_gate.dart';
import 'services/revenuecat_service.dart';

// Presets (yeast/additives)
import 'services/presets_service.dart';

// Web bridge (conditional)
import 'web_bridge_stub.dart'
  if (dart.library.html) 'web_bridge_web.dart' as wb;

bool get _crashlyticsSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

Future<void> _wireCrashlytics() async {
  if (!_crashlyticsSupported) return;

  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Edge-to-edge once at startup (Android)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Web-only housekeeping (no-op on mobile)
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

    // Crashlytics (supported platforms only)
    await _wireCrashlytics();

    // Pre-warm SharedPreferences
    await SharedPreferences.getInstance();

    // Cloud sync
    final settingsBox = Hive.box(Boxes.settings);
    final syncEnabled = settingsBox.get('syncEnabled') == true;
    await (FirestoreSyncService.instance..isEnabled = syncEnabled).init();

    // RevenueCat
    await RevenueCatService.instance.init();

    // Presets
    final presets = PresetsService();
    await presets.ensureLoaded();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PresetsService>.value(value: presets),
          ChangeNotifierProvider<SettingsModel>(
            create: (_) => SettingsModel(Hive.box(Boxes.settings)),
          ),
          ChangeNotifierProvider<TagManager>(create: (_) => TagManager()),
          ChangeNotifierProvider<FeatureGate>.value(value: FeatureGate.instance),
        ],
        child: const FermentaCraftApp(),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => wb.postSplashComplete());

    assert(() {
      wb.startSplashWatchdog(timeout: const Duration(minutes: 2));
      return true;
    }());
  }, (error, stack) async {
    if (_crashlyticsSupported) {
      await FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
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
