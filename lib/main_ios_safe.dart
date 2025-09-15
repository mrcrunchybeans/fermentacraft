// lib/main_ios_safe.dart
//
// SAFE MODE ON:
//   flutter build ios --simulator --debug -t lib/main_ios_safe.dart --dart-define=IOS_SAFE_MODE=true
//
// SAFE MODE OFF (normal):
//   flutter build ios --simulator --debug -t lib/main_ios_safe.dart --dart-define=IOS_SAFE_MODE=false

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';

import 'bootstrap/bootstrap.dart';
import 'main.dart' as app; // use your real entrypoint

const bool kIosSafeMode =
    bool.fromEnvironment('IOS_SAFE_MODE', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  await bootstrap(prewarmOnly: kIosSafeMode);

  if (Platform.isIOS && kIosSafeMode) {
    runZonedGuarded(() {
      runApp(const _SafeShell());
    }, (error, stack) {
      debugPrint('Uncaught zone error (SAFE): $error\n$stack');
    });
    return;
  }

  runZonedGuarded(() {
    app.main();
  }, (error, stack) {
    debugPrint('Uncaught zone error (APP): $error\n$stack');
  });
}

class _SafeShell extends StatelessWidget {
  const _SafeShell();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FermentaCraft (iOS SAFE MODE)',
      debugShowCheckedModeBanner: false,
      home: const _SafeHome(),
    );
  }
}

class _SafeHome extends StatefulWidget {
  const _SafeHome();
  @override
  State<_SafeHome> createState() => _SafeHomeState();
}

class _SafeHomeState extends State<_SafeHome> {
  String _status = 'Booting…';

  @override
  void initState() {
    super.initState();
    _tick();
  }

  Future<void> _tick() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (mounted) setState(() => _status = 'iOS SAFE MODE: services bypassed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield, size: 96, color: Colors.white),
            const SizedBox(height: 18),
            const Text(
              'iOS SAFE MODE',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _status,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
