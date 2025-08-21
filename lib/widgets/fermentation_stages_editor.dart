import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/models/settings_model.dart';
import 'package:fermentacraft/utils/temp_display.dart';

String _unitSymbol(dynamic unit) {
  final s = unit?.toString().toLowerCase() ?? '';
  return s.startsWith('f') ? '°F' : '°C';
}

double _toC(double value, dynamic unit) {
  final s = unit?.toString().toLowerCase() ?? '';
  // If app is set to Fahrenheit, convert input -> °C; otherwise assume input is already °C
  return s.startsWith('f') ? (value - 32.0) * (5.0 / 9.0) : value;
}

class FermentationStagesEditor extends StatefulWidget {
  final List<FermentationStage> stages;
  final ValueChanged<List<FermentationStage>> onChanged;

  const FermentationStagesEditor({
    super.key,
    required this.stages,
    required this.onChanged,
  });

  @override
  State<FermentationStagesEditor> createState() => _FermentationStagesEditorState();
}

class _FermentationStagesEditorState extends State<FermentationStagesEditor> {
  late List<FermentationStage> _stages;

  @override
  void initState() {
    super.initState();
    _stages = List<FermentationStage>.from(widget.stages);
  }

  void _pushChange() => widget.onChanged(List<FermentationStage>.from(_stages));

  void _addStage() {
    setState(() {
      _stages.add(FermentationStage(name: 'Stage ${_stages.length + 1}', durationDays: 7, targetTempC: 20));
    });
    _pushChange();
  }

  void _removeAt(int index) {
    setState(() { _stages.removeAt(index); });
    _pushChange();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final unit = settings.unit; // °C or °F

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.timeline),
                const SizedBox(width: 8),
                Text('Fermentation Stages', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(onPressed: _addStage, icon: const Icon(Icons.add)),
              ],
            ),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: _stages.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _stages.removeAt(oldIndex);
                  _stages.insert(newIndex, item);
                });
                _pushChange();
              },
              itemBuilder: (context, i) {
                final s = _stages[i];
                final tempDisplay = s.targetTempC?.toDisplay(targetUnit: unit) ?? '';
                final tempController = TextEditingController(
                  text: tempDisplay.isEmpty ? '' : tempDisplay.toString(),
                );

                return Card(
                  key: ValueKey('stage_$i'),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: s.name,
                                decoration: const InputDecoration(
                                  labelText: 'Stage name',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  _stages[i] = s.copyWith(name: v);
                                  _pushChange();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 120,
                              child: TextFormField(
                                initialValue: s.durationDays.toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Days',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                  final d = int.tryParse(v) ?? s.durationDays;
                                  _stages[i] = s.copyWith(durationDays: d);
                                  _pushChange();
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              onPressed: () => _removeAt(i),
                              icon: const Icon(Icons.delete_outline),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.drag_handle),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: tempController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                labelText: 'Target Temp (${_unitSymbol(settings.unit)})',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (v) {
                                final t = double.tryParse(v);
                                if (t == null) return;
                                final c = _toC(t, settings.unit); // convert entered UI value -> °C for storage
                                _stages[i] = s.copyWith(targetTempC: c);
                                _pushChange();
                              },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
