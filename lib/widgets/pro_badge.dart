// lib/widgets/pro_badge.dart
import 'package:flutter/material.dart';

class ProBadge extends StatelessWidget {
  const ProBadge({
    super.key,
    this.unlocked = false,
    this.compact = true,
    this.label, // <- optional
  });

  final bool unlocked;
  final bool compact;
  final String? label;

  String get _label => label ?? (unlocked ? 'Premium' : 'Free');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = unlocked ? cs.primaryContainer.withValues(alpha: 0.85) : cs.surfaceContainerHigh;
    final fg = unlocked ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    final bd = unlocked ? cs.primary : cs.outlineVariant;

    final padX = compact ? 8.0 : 10.0;
    final padY = compact ? 4.0 : 6.0;
    final fontSize = compact ? 11.0 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padX, vertical: padY),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bd, width: 1),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(
              Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.08,
            ),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!unlocked) ...[
          ],
          Text(
            _label.toUpperCase(),
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: fontSize,
              letterSpacing: 0.8,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
