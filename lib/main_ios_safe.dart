// lib/main_ios_safe.dart
//
// Build with:
//   flutter build ios --simulator --debug -t lib/main_ios_safe.dart --dart-define=IOS_SAFE_MODE=true
//   flutter build ios --simulator --debug -t lib/main_ios_safe.dart --dart-define=IOS_SAFE_MODE=false

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';

import 'bootstrap/firebase_boot.dart';

// Import your existing app entry so we can reuse its root widget.
import 'main.dart' as app;

/// CHANGE THIS to return your real root widget from `main.dart`.
/// Example if your root is `FermentaCraftApp`: `const app.FermentaCraftApp()`
Widget buildRealApp() => const app.FermentaCraftApp();

const bool kIosSafeMode =
    bool.fromEnvironment('IOS_SAFE_MODE', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };

  await runZonedGuarded(() async {
    runApp(const _SafeBootstrap());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class _SafeBootstrap extends StatefulWidget {
  const _SafeBootstrap(); // removed {super.key} to silence the unused param lint
  @override
  State<_SafeBootstrap> createState() => _SafeBootstrapState();
}

class _SafeBootstrapState extends State<_SafeBootstrap> {
  String status = 'Booting…';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      if (Platform.isIOS && kIosSafeMode) {
        // Deliberately bypass services on iOS in SAFE MODE
        await Future<void>.delayed(const Duration(milliseconds: 100));
        setState(() {
          status = 'iOS SAFE MODE: services bypassed';
          _ready = true;
        });
        return;
      }

      // Ensure Firebase is configured (uses plist on iOS)
      await FirebaseBoot.instance.ensure();

      setState(() {
        status = 'Init complete';
        _ready = true;
      });
    } catch (e, st) {
      debugPrint('Init error: $e\n$st');
      setState(() => status = 'Init failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final safe = Platform.isIOS && kIosSafeMode;

    // When not in safe mode and ready, jump straight into the real app.
    if (!safe && _ready) {
      return buildRealApp();
    }

    // Minimal shell UI for safe mode / early boot
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
                safe ? 'iOS SAFE MODE' : 'Starting…',
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
