import 'package:flutter/material.dart';
import '../models/measurement.dart';
import 'add_measurement_dialog.dart';
import '../utils/gravity_utils.dart';

class MeasurementList extends StatelessWidget {
  final List<Measurement> measurements;
  final void Function(Measurement) onEdit;
  final void Function(Measurement) onDelete;

  const MeasurementList({
    super.key,
    required this.measurements,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (measurements.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No measurements logged yet.'),
      );
    }

    final sorted = measurements.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)); // newest first

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final m = sorted[index];
        final sgText = m.sg != null ? formatGravity(m.sg!) : '—';
        final brixText = m.brix != null ? formatBrix(m.brix!) : '—';
        final tempText = m.temperature != null ? '${m.temperature!.toStringAsFixed(1)}°C' : '—';
        final fsuText = m.fsuspeed != null ? m.fsuspeed!.toStringAsFixed(1) : '—';
        final dateText = m.timestamp.toLocal().toString().split(' ')[0];

        return ListTile(
          title: Text('Date: $dateText'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SG: $sgText | Brix: $brixText'),
              Text('Temp: $tempText | FSU: $fsuText'),
              if (m.note != null && m.note!.isNotEmpty)
                Text('Note: ${m.note}', style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                await showDialog(
                  context: context,
                  builder: (_) => AddMeasurementDialog(
                    existingMeasurement: m,
                    onSave: (updated) => onEdit(updated),
                  ),
                );
              } else if (value == 'delete') {
                onDelete(m);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        );
      },
    );
  }
}
