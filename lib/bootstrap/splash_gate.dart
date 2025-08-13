// lib/bootstrap/splash_gate.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/startup_guard.dart';
import '../auth_gate.dart';

class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot({bool forceReset = false}) async {
    setState(() => _error = null);
    try {
      await StartupGuard.run(softResetAfter: const Duration(seconds: 8));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasError = _error != null;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const FlutterLogo(size: 64),
              const SizedBox(height: 16),
              Text('FermentaCraft', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 24),
              if (!hasError) const LinearProgressIndicator(),
              if (!hasError && kIsWeb)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Preparing app…',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (hasError) ...[
                Text(
                  'We hit a snag starting up.',
                  style: theme.textTheme.bodyMedium!
                      .copyWith(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall!
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _boot(forceReset: true),
                  child: const Text('Try Safe Reset'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
