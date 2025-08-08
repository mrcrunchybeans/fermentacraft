import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/utils/temp_display.dart';
import '../models/settings_model.dart';

class ManageStagesDialog extends StatefulWidget {
  final List<FermentationStage> initialStages;

  /// Optional: anchor the first stage to a specific date (e.g., the batch startDate).
  final DateTime? anchorStartDate;

  const ManageStagesDialog({
    super.key,
    required this.initialStages,
    this.anchorStartDate,
  });

  @override
  State<ManageStagesDialog> createState() => _ManageStagesDialogState();
}

class _ManageStagesDialogState extends State<ManageStagesDialog> {
  late List<FermentationStage> stages;

  @override
  void initState() {
    super.initState();
    // Make a mutable copy so edits don't mutate the original list until Save.
    stages = widget.initialStages.map((s) => s.copy()).toList();
    _normalizeStageDates(); // ensure contiguity on open
  }

  /// Ensures stages have contiguous dates in current order.
  /// - First stage uses `anchorStartDate` (if provided) else existing startDate or today.
  /// - Each subsequent stage starts right after the previous stage ends.
  void _normalizeStageDates() {
    if (stages.isEmpty) return;

    // First stage anchor
    final firstAnchor =
        widget.anchorStartDate ?? stages.first.startDate ?? DateTime.now();
    stages.first.startDate = DateTime(
      firstAnchor.year,
      firstAnchor.month,
      firstAnchor.day,
    );

    // Chain subsequent stages
    for (int i = 1; i < stages.length; i++) {
      final prev = stages[i - 1];
      final prevStart = prev.startDate!;
      final prevEnd = prevStart.add(Duration(days: prev.durationDays));
      stages[i].startDate = DateTime(prevEnd.year, prevEnd.month, prevEnd.day);
    }

    setState(() {});
  }

  Future<void> _addStage() async {
    final DateTime startForNew;
    if (stages.isEmpty) {
      startForNew = widget.anchorStartDate ?? DateTime.now();
    } else {
      final last = stages.last;
      final lastStart = last.startDate ?? (widget.anchorStartDate ?? DateTime.now());
      final lastEnd = lastStart.add(Duration(days: last.durationDays));
      startForNew = DateTime(lastEnd.year, lastEnd.month, lastEnd.day);
    }

    final newStage = await showDialog<FermentationStage>(
      context: context,
      builder: (_) => _StageEditorDialog(
        stage: FermentationStage(
          name: 'New Stage',
          startDate: startForNew,
          durationDays: 7,
          targetTempC: 18.0,
        ),
      ),
    );

    if (newStage != null) {
      setState(() {
        stages.add(newStage);
        _normalizeStageDates(); // keep everything contiguous
      });
    }
  }

  Future<void> _editStage(int index) async {
    final edited = await showDialog<FermentationStage>(
      context: context,
      builder: (_) => _StageEditorDialog(stage: stages[index]),
    );

    if (edited != null) {
      setState(() {
        stages[index] = edited;
        _normalizeStageDates(); // recalc dates after duration/name/temp changes
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Material(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                "Manage Fermentation Stages",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: stages.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = stages.removeAt(oldIndex);
                      stages.insert(newIndex, item);
                      _normalizeStageDates(); // keep dates contiguous after reorder
                    });
                  },
                  itemBuilder: (context, index) {
                    final stage = stages[index];
                    final startDateString =
                        stage.startDate?.toLocal().toString().split(' ').first ?? 'Not set';

                    return ListTile(
                      key: ValueKey(
                        '${stage.name}_${stage.startDate?.millisecondsSinceEpoch ?? 0}_$index',
                      ),
                      title: Text(stage.name),
                      subtitle: Text(
                        'Start: $startDateString, '
                        'Duration: ${stage.durationDays}d, '
                        'Temp: ${stage.targetTempC?.toDisplay(targetUnit: settings.unit) ?? 'N/A'}',
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
                            onPressed: () {
                              setState(() {
                                stages.removeAt(index);
                                _normalizeStageDates();
                              });
                            },
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
                    onPressed: () {
                      _normalizeStageDates(); // final pass
                      Navigator.pop(
                        context,
                        List<FermentationStage>.from(stages),
                      );
                    },
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
    super.initState();
    nameController = TextEditingController(text: widget.stage.name);
    durationController = TextEditingController(text: widget.stage.durationDays.toString());
    tempController = TextEditingController(text: widget.stage.targetTempC?.toString() ?? '');
    startDate = widget.stage.startDate ?? DateTime.now();
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
                  child: Text(startDate.toLocal().toString().split(' ').first),
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
              name: nameController.text.trim().isEmpty ? 'Stage' : nameController.text.trim(),
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
