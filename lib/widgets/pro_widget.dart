// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.workspace_premium, size: 14),
          SizedBox(width: 4),
          Text('Premium', style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
