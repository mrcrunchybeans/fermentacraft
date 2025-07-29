import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/batch_model.dart';
import '../models/fermentation_stage.dart';
import '../models/measurement.dart';

class BatchSummaryCard extends StatelessWidget {
  final BatchModel batch;

  const BatchSummaryCard({super.key, required this.batch});

  int get daysInProcess {
    return DateTime.now().difference(batch.startDate).inDays;
  }

  FermentationStage? get currentStage {
    final today = DateTime.now();
    for (final stage in batch.fermentationStages) {
      final start = stage.startDate;
      if (start == null) continue;
      
      final end = start.add(Duration(days: stage.durationDays));
      if (today.isAfter(start) && today.isBefore(end)) {
        return stage;
      }
    }
    return null;
  }

  FermentationStage? get nextStage {
    final today = DateTime.now();
    final upcoming = batch.fermentationStages
        .where((s) => s.startDate != null && s.startDate!.isAfter(today));
    if (upcoming.isEmpty) return null;
    // Find the upcoming stage with the earliest start date
    return upcoming.reduce((a, b) =>
        a.startDate!.isBefore(b.startDate!) ? a : b);
  }

  Measurement? get latestMeasurement {
    if (batch.measurements.isEmpty) return null;
    // Find the latest measurement that has a valid fsuspeed
    return batch.measurements
        .where((m) => m.fsuspeed != null) // FIXED: Changed from fsu to fsuspeed
        .fold<Measurement?>(null, (prev, curr) {
      if (prev == null || curr.timestamp.isAfter(prev.timestamp)) {
        return curr;
      }
      return prev;
    });
  }

  @override
  Widget build(BuildContext context) {
    final stage = currentStage;
    final next = nextStage;
    final measurement = latestMeasurement;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(batch.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _infoTile('Started', DateFormat('yMMMd').format(batch.startDate)),
                _infoTile('Days Active', '$daysInProcess'),
                _infoTile('Stage', stage?.name ?? '—'),
                _infoTile('Next Stage',
                    next?.startDate != null ? DateFormat('yMMMd').format(next!.startDate!) : '—'),
                // FIXED: Changed from fsu to fsuspeed
                _infoTile('FSU', measurement?.fsuspeed?.toStringAsFixed(1) ?? '—'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }
}