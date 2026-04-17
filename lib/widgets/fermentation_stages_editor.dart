import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/models/settings_model.dart';
import 'package:fermentacraft/utils/temp_display.dart';

String _unitSymbol(dynamic unit) {
  final s = unit?.toString().toLowerCase() ?? '';
  return s.contains('f') ? '°F' : '°C';
}

double _toC(double value, dynamic unit) {
  final s = unit?.toString().toLowerCase() ?? '';
  // If app is set to Fahrenheit, convert input -> °C; otherwise assume input is already °C
  return s.contains('f') ? (value - 32.0) * (5.0 / 9.0) : value;
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

  @override
  void didUpdateWidget(FermentationStagesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync with parent when stages externally changed (e.g., from dialog additions)
    if (!_areListsEqual(widget.stages, oldWidget.stages)) {
      _stages = List<FermentationStage>.from(widget.stages);
    }
  }

  bool _areListsEqual(List<FermentationStage> a, List<FermentationStage> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name ||
          a[i].durationDays != b[i].durationDays ||
          a[i].targetTempC != b[i].targetTempC) {
        return false;
      }
    }
    return true;
  }

  void _pushChange() => widget.onChanged(List<FermentationStage>.from(_stages));

  void _addStage() {
    final settings = context.read<SettingsModel>();
    final defaultTempC = settings.unit.toLowerCase().contains('f') ? 20.0 : 20.0;
    setState(() {
      _stages.add(FermentationStage(name: 'Stage ${_stages.length + 1}', durationDays: 7, targetTempC: defaultTempC));
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
                return _StageTile(
                  key: ValueKey('stage_tile_$i'),
                  stage: s,
                  unitSettings: unit,
                  unitSymbolStr: _unitSymbol(settings.unit),
                  onChanged: (updated) {
                    _stages[i] = updated;
                    _pushChange();
                  },
                  onRemove: () => _removeAt(i),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StageTile extends StatefulWidget {
  final FermentationStage stage;
  final String unitSettings;
  final String unitSymbolStr;
  final ValueChanged<FermentationStage> onChanged;
  final VoidCallback onRemove;

  const _StageTile({
    super.key,
    required this.stage,
    required this.unitSettings,
    required this.unitSymbolStr,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_StageTile> createState() => _StageTileState();
}

class _StageTileState extends State<_StageTile> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _daysCtrl;
  late final TextEditingController _tempCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.stage.name);
    _daysCtrl = TextEditingController(text: widget.stage.durationDays.toString());

    String tempText = '';
    final tempVal = widget.stage.targetTempC;
    if (tempVal != null) {
      final isF = widget.unitSettings.toLowerCase().contains('f');
      final v = isF ? tempVal.asFahrenheit : tempVal;
      tempText = v.toStringAsFixed(1);
    }
    _tempCtrl = TextEditingController(text: tempText);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _daysCtrl.dispose();
    _tempCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_StageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync _tempCtrl when widget.stage changes (e.g., recipe loaded or stage updated)
    if (widget.stage.targetTempC != oldWidget.stage.targetTempC ||
        widget.unitSettings != oldWidget.unitSettings) {
      final tempVal = widget.stage.targetTempC;
      if (tempVal != null) {
        final isF = widget.unitSettings.toLowerCase().contains('f');
        final v = isF ? tempVal.asFahrenheit : tempVal;
        _tempCtrl.text = v.toStringAsFixed(1);
      } else {
        _tempCtrl.text = '';
      }
    }
    // Sync name and days controllers too
    if (widget.stage.name != oldWidget.stage.name) {
      _nameCtrl.text = widget.stage.name;
    }
    if (widget.stage.durationDays != oldWidget.stage.durationDays) {
      _daysCtrl.text = widget.stage.durationDays.toString();
    }
  }

  void _push(FermentationStage next) {
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stage;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Stage name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      _push(FermentationStage(
                        name: v,
                        startDate: s.startDate,
                        durationDays: s.durationDays,
                        targetTempC: s.targetTempC,
                      ));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _daysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Days',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final d = int.tryParse(v) ?? s.durationDays;
                      _push(FermentationStage(
                        name: s.name,
                        startDate: s.startDate,
                        durationDays: d,
                        targetTempC: s.targetTempC,
                      ));
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: widget.onRemove,
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
                    controller: _tempCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Target Temp (${widget.unitSymbolStr})',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final t = double.tryParse(v);
                      double? newTempC;
                      if (t != null) {
                        newTempC = _toC(t, widget.unitSettings);
                      }
                      
                      _push(FermentationStage(
                        name: s.name,
                        startDate: s.startDate,
                        durationDays: s.durationDays,
                        targetTempC: newTempC,
                      ));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

