// lib/pages/splash_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:js_interop';           // ⬅️ add this
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web/web.dart' as web;

/// A simple splash that can do lightweight boot work, signal the watchdog that
/// we’re alive, and then navigate to [nextPage].
///
/// Note: Your heavy initialization (Firebase, Hive, services) is already done
/// in main.dart. We intentionally keep this splash minimal so we don’t risk
/// double-initializing anything.
class SplashPage extends StatefulWidget {
  const SplashPage({
    super.key,
    required this.nextPage,
    this.minDisplayTime = const Duration(milliseconds: 400),
  });

  final Widget nextPage;
  final Duration minDisplayTime;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Object? _error;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final startedAt = DateTime.now();
    try {
      // Do any *lightweight* UI-prep work here if you want.
      // Heavy init already happens in main.dart.

      // Tell the watchdog we’re progressing (prevents “stuck splash” wipe).
      _notifySplashComplete();

      // Ensure splash is visible at least a short time (looks nicer).
      final elapsed = DateTime.now().difference(startedAt);
      final remaining = widget.minDisplayTime - elapsed;
      if (remaining > Duration.zero) {
        await Future.delayed(remaining);
      }

      // Go to the app.
      if (mounted && !_navigated) {
        _navigated = true;
        // Use pushReplacement so the back button won’t return to splash.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => widget.nextPage),
        );
      }
    } catch (e) {
      setState(() => _error = e);
    }
  }

  void _notifySplashComplete() {
    if (!kIsWeb) return;
    try {
      // Convert to JS types for package:web
      web.window.postMessage('splash_complete'.toJS, '*'.toJS);
    } catch (_) {
      // Non-fatal; watchdog may wipe fc_-keys and reload if needed.
    }
  }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _error == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Icon(Icons.bubble_chart, size: 72, color: cs.primary),
                      const SizedBox(height: 16),
                      Text('FermentaCraft',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Text('Preparing your workspace…',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 24),
                      const LinearProgressIndicator(),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 56, color: cs.error),
                      const SizedBox(height: 12),
                      Text(
                        'Something went wrong',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: cs.error, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_error',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _start();
                        },
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
