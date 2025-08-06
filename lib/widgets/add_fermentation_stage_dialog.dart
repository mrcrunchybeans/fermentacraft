import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/temp_display.dart';
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
  final _formKey = GlobalKey<FormState>(); // Use a FormKey for validation
  final _nameController = TextEditingController();
  final _tempController = TextEditingController();
  final _daysController = TextEditingController();

  // Use a simple, non-display character for the internal state of the unit
  late String _unit;

  @override
  void initState() {
    super.initState();

    // Get the initial unit from app settings. No need to listen for changes here.
    final settings = Provider.of<SettingsModel>(context, listen: false);
    _unit = settings.unit; // Assumes unit is 'c' or 'f'

    // Populate fields if we are editing an existing stage
    if (widget.existing != null) {
      final stage = widget.existing!;
      _nameController.text = stage.name;
      _daysController.text = stage.durationDays.toString();

      // Use our robust `toDisplay` extension to set the temperature text
      if (stage.targetTempC != null) {
        _tempController.text = stage.targetTempC!.toDisplay(targetUnit: _unit);
      }
    } else {
      // Provide a sensible default value for a new stage
      const defaultTempC = 20.0;
      _tempController.text = defaultTempC.toDisplay(targetUnit: _unit);
    }
  }

  // UX Improvement: When the unit changes, convert the existing value.
  void _onUnitChanged(String? newUnit) {
    if (newUnit == null || newUnit == _unit) return;

    // Safely get the current numeric value from the text field
    final currentTempValue = double.tryParse(_tempController.text);
    if (currentTempValue == null) return; // Do nothing if the text is not a valid number

    double tempInCelsius;
    // First, convert the current value to our standard unit (Celsius)
    if (_unit == 'f') {
      tempInCelsius = currentTempValue.asCelsius;
    } else {
      tempInCelsius = currentTempValue;
    }

    // Now, update the state and display the value in the new unit
    setState(() {
      _unit = newUnit;
      _tempController.text = tempInCelsius.toDisplay(targetUnit: _unit);
    });
  }

  // A safe, robust save method
  void _saveStage() {
    // Use the FormKey to validate all fields at once
    if (!_formKey.currentState!.validate()) {
      return; // If validation fails, do not proceed
    }

    // Safely parse the temperature and days
    final tempValue = double.tryParse(_tempController.text) ?? 0.0;
    final daysValue = int.tryParse(_daysController.text) ?? 0;

    // Convert the final temperature to Celsius for consistent storage
    final double tempInCelsius;
    if (_unit == 'f') {
      tempInCelsius = tempValue.asCelsius;
    } else {
      tempInCelsius = tempValue;
    }

    // Create the stage object with the final, standardized data
    final stage = FermentationStage(
      name: _nameController.text.trim(),
      durationDays: daysValue,
      targetTempC: tempInCelsius,
      startDate: widget.existing?.startDate, // Preserve start date if editing
    );

    widget.onSave(stage);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // Clean up the controllers when the widget is disposed
    _nameController.dispose();
    _tempController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Stage' : 'Edit Stage'),
      content: SingleChildScrollView(
        child: Form( // Wrap fields in a Form widget
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Stage Name'),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Please enter a name'
                    : null,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tempController,
                      decoration: const InputDecoration(labelText: 'Temperature'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) => (double.tryParse(value ?? '') == null)
                          ? 'Invalid number'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Use our internal '_unit' for the dropdown value
                  DropdownButton<String>(
                    value: _unit,
                    onChanged: _onUnitChanged, // Call our new handler
                    items: ['c', 'f']
                        .map((u) => DropdownMenuItem(
                            value: u, child: Text('°${u.toUpperCase()}')))
                        .toList(),
                  ),
                ],
              ),
              TextFormField(
                controller: _daysController,
                decoration: const InputDecoration(labelText: 'Days'),
                keyboardType: TextInputType.number,
                validator: (value) => (int.tryParse(value ?? '') == null)
                    ? 'Invalid number'
                    : null,
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
        FilledButton( // Use a more prominent button for the primary action
          onPressed: _saveStage,
          child: const Text("Save"),
        ),
      ],
    );
  }
}