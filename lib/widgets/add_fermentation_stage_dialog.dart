import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/temp_display.dart'; // Using YOUR extension methods now
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

  late String _unit; // Internal state will be 'c' or 'f'

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsModel>();
    // Normalize the unit from settings ('°C'/'°F') to 'c'/'f' for your extension methods
    _unit = settings.unit.toLowerCase().contains('c') ? 'c' : 'f';

    _nameController = TextEditingController(text: widget.existing?.name ?? 'Primary');
    _durationController = TextEditingController(text: widget.existing?.durationDays.toString() ?? '14');

    final initialTempInC = widget.existing?.targetTempC ?? 18.0;

    // FIX: Using your extension methods to get the initial temperature
    final tempInPreferredUnit = (_unit == 'f') ? initialTempInC.asFahrenheit : initialTempInC;
    _tempController = TextEditingController(text: tempInPreferredUnit.toStringAsFixed(1));
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    _tempController.dispose();
    super.dispose();
  }

  void _onUnitChanged(String? newUnit) {
    if (newUnit == null || newUnit == _unit) return;

    final currentTempValue = double.tryParse(_tempController.text);
    if (currentTempValue == null) return;

    // First, convert the current value back to the standard unit (Celsius)
    final tempInCelsius = (_unit == 'f') ? currentTempValue.asCelsius : currentTempValue;

    // Now, convert from Celsius to the new target unit
    final tempInNewUnit = (newUnit == 'f') ? tempInCelsius.asFahrenheit : tempInCelsius;

    setState(() {
      _unit = newUnit;
      _tempController.text = tempInNewUnit.toStringAsFixed(1);
    });
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final tempValue = double.tryParse(_tempController.text) ?? 0.0;
    final daysValue = int.tryParse(_durationController.text) ?? 0;

    // FIX: Using your 'asCelsius' extension to convert back for storage
    final tempInCelsius = (_unit == 'f') ? tempValue.asCelsius : tempValue;

    final stage = FermentationStage(
      name: _nameController.text.trim(),
      durationDays: daysValue,
      targetTempC: tempInCelsius,
      startDate: widget.existing?.startDate,
    );
    
    widget.onSave(stage);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Stage' : 'Edit Stage'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Stage Name'),
                validator: (value) => (value == null || value.trim().isEmpty) ? 'Please enter a name' : null,
              ),
              TextFormField(
                controller: _durationController,
                decoration: const InputDecoration(labelText: 'Duration (days)'),
                keyboardType: TextInputType.number,
                validator: (value) => (int.tryParse(value ?? '') == null) ? 'Invalid number' : null,
              ),
              TextFormField(
                controller: _tempController,
                decoration: InputDecoration(
                  labelText: 'Target Temperature',
                  // Display the unit next to the field, not inside it
                  suffixText: '°${_unit.toUpperCase()}',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => (double.tryParse(value ?? '') == null) ? 'Invalid number' : null,
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'c', label: Text('°C')),
                  ButtonSegment(value: 'f', label: Text('°F')),
                ],
                selected: {_unit}, // The selected value is now 'c' or 'f'
                onSelectionChanged: (newSelection) => _onUnitChanged(newSelection.first),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: _handleSave,
          child: const Text("Save"),
        ),
      ],
    );
  }
}