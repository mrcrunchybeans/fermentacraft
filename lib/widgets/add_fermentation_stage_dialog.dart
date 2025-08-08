import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/temp_display.dart'; // your C/F extension helpers
import '../models/settings_model.dart';
import '../models/fermentation_stage.dart';

class AddFermentationStageDialog extends StatefulWidget {
  final FermentationStage? existing;
  final Function(FermentationStage) onSave;

  const AddFermentationStageDialog({
    super.key,
    this.existing,
    required this.onSave,
  });

  @override
  State<AddFermentationStageDialog> createState() =>
      _AddFermentationStageDialogState();
}

class _AddFermentationStageDialogState extends State<AddFermentationStageDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _durationController;
  late TextEditingController _tempController;

  /// Internal unit: 'c' or 'f'
  late String _unit;

  @override
  void initState() {
    super.initState();

    // Pull user preference once (safe to read in initState).
    final settings = context.read<SettingsModel>();
    _unit = settings.unit.toLowerCase().contains('c') ? 'c' : 'f';

    _nameController =
        TextEditingController(text: widget.existing?.name ?? 'Primary');
    _durationController = TextEditingController(
        text: (widget.existing?.durationDays ?? 14).toString());

    final initialTempC = widget.existing?.targetTempC ?? 18.0;
    final tempInPreferred =
        _unit == 'f' ? initialTempC.asFahrenheit : initialTempC;

    _tempController =
        TextEditingController(text: tempInPreferred.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    _tempController.dispose();
    super.dispose();
  }

  // Compact input decoration
  InputDecoration _dec(String label, {String? suffix}) => InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        filled: true,
        suffixText: suffix,
      );

  void _onUnitChanged(String? newUnit) {
    if (newUnit == null || newUnit == _unit) return;

    final current = double.tryParse(_tempController.text);
    if (current == null) {
      setState(() => _unit = newUnit); // still switch to keep UI in sync
      return;
    }

    // Normalize current value to Celsius, then convert to target unit
    final asC = _unit == 'f' ? current.asCelsius : current;
    final converted = newUnit == 'f' ? asC.asFahrenheit : asC;

    setState(() {
      _unit = newUnit;
      _tempController.text = converted.toStringAsFixed(1);
    });
  }

  void _handleSave() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final tempValue = double.tryParse(_tempController.text) ?? 0.0;
    final daysValue = int.tryParse(_durationController.text) ?? 0;

    // Store in Celsius
    final tempC = _unit == 'f' ? tempValue.asCelsius : tempValue;

    final stage = FermentationStage(
      name: _nameController.text.trim(),
      durationDays: daysValue,
      targetTempC: tempC,
      startDate: widget.existing?.startDate,
    );

    widget.onSave(stage);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Stage' : 'Add Stage'),
      content: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: _dec('Stage Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _durationController,
                  decoration: _dec('Duration (days)'),
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      (int.tryParse(v ?? '') == null) ? 'Invalid number' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _tempController,
                  decoration: _dec('Target Temperature', suffix: '°${_unit.toUpperCase()}'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) =>
                      (double.tryParse(v ?? '') == null) ? 'Invalid number' : null,
                ),
                const SizedBox(height: 10),

                // Wrap the segmented control to avoid overflow on narrow screens
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'c', label: Text('°C')),
                      ButtonSegment(value: 'f', label: Text('°F')),
                    ],
                    selected: {_unit},
                    onSelectionChanged: (sel) => _onUnitChanged(sel.first),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _handleSave,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
