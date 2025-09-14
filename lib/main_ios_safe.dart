// lib/main_ios_safe.dart
//
// Build with SAFE MODE ON  (no services):
//   flutter build ios --simulator --debug -t lib/main_ios_safe.dart --dart-define=IOS_SAFE_MODE=true
//
// Build with SAFE MODE OFF (normal):
//   flutter build ios --simulator --debug -t lib/main_ios_safe.dart --dart-define=IOS_SAFE_MODE=false

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';

import 'bootstrap/firebase_boot.dart';
import 'main.dart' as app; // <-- use your existing entrypoint, no need to know the root widget name

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
  const _SafeBootstrap(); // no key param to silence "unused_element_parameter"
  @override
  State<_SafeBootstrap> createState() => _SafeBootstrapState();
}

class _SafeBootstrapState extends State<_SafeBootstrap> {
  String status = 'Booting…';
  bool _launchedRealApp = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      if (Platform.isIOS && kIosSafeMode) {
        // Bypass risky services entirely
        setState(() => status = 'iOS SAFE MODE: services bypassed');
        return;
      }

      // Ensure Firebase is configured BEFORE any Firebase-using plugin code.
      setState(() => status = 'Initializing Firebase…');
      await FirebaseBoot.ensure();

      // Hand off to your real entrypoint (this will call runApp(...) again).
      setState(() => status = 'Launching app…');
      app.main(); // <-- uses your existing main.dart; no imports of a specific widget needed
      _launchedRealApp = true;
      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('Init error: $e\n$st');
      setState(() => status = 'Init failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Once we hand off to app.main(), our widget tree will be replaced by your real app.
    if (_launchedRealApp && !(Platform.isIOS && kIosSafeMode)) {
      return const SizedBox.shrink();
    }

    // Minimal shell UI for SAFE MODE / early boot
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
              Icon(safe ? Icons.shield : Icons.hourglass_bottom,
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
