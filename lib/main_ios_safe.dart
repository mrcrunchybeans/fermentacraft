// lib/main_ios_safe.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

// If you generated firebase_options.dart (flutterfire configure), import it.
// If you don't have this file yet, comment the next line and the related usage.
import 'firebase_options.dart' as fb_opts;

import 'package:firebase_core/firebase_core.dart';

// Your services (safe to import even if some are no-ops)
import 'services/revenuecat_service.dart';
import 'services/feature_gate.dart';
import 'services/local_mode_service.dart';

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

      // 3) RevenueCat: SKIP on iOS if there is no key or SAFE MODE is on
      final bool skipRC = Platform.isIOS && (kIosSafeMode || !_hasIosRCKey());
      if (skipRC) {
        _log('RevenueCat: skipped on iOS (safe: $kIosSafeMode, key: ${_hasIosRCKey()})');
      } else {
        _log('RevenueCat: init');
        await RevenueCatService.instance.init();
        _log('RevenueCat: ready (supported=${RevenueCatService.instance.isSupported})');
      }

      // 4) Done; show a simple “app shell” so you can navigate further
      _log('BOOT COMPLETE');
      setState(() => _done = true);
    } catch (e, st) {
      _log('BOOT FAILED: $e');
      debugPrint('BOOT FAILED: $e\n$st');
      // keep screen visible with error text
    }
  }

  bool _hasIosRCKey() {
    // This mirrors your wrapper’s env behavior
    const k = String.fromEnvironment('RC_API_KEY_IOS', defaultValue: '');
    return k.isNotEmpty;
  }

  Future<void> _initFirebase() async {
    try {
      // If you have firebase_options.dart, use it; else fall back.
      await Firebase.initializeApp(
        options: Platform.isIOS || Platform.isMacOS
            ? fb_opts.DefaultFirebaseOptions.currentPlatform
            : fb_opts.DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {
      // Fallback if you don't have firebase_options.dart yet
      await Firebase.initializeApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final safe = Platform.isIOS && (kIosSafeMode || !_hasIosRCKey());

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(safe ? Icons.shield : Icons.check_circle,
                      size: 72, color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    safe ? 'iOS SAFE MODE' : 'Normal Startup',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.centerLeft,
                    height: 180,
                    child: SingleChildScrollView(
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
                        // TODO: when you’re ready, navigate to your real app root here.
                        // For now we just show the safe boot screen so it never goes black.
                      },
                      child: const Text('Continue', style: TextStyle(color: Colors.white)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
