import 'package:flutter/material.dart';
import '../../models/measurement.dart';
import '../../models/fermentation_stage.dart';
import '../section.dart';
import '../fermentation_chart.dart';

class MeasurementsCard extends StatelessWidget {
  final List<Measurement> measurements;
  final List<FermentationStage> stages;
  final Future<Measurement?> Function(Measurement? previous, DateTime? firstDate) onAdd;
  final Future<Measurement?> Function(Measurement toEdit, Measurement? previous, DateTime? firstDate) onEdit;
  final void Function(Measurement toDelete) onDelete;
  final VoidCallback onManageStages;

  const MeasurementsCard({
    super.key,
    required this.measurements,
    required this.stages,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onManageStages,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...measurements]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final previous = sorted.isNotEmpty ? sorted.last : null;
    final firstDate = sorted.isNotEmpty ? sorted.first.timestamp : null;

    return SectionCard(
      title: 'Fermentation Progress',
      trailing: Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.layers),
            label: const Text('Manage Stages'),
            onPressed: onManageStages,
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Measurement'),
            onPressed: () async {
              final m = await onAdd(previous, firstDate);
              if (m == null) return;
            },
          ),
        ],
      ),
      child: FermentationChartWidget(
        measurements: sorted,
        stages: stages,
        onEditMeasurement: (m) async {
          final idx = sorted.indexWhere((x) => x.id == m.id);
          final prev = (idx > 0) ? sorted[idx - 1] : null;
          final updated = await onEdit(m, prev, firstDate);
          if (updated == null) return;
        },
        onDeleteMeasurement: onDelete,
        onManageStages: onManageStages,
      ),
    );
  }
}
