import 'dart:async';
import 'package:flutter/material.dart';
import '../web_bridge.dart';

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

    // ✅ Signal immediately to satisfy the watchdog.
    postSplashComplete();

    _go();
  }

  Future<void> _go() async {
    final started = DateTime.now();
    try {
      final elapsed = DateTime.now().difference(started);
      final wait = widget.minDisplayTime - elapsed;
      if (wait > Duration.zero) {
        await Future.delayed(wait);
      }
      if (mounted && !_navigated) {
        _navigated = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => widget.nextPage),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
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
                      Text('Something went wrong',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: cs.error, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('$_error', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _go();
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
