import 'package:flutter/material.dart';
import 'package:flutter_application_1/batch_detail_page.dart';
import 'package:flutter_application_1/models/batch_model.dart';
import 'package:flutter_application_1/widgets/add_batch_dialog.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

class BatchLogPage extends StatefulWidget {
  const BatchLogPage({super.key});

  @override
  State<BatchLogPage> createState() => _BatchLogPageState();
}

class _BatchLogPageState extends State<BatchLogPage> {
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  // State to toggle between active and archived views.
  bool _showArchived = false;

  // Handles archiving/unarchiving a batch.
  void _toggleArchiveStatus(BatchModel batch) {
    final isArchiving = !batch.isArchived;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isArchiving ? "Archive Batch?" : "Unarchive Batch?"),
        content: Text(
            'Are you sure you want to ${isArchiving ? 'archive' : 'unarchive'} "${batch.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                batch.isArchived = isArchiving;
                batch.save();
              });
              Navigator.pop(context);
            },
            child: Text(isArchiving ? "Archive" : "Unarchive"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Title changes based on the current view.
        title: Text(_showArchived ? 'Archived Batches' : 'Batches'),
        // Action button to toggle the archived view.
        actions: [
          IconButton(
            icon: Icon(_showArchived ? Icons.inventory_2_outlined : Icons.archive_outlined),
            tooltip: _showArchived ? 'View Active Batches' : 'View Archived',
            onPressed: () {
              setState(() {
                _showArchived = !_showArchived;
              });
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<BatchModel>>(
        valueListenable: Hive.box<BatchModel>('batches').listenable(),
        builder: (context, box, _) {
          // Filter batches based on the current view (archived or not).
          final batches = box.values
              .where((batch) => batch.isArchived == _showArchived)
              .toList();

          if (batches.isEmpty) {
            return Center(
                child: Text(_showArchived
                    ? 'No archived batches.'
                    : 'No batches yet. Tap + to create one.'));
          }

          // Group batches into "Active" and "Completed".
          final activeBatches =
              batches.where((b) => b.status != 'Completed').toList();
          final completedBatches =
              batches.where((b) => b.status == 'Completed').toList();

          return ListView(
            children: [
              if (activeBatches.isNotEmpty)
                _buildBatchGroup(context, 'Active', activeBatches),
              if (completedBatches.isNotEmpty)
                _buildBatchGroup(context, 'Completed', completedBatches),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await showDialog(
            context: context,
            builder: (_) => const AddBatchDialog(),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  // Helper widget to build the expandable groups.
  Widget _buildBatchGroup(
      BuildContext context, String title, List<BatchModel> batches) {
    return Card(
      margin: const EdgeInsets.all(12.0),
      child: ExpansionTile(
        title: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        initiallyExpanded: true,
        children: batches.map((batch) {
          final sg = batch.safeMeasurements.isNotEmpty
              ? batch.safeMeasurements.last.gravity?.toStringAsFixed(3)
              : '—';

          return GestureDetector(
            // Added long press to archive completed batches.
            onLongPress:
                batch.status == 'Completed' || batch.isArchived
                    ? () => _toggleArchiveStatus(batch)
                    : null,
            child: ListTile(
              title: Text(batch.name),
              subtitle: Text(
                'Started: ${_dateFormat.format(batch.startDate)}\n'
                'Status: ${batch.status}\n'
                'Current SG: $sg',
              ),
              isThreeLine: true,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BatchDetailPage(batch: batch),
                  ),
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}
