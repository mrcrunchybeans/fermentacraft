import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/batch_model.dart';
import 'package:intl/intl.dart';

class BatchDetailPage extends StatelessWidget {
  final BatchModel batch;

  const BatchDetailPage({super.key, required this.batch});

  @override
  Widget build(BuildContext context) {
    final DateFormat dateFormat = DateFormat('MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(batch.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // TODO: Implement batch editing
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            /// Summary card
            Card(
              elevation: 2,
              child: ListTile(
                title: Text('Batch Volume: ${batch.batchVolume ?? '—'} gal'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status: ${batch.status}'),
                    Text('Start: ${dateFormat.format(batch.startDate)}'),
                    if (batch.bottleDate != null)
                      Text('Bottled: ${dateFormat.format(batch.bottleDate!)}'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            /// Current Stats Card
            Card(
              child: ListTile(
                title: const Text('Current Readings'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SG: ${_latestSG(batch)}'),
                    Text('pH: ${_latestPH(batch)}'),
                    Text('Temp: ${_latestTemp(batch)}°C'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            /// Measurement Log
            Text('Measurement Logs', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _buildMeasurementLogsTable(batch),

            const SizedBox(height: 24),

            /// Fermentation Stages
            Text('Fermentation Stages', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _buildStageList(batch),

            const SizedBox(height: 24),

            /// Notes
            if ((batch.notes ?? '').isNotEmpty) ...[
              Text('Notes', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(batch.notes!),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add_chart),
        onPressed: () {
          // TODO: Add measurement or stage
        },
      ),
    );
  }

  String _latestSG(BatchModel batch) {
    return batch.measurementLogs.isNotEmpty
        ? batch.measurementLogs.last.sg.toStringAsFixed(3)
        : '—';
  }

  String _latestTemp(BatchModel batch) {
    final latest = batch.measurementLogs.lastOrNull;
    return latest?.tempC?.toStringAsFixed(1) ?? '—';
  }

  String _latestPH(BatchModel batch) {
    final latest = batch.measurementLogs.lastOrNull;
    return latest?.pH?.toStringAsFixed(2) ?? '—';
  }

  Widget _buildMeasurementLogsTable(BatchModel batch) {
    final logs = batch.measurementLogs.reversed.toList();
    if (logs.isEmpty) return const Text('No logs yet.');

    return DataTable(
      columns: const [
        DataColumn(label: Text('Date')),
        DataColumn(label: Text('SG')),
        DataColumn(label: Text('Temp')),
        DataColumn(label: Text('pH')),
      ],
      rows: logs.map((log) {
        return DataRow(cells: [
          DataCell(Text(DateFormat('MMM d').format(log.timestamp))),
          DataCell(Text(log.sg.toStringAsFixed(3))),
          DataCell(Text(log.tempC?.toStringAsFixed(1) ?? '—')),
          DataCell(Text(log.pH?.toStringAsFixed(2) ?? '—')),
        ]);
      }).toList(),
    );
  }

  Widget _buildStageList(BatchModel batch) {
    final stages = batch.stages;
    if (stages.isEmpty) return const Text('No fermentation stages added.');

    return Column(
      children: stages.map((stage) {
        return Card(
          child: ListTile(
            title: Text(stage.name),
            subtitle: Text(
              'Start: ${DateFormat('MMM d').format(stage.startDate)}\n'
              'Duration: ${stage.durationDays} days\n'
              'Target Temp: ${stage.targetTempC?.toStringAsFixed(1) ?? '—'}°C',
            ),
          ),
        );
      }).toList(),
    );
  }
}
