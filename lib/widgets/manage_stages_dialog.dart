import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/fermentation_stage.dart';
import 'package:flutter_application_1/utils/temp_display.dart';

class ManageStagesDialog extends StatefulWidget {
  final List<FermentationStage> initialStages;

  const ManageStagesDialog({super.key, required this.initialStages});

  @override
  State<ManageStagesDialog> createState() => _ManageStagesDialogState();
}

class _ManageStagesDialogState extends State<ManageStagesDialog> {
  late List<FermentationStage> stages;

  @override
  void initState() {
    stages = List.from(widget.initialStages); // Make mutable copy
    super.initState();
  }

  void _addStage() async {
    final now = DateTime.now();
    final newStage = await showDialog<FermentationStage>(
      context: context,
      builder: (_) => _StageEditorDialog(
        stage: FermentationStage(
          name: 'New Stage',
          startDate: now,
          durationDays: 7,
          targetTempC: 18.0,
        ),
      ),
    );

    if (newStage != null) {
      setState(() => stages.add(newStage));
    }
  }

  void _editStage(int index) async {
    final edited = await showDialog<FermentationStage>(
      context: context,
      builder: (_) => _StageEditorDialog(stage: stages[index]),
    );

    if (edited != null) {
      setState(() => stages[index] = edited);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Material(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        const Text("Manage Fermentation Stages", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: stages.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = stages.removeAt(oldIndex);
                stages.insert(newIndex, item);
              });
            },
            itemBuilder: (context, index) {
              final stage = stages[index];
              return ListTile(
                key: ValueKey(stage.name + stage.startDate!.toIso8601String()),
                title: Text(stage.name),
                subtitle: Text(
                  'Start: ${stage.startDate?.toLocal().toString().split(' ')[0]}, '
                  'Duration: ${stage.durationDays}d, '
                  'Temp: ${TempDisplay.format(stage.targetTempC ?? 0)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _editStage(index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => setState(() => stages.removeAt(index)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("Add Stage"),
              onPressed: _addStage,
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text("Save & Close"),
              onPressed: () => Navigator.pop(context, List<FermentationStage>.from(stages)),
            ),
          ],
        ),
      ],
    ),
  ),
),
    );
  }
}



class _StageEditorDialog extends StatefulWidget {
  final FermentationStage stage;

  const _StageEditorDialog({required this.stage});

  @override
  State<_StageEditorDialog> createState() => _StageEditorDialogState();
}

class _StageEditorDialogState extends State<_StageEditorDialog> {
  late TextEditingController nameController;
  late TextEditingController durationController;
  late TextEditingController tempController;
  late DateTime startDate;

  @override
  void initState() {
    nameController = TextEditingController(text: widget.stage.name);
    durationController = TextEditingController(text: widget.stage.durationDays.toString());
    tempController = TextEditingController(text: widget.stage.targetTempC?.toString() ?? '');
    startDate = widget.stage.startDate!;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Stage'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Stage Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Duration (days)'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Start Date:'),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => startDate = picked);
                  },
                  child: Text(startDate.toLocal().toString().split(' ')[0]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tempController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Target Temp (°C)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final newStage = FermentationStage(
              name: nameController.text,
              startDate: startDate,
              durationDays: int.tryParse(durationController.text) ?? 7,
              targetTempC: double.tryParse(tempController.text),
            );
            Navigator.pop(context, newStage);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
