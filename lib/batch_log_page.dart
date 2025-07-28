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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batches'),
      ),
      body: ValueListenableBuilder<Box<BatchModel>>(
        valueListenable: Hive.box<BatchModel>('batches').listenable(),
        builder: (context, box, _) {
          if (box.values.isEmpty) {
            return const Center(child: Text('No batches yet. Tap + to create one.'));
          }

          return ListView(
            children: box.values.map((batch) {
              final sg = batch.measurementLogs.isNotEmpty
                  ? batch.measurementLogs.last.sg.toStringAsFixed(3)
                  : '—';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
}
