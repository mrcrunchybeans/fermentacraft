// lib/main_ios_safe.dart
//
// Build with:
//   flutter build ios --simulator --debug -t lib/main_ios_safe.dart --dart-define=IOS_SAFE_MODE=true
//
// Then again with:
//   --dart-define=IOS_SAFE_MODE=false
//
// This lets us prove whether startup services are the crash culprit on iOS.

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';

const bool kIosSafeMode =
    bool.fromEnvironment('IOS_SAFE_MODE', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  runZonedGuarded(() async {
    runApp(const _SafeApp());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class _SafeApp extends StatefulWidget {
  const _SafeApp();
  @override
  State<_SafeApp> createState() => _SafeAppState();
}

class _SafeAppState extends State<_SafeApp> {
  String status = 'Booting…';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      if (Platform.isIOS && kIosSafeMode) {
        // BYPASS all risky services on iOS in safe mode
        await Future<void>.delayed(const Duration(milliseconds: 100));
        setState(() => status = 'iOS SAFE MODE: services bypassed');
        return;
      }

      // TODO: After we confirm safe mode works,
      // bring your real init back here step-by-step (Firebase/Hive/RC/etc.) with try/catch.

      setState(() => status = 'Normal init complete');
    } catch (e, st) {
      setState(() => status = 'Init failed: $e');
      debugPrint('Init error: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final safe = Platform.isIOS && kIosSafeMode;
    return MaterialApp(
      title: 'FermentaCraft',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(safe ? Icons.shield : Icons.check_circle,
                  size: 96, color: Colors.white),
              const SizedBox(height: 24),
              Text(
                safe ? 'iOS SAFE MODE' : 'Normal Startup',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
