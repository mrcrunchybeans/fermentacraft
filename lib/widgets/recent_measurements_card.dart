// lib/widgets/recent_measurements_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/measurement.dart';

class RecentMeasurementsCard extends StatelessWidget {
  const RecentMeasurementsCard({
    super.key,
    required this.measurements,
    this.deviceName,
    this.maxItems = 12,
    required this.onOpenFullLog,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Measurement> measurements;
  final String? deviceName;
  final int maxItems;
  final VoidCallback onOpenFullLog;
  final void Function(Measurement) onEdit;
  final void Function(Measurement) onDelete;

  @override
  Widget build(BuildContext context) {
    if (measurements.isEmpty) return const SizedBox.shrink();

    // newest first
    final items = [...measurements]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // group by day
    final byDay = <DateTime, List<Measurement>>{};
    for (final m in items) {
      final d = DateTime(m.timestamp.year, m.timestamp.month, m.timestamp.day);
      byDay.putIfAbsent(d, () => []).add(m);
    }

    int added = 0; // global cap across all days
    String fmt(Measurement m) {
      final t = DateFormat.Md().add_jm().format(m.timestamp.toLocal());
      final g = (m.gravity != null)
          ? m.gravity!.toStringAsFixed(3)
          : (m.brix != null) ? '${m.brix!.toStringAsFixed(1)}°Bx' : '—';
      final temp = (m.temperature != null) ? '${m.temperature!.toStringAsFixed(1)}°C' : '—';
      final fsu = (m.fsuspeed != null) ? ' · FSU ${m.fsuspeed!.toStringAsFixed(0)}' : '';
      return '$t  ·  SG $g  ·  $temp$fsu';
    }

    Widget badge(Measurement m) {
      if (m.fromDevice != true) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(deviceName ?? 'device'),
      );
    }

    final dayKeys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Recent measurements', style: TextStyle(fontWeight: FontWeight.w600))),
                TextButton.icon(onPressed: onOpenFullLog, icon: const Icon(Icons.list), label: const Text('Open full log')),
              ],
            ),
            const SizedBox(height: 4),
            for (final day in dayKeys) ...[
              if (added >= maxItems) const SizedBox.shrink() else _DayHeader(date: day),
              if (added >= maxItems) const SizedBox.shrink() else const SizedBox(height: 4),
              if (added >= maxItems) const SizedBox.shrink() else
              ...byDay[day]!.map((m) {
                if (added >= maxItems) return const SizedBox.shrink();
                added++;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(fmt(m)),
                  leading: Icon(m.fromDevice == true ? Icons.sensors : Icons.edit_note),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      badge(m),
                      const SizedBox(width: 6),
                      if (m.fromDevice != true)
                        IconButton(tooltip: 'Edit',   icon: const Icon(Icons.edit),           onPressed: () => onEdit(m)),
                      if (m.fromDevice != true)
                        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => onDelete(m)),
                    ],
                  ),
                );
              }),
              if (added < maxItems) const Divider(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final label = DateFormat.yMMMd().format(date);
    return Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
        const SizedBox(width: 8),
        const Expanded(child: Divider()),
      ],
    );
  }
}
