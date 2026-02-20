// lib/widgets/batch_detail/measurement_section.dart
import 'package:flutter/material.dart';
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/models/measurement.dart';
import 'package:fermentacraft/models/settings_model.dart';
import 'package:fermentacraft/widgets/fermentation_chart_improved.dart';
import 'package:provider/provider.dart';

/// Measurement section for batch detail page
/// Displays fermentation chart and measurement list
class MeasurementSection extends StatelessWidget {
  const MeasurementSection({
    super.key,
    required this.batch,
    required this.measurements,
    required this.chartRangeNotifier,
    required this.onAddMeasurement,
    required this.onEditMeasurement,
    required this.onDeleteMeasurement,
    this.deviceMeasurements = const [],
    this.deviceName,
  });

  final BatchModel batch;
  final List<Measurement> measurements;
  final ValueNotifier<ChartRange> chartRangeNotifier;
  final VoidCallback onAddMeasurement;
  final void Function(Measurement) onEditMeasurement;
  final void Function(Measurement) onDeleteMeasurement;
  final List<Measurement> deviceMeasurements;
  final String? deviceName;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final useFahrenheit = !settings.useCelsius;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        const SizedBox(height: 12),
        ValueListenableBuilder<ChartRange>(
          valueListenable: chartRangeNotifier,
          builder: (context, chartRange, child) {
            final combined = _mergeMeasurements(measurements, deviceMeasurements);
            final capped = _capMeasurements(combined, chartRange);

            return ImprovedFermentationChartPanel(
              measurements: capped,
              useFahrenheit: useFahrenheit,
              sincePitchingAt: _inferPitchTime(),
              initialRange: chartRange,
              onRangeChanged: (r) => chartRangeNotifier.value = r,
            );
          },
        ),
        const SizedBox(height: 16),
        _buildMeasurementList(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            'Fermentation Progress',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add Measurement'),
          onPressed: onAddMeasurement,
        ),
      ],
    );
  }

  Widget _buildMeasurementList(BuildContext context) {
    if (measurements.isEmpty && deviceMeasurements.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.science_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  'No measurements yet',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final combined = _mergeMeasurements(measurements, deviceMeasurements);
    final sorted = combined.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sorted.length > 10 ? 10 : sorted.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final measurement = sorted[index];
        final isLocal = measurements.contains(measurement);

        return ListTile(
          leading: Icon(
            isLocal ? Icons.edit : Icons.sensors,
            color: isLocal ? Theme.of(context).colorScheme.primary : Colors.grey,
          ),
          title: Text(_formatMeasurement(measurement)),
          subtitle: Text(_formatTimestamp(measurement.timestamp)),
          trailing: isLocal
              ? PopupMenuButton(
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEditMeasurement(measurement);
                    } else if (value == 'delete') {
                      onDeleteMeasurement(measurement);
                    }
                  },
                )
              : null,
        );
      },
    );
  }

  List<Measurement> _mergeMeasurements(
    List<Measurement> local,
    List<Measurement> device,
  ) {
    final combined = <Measurement>[...local, ...device];
    combined.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return combined;
  }

  List<Measurement> _capMeasurements(
    List<Measurement> measurements,
    ChartRange range,
  ) {
    const kSincePitchMaxPoints = 5000;
    final maxPoints = range == ChartRange.sincePitch ? kSincePitchMaxPoints : 600;
    
    if (measurements.length <= maxPoints) {
      return measurements;
    }
    
    // Keep first and last, downsample middle
    final step = measurements.length / maxPoints;
    final result = <Measurement>[];
    
    for (int i = 0; i < measurements.length; i++) {
      if (i == 0 || i == measurements.length - 1 || i % step.ceil() == 0) {
        result.add(measurements[i]);
      }
    }
    
    return result;
  }

  DateTime? _inferPitchTime() {
    return batch.startDate;
  }

  String _formatMeasurement(Measurement m) {
    final parts = <String>[];
    
    if (m.gravity != null) {
      parts.add('SG: ${m.gravity!.toStringAsFixed(3)}');
    }
    if (m.temperature != null) {
      parts.add('${m.temperature!.toStringAsFixed(1)}°C');
    }
    
    return parts.isEmpty ? 'No data' : parts.join(' • ');
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    
    if (diff.inDays == 0) {
      return 'Today ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${dt.month}/${dt.day}/${dt.year}';
    }
  }
}
