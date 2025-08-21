import 'package:flutter/material.dart';
import '../../models/batch_model.dart';
import '../../services/batch_extras_repo.dart';
import '../../services/gravity_service.dart';
import '../section.dart';

class BatchStatsCard extends StatelessWidget {
  final BatchModel batch;
  final Future<void> Function() onEditSummary; // opens your “Edit Targets” dialog
  const BatchStatsCard({super.key, required this.batch, required this.onEditSummary});

  @override
  Widget build(BuildContext context) {
    final extrasFuture = BatchExtrasRepo().getOrCreate(batch.id);

    return FutureBuilder(
      future: extrasFuture,
      builder: (context, snap) {
        final extras = snap.data;
        final useMeasured = extras?.useMeasuredOg == true;
        final measuredOg = extras?.measuredOg;

        final og = (useMeasured && measuredOg != null && measuredOg > 1.0)
            ? measuredOg
            : (batch.og ?? batch.plannedOg);

        final fg = batch.fg;
        final abv = (og != null && fg != null) ? GravityService.abv(og: og, fg: fg) : null;

        return SectionCard(
          title: 'Batch Stats',
          trailing: OutlinedButton.icon(
            icon: const Icon(Icons.flag),
            label: const Text('Edit Targets'),
            onPressed: onEditSummary,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8, runSpacing: 8, children: [
                  MetricChip(icon: Icons.bubble_chart, label: 'OG', value: og?.toStringAsFixed(3) ?? '—'),
                  MetricChip(icon: Icons.water_drop, label: 'FG', value: fg?.toStringAsFixed(3) ?? '—'),
                  MetricChip(icon: Icons.percent, label: 'ABV',
                    value: abv == null ? '—' : '${abv.toStringAsFixed(2)}%'),
                  MetricChip(icon: Icons.local_drink, label: 'Target Vol',
                    value: batch.batchVolume == null ? '—' : '${batch.batchVolume!.toStringAsFixed(1)} gal'),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: (measuredOg != null && measuredOg > 1.0) ? measuredOg.toStringAsFixed(3) : '',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Measured OG (e.g., 1.072)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) async {
                  final p = double.tryParse(v);
                  await BatchExtrasRepo().setMeasuredOg(batch.id, (p != null && p > 1.0) ? p : null);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use measured OG for ABV'),
                value: useMeasured,
                onChanged: (v) async => BatchExtrasRepo().setUseMeasuredOg(batch.id, v),
              ),
            ],
          ),
        );
      },
    );
  }
}
