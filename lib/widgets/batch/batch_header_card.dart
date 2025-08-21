import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/batch_model.dart';

class BatchHeaderCard extends StatelessWidget {
  final BatchModel batch;
  final VoidCallback onChangeStatus;
  final VoidCallback onToggleBrewMode;
  final bool brewModeEnabled;
  final VoidCallback onArchiveToggle;

  const BatchHeaderCard({
    super.key,
    required this.batch,
    required this.onChangeStatus,
    required this.onToggleBrewMode,
    required this.brewModeEnabled,
    required this.onArchiveToggle,
  });

  @override
  Widget build(BuildContext context) {
    final created = DateFormat.yMMMd().format(batch.createdAt);
    final statusColor = switch (batch.status) {
      'Planning' => Colors.blue,
      'Preparation' => Colors.orange,
      'Fermenting' => Colors.purple,
      'Completed' => Colors.green,
      _ => Colors.grey,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.receipt_long),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(batch.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _chip(context, 'Status', batch.status, statusColor),
                    _chip(context, 'Created', created, null),
                    if (batch.category?.isNotEmpty == true) _chip(context, 'Category', batch.category!, null),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 8,
              children: [
                IconButton(
                  tooltip: 'Change Status',
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: onChangeStatus,
                ),
                IconButton(
                  tooltip: brewModeEnabled ? 'Disable Brew Mode' : 'Enable Brew Mode',
                  icon: Icon(brewModeEnabled ? Icons.lightbulb : Icons.lightbulb_outline,
                      color: brewModeEnabled ? Colors.amber : null),
                  onPressed: onToggleBrewMode,
                ),
                IconButton(
                  tooltip: batch.isArchived ? 'Unarchive' : 'Archive',
                  icon: Icon(batch.isArchived ? Icons.unarchive : Icons.archive_outlined),
                  onPressed: onArchiveToggle,
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

Color _shade700Compat(Color c) {
  // If it's a MaterialColor, use the real shade700.
  if (c is MaterialColor) return c.shade700;
  // Otherwise, darken via HSL so it feels like a 700 tone.
  final hsl = HSLColor.fromColor(c);
  final darker = (hsl.lightness * 0.75).clamp(0.0, 1.0);
  return hsl.withLightness(darker).toColor();
}

Widget _chip(BuildContext context, String label, String value, Color? c) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  // Subtle colored background when an accent color is provided; otherwise surfaceVariant.
  final bg = c == null
      ? cs.surfaceVariant
      : Color.alphaBlend(c.withOpacity(0.15), cs.surfaceVariant);

  // Text color: onSurfaceVariant by default, or a darker accent for emphasis.
  final valueColor = c == null ? cs.onSurfaceVariant : _shade700Compat(c);

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label: ', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      Text(
        value,
        style: theme.textTheme.labelMedium?.copyWith(
          color: valueColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    ]),
  );
}
}