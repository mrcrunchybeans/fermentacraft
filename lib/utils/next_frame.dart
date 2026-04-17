// lib/utils/next_frame.dart
import 'package:flutter/widgets.dart';

Future<void> onNextFrame(Future<void> Function() fn) async {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await fn();
    } catch (_) {}
  });
}
