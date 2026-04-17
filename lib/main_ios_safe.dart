// lib/main_ios_safe.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

// If you generated firebase_options.dart (flutterfire configure), import it.
// If you don't have this file yet, comment the next line and the related usage.
import 'firebase_options.dart' as fb_opts;

import 'package:firebase_core/firebase_core.dart';

// Your services (safe to import even if some are no-ops)
import 'services/revenuecat_service.dart';
import 'services/feature_gate.dart';
import 'services/local_mode_service.dart';

// Main app components
import 'theme/app_theme.dart';
import 'auth_gate.dart';
import 'utils/boxes.dart';
import 'services/snackbar_service.dart';

// Models / Providers
import 'models/settings_model.dart';
import 'models/tag_manager.dart';

// Toggle with --dart-define=IOS_SAFE_MODE=true/false (default true)
const bool kIosSafeMode =
    bool.fromEnvironment('IOS_SAFE_MODE', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
  };

  runZonedGuarded(() async {
    runApp(const _SafeBootApp());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class _SafeBootApp extends StatelessWidget {
  const _SafeBootApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _SafeBootScreen(),
    );
  }
}

class _SafeBootScreen extends StatefulWidget {
  const _SafeBootScreen();
  @override
  State<_SafeBootScreen> createState() => _SafeBootScreenState();
}

class _SafeBootScreenState extends State<_SafeBootScreen> {
  final List<String> _lines = <String>['Booting…'];
  bool _done = false;

  void _log(String m) {
    debugPrint('[BOOT] $m');
    setState(() => _lines.add(m));
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      // 1) Firebase first, with a timeout so we never hang on black
      _log('Firebase: init start');
      await _initFirebase().timeout(const Duration(seconds: 10));
      _log('Firebase: ok');

      // 2) FeatureGate + LocalMode (always safe)
      FeatureGate.instance.setFromBackend(false);
      _log('FeatureGate: seeded (false)');
      _log('LocalMode: ${LocalModeService.instance.isLocalOnly}');

      // 3) RevenueCat (safe to skip)
      try {
        _log('RevenueCat: init start');
        await RevenueCatService.instance.init();
        _log('RevenueCat: ok');
      } catch (e, st) {
        _log('RevenueCat: err $e');
        debugPrint('RevenueCat error: $e\n$st');
      }

      await Future.delayed(const Duration(seconds: 1));
      _log('Boot: complete!');
      setState(() => _done = true);
    } catch (e, st) {
      _log('Boot: FAIL $e');
      debugPrint('Boot error: $e\n$st');
    }
  }

  Future<void> _initFirebase() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      await Firebase.initializeApp(options: fb_opts.DefaultFirebaseOptions.currentPlatform);
    } else {
      debugPrint('Firebase: skip (unsupported platform)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'iOS Safe Mode',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Debugging boot sequence...',
                  style: TextStyle(color: Colors.white60, fontSize: 16),
                ),
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 200),
                    child: SelectableText(
                      _lines.join('\n'),
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.25,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_done)
                  TextButton(
                    onPressed: () {
                      // Navigate to the real app root
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => MultiProvider(
                            providers: [
                              ChangeNotifierProvider<SettingsModel>(
                                create: (_) => SettingsModel(Hive.box(Boxes.settings)),
                              ),
                              ChangeNotifierProvider<TagManager>(create: (_) => TagManager()),
                              ChangeNotifierProvider<FeatureGate>.value(
                                value: FeatureGate.instance),
                            ],
                            child: const FermentaCraftApp(),
                          ),
                        ),
                      );
                    },
                    child: const Text('Continue', style: TextStyle(color: Colors.white)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Main app widget - similar to main.dart
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