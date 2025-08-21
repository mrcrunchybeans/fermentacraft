import 'package:flutter/material.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const MetricChip({super.key, required this.icon, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final chip = Chip(
      avatar: Icon(icon, size: 18),
      label: Text('$label: $value'),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
    return onTap == null
        ? chip
        : InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: chip);
  }
}

String unitSymbol(dynamic unit) {
  final s = unit?.toString().toLowerCase() ?? '';
  return s.startsWith('f') ? '°F' : '°C';
}
