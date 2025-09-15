// lib/main_ios_safe.dart
//
// Build with (safe true):  flutter run -t lib/main_ios_safe.dart --dart-define=IOS_SAFE_MODE=true
// Build with (safe false): flutter run -t lib/main_ios_safe.dart --dart-define=IOS_SAFE_MODE=false
//
// In Codemagic we already run both variants to prove stability.

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'bootstrap/bootstrap.dart';
import 'app/app.dart'; // <-- your real app root (MyApp)

const bool kIosSafeMode =
    bool.fromEnvironment('IOS_SAFE_MODE', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  runZonedGuarded(() async {
    runApp(const _SafeBootstrap());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class _SafeBootstrap extends StatefulWidget {
  const _SafeBootstrap({super.key});
  @override
  State<_SafeBootstrap> createState() => _SafeBootstrapState();
}

class _SafeBootstrapState extends State<_SafeBootstrap> {
  String _status = 'Booting…';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      if (Platform.isIOS && kIosSafeMode) {
        setState(() {
          _status = 'iOS SAFE MODE: services bypassed';
          _ready = true;
        });
        return;
      }

      setState(() => _status = 'Initializing services…');
      await AppBootstrap.instance.run(safeMode: false);

      setState(() {
        _status = 'Services ready';
        _ready = true;
      });
    } catch (e, st) {
      setState(() => _status = 'Init failed: $e');
      debugPrint('Init error: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      final safe = Platform.isIOS && kIosSafeMode;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  safe ? Icons.shield : Icons.sync,
                  size: 80,
                  color: Colors.white,
                ),
                const SizedBox(height: 20),
                Text(
                  safe ? 'iOS SAFE MODE' : 'Starting…',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _status,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Only build your real app once services are ready.
    return const MyApp();
  }
}
