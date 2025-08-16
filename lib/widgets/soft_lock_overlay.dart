// lib/widgets/soft_lock_overlay.dart
// ignore_for_file: deprecated_member_use

import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';

class SoftLockOverlay extends StatelessWidget {
  final bool allow;              // if false => soft lock
  final Widget child;
  final String message;

  const SoftLockOverlay({
    super.key,
    required this.allow,
    required this.child,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    if (allow) return child;

    return Stack(
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.mode(Colors.black12, BlendMode.saturation),
          child: child,
        ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showPaywall(context),

              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withOpacity(.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.lock),
                      SizedBox(width: 8),
                      Text('Premium feature'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}