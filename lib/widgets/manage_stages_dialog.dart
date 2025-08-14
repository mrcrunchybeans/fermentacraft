import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/utils/temp_display.dart';
import '../models/settings_model.dart';

// ── Small helpers ──────────────────────────────────────────────────────────────
double? cToF(double? c) => (c == null) ? null : (c * 9.0 / 5.0) + 32.0;
double? fToC(double? f) => (f == null) ? null : (f - 32.0) * 5.0 / 9.0;

String _yyyyMmDd(DateTime d) => d.toLocal().toString().split(' ').first;

// ── Dialog ────────────────────────────────────────────────────────────────────
class ManageStagesDialog extends StatefulWidget {
  final List<FermentationStage> initialStages;

  /// Optional: anchor the first stage to a specific date (e.g., batch.startDate).
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
  late List<FermentationStage> _stages;

  @override
  void initState() {
    super.initState();
    // Work on a copy so we don’t mutate the caller’s list until Save.
    _stages = widget.initialStages.map((s) => s.copy()).toList();
    _normalizeStageDates();
  }

  /// Ensure contiguous dates in current order.
  /// - First stage uses `anchorStartDate` (if provided) else existing startDate or today.
  /// - Each subsequent stage starts the day the previous one ends.
  void _normalizeStageDates() {
    if (_stages.isEmpty) return;

    final firstAnchor =
        widget.anchorStartDate ?? _stages.first.startDate ?? DateTime.now();
    _stages.first.startDate =
        DateTime(firstAnchor.year, firstAnchor.month, firstAnchor.day);

    for (int i = 1; i < _stages.length; i++) {
      final prev = _stages[i - 1];
      final prevStart = prev.startDate!;
      final prevEnd = prevStart.add(Duration(days: prev.durationDays));
      _stages[i].startDate =
          DateTime(prevEnd.year, prevEnd.month, prevEnd.day);
    }
  }

  Future<void> _addStage() async {
    // Default start date for the new stage = day after last stage ends (or anchor/today).
    final DateTime startForNew;
    if (_stages.isEmpty) {
      startForNew = widget.anchorStartDate ?? DateTime.now();
    } else {
      final last = _stages.last;
      final lastStart =
          last.startDate ?? (widget.anchorStartDate ?? DateTime.now());
      final lastEnd = lastStart.add(Duration(days: last.durationDays));
      startForNew = DateTime(lastEnd.year, lastEnd.month, lastEnd.day);
    }

    // Default temp: 18°C (≈64°F). Shown in user’s unit in the editor.
    final draft = FermentationStage(
      name: 'New Stage',
      startDate: startForNew,
      durationDays: 7,
      targetTempC: 18.0,
    );

    final edited = await showDialog<FermentationStage>(
      context: context,
      builder: (_) => _StageEditorDialog(stage: draft),
    );

    if (edited != null) {
      setState(() {
        _stages.add(edited);
        _normalizeStageDates();
      });
    }
  }

  Future<void> _editStage(int index) async {
    final edited = await showDialog<FermentationStage>(
      context: context,
      builder: (_) => _StageEditorDialog(stage: _stages[index]),
    );

    if (edited != null) {
      setState(() {
        _stages[index] = edited;
        _normalizeStageDates();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>(); // for subtitle unit display

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
                  itemCount: _stages.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final moved = _stages.removeAt(oldIndex);
                      _stages.insert(newIndex, moved);
                      _normalizeStageDates();
                    });
                  },
                  itemBuilder: (context, index) {
                    final stage = _stages[index];
                    final start = stage.startDate;
                    final startString =
                        (start == null) ? 'Not set' : _yyyyMmDd(start);

                    return ListTile(
                      key: ValueKey(
                        'stage_${stage.name}_${stage.startDate?.millisecondsSinceEpoch ?? 0}_$index',
                      ),
                      title: Text(stage.name),
                      subtitle: Text(
                        'Start: $startString, '
                        'Duration: ${stage.durationDays}d, '
                        'Temp: ${stage.targetTempC?.toDisplay(targetUnit: settings.unit) ?? 'N/A'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editStage(index),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _stages.removeAt(index);
                                _normalizeStageDates();
                              });
                            },
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.drag_handle),
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
                        List<FermentationStage>.from(_stages),
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

// ── Editor ────────────────────────────────────────────────────────────────────
class _StageEditorDialog extends StatefulWidget {
  final FermentationStage stage;

  const _StageEditorDialog({required this.stage});

  @override
  State<_StageEditorDialog> createState() => _StageEditorDialogState();
}

class _StageEditorDialogState extends State<_StageEditorDialog> {
  late final TextEditingController _nameC;
  late final TextEditingController _durationC;
  late final TextEditingController _tempC; // holds UI-unit value as text
  late DateTime _startDate;

  bool get _useCelsius => context.read<SettingsModel>().useCelsius;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController(text: widget.stage.name);
    _durationC =
        TextEditingController(text: widget.stage.durationDays.toString());
    _startDate = widget.stage.startDate ?? DateTime.now();

    // Seed temp field in user's preferred unit
    final uiTemp =
        _useCelsius ? widget.stage.targetTempC : cToF(widget.stage.targetTempC);
    _tempC = TextEditingController(
      text: (uiTemp == null) ? '' : uiTemp.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _nameC.dispose();
    _durationC.dispose();
    _tempC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useC = context.watch<SettingsModel>().useCelsius;
    final unitLabel = useC ? '°C' : '°F';

    return AlertDialog(
      title: const Text('Edit Stage'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              controller: _nameC,
              decoration: const InputDecoration(labelText: 'Stage Name'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _durationC,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                      initialDate: _startDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _startDate = picked);
                  },
                  child: Text(_yyyyMmDd(_startDate)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tempC,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))
              ],
              decoration: InputDecoration(
                labelText: 'Target Temp ($unitLabel)',
                suffixText: unitLabel,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final name =
                _nameC.text.trim().isEmpty ? 'Stage' : _nameC.text.trim();
            final duration = int.tryParse(_durationC.text) ?? 7;

            // Convert UI value (°C or °F) back to °C for storage.
            final uiVal = double.tryParse(_tempC.text);
            final targetTempC = useC ? uiVal : fToC(uiVal);

            final updated = FermentationStage(
              name: name,
              startDate: _startDate,
              durationDays: duration,
              targetTempC: targetTempC,
            );
            Navigator.pop(context, updated);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
