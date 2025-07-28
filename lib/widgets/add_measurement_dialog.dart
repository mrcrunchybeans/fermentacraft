import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/batch_model.dart';
import 'package:flutter_application_1/models/measurement_log.dart';

class AddMeasurementDialog extends StatefulWidget {
  final BatchModel batch;

  const AddMeasurementDialog({super.key, required this.batch});

  @override
  State<AddMeasurementDialog> createState() => _AddMeasurementDialogState();
}

class _AddMeasurementDialogState extends State<AddMeasurementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _sgController = TextEditingController();
  final _tempController = TextEditingController();
  final _pHController = TextEditingController();

  DateTime _timestamp = DateTime.now();

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _timestamp,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _timestamp = picked);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final log = MeasurementLog(
      timestamp: _timestamp,
      sg: double.parse(_sgController.text),
      tempC: _tempController.text.isEmpty ? null : double.tryParse(_tempController.text),
      pH: _pHController.text.isEmpty ? null : double.tryParse(_pHController.text),
    );

    widget.batch.measurementLogs.add(log);
    widget.batch.save();

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Measurement'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: Text('Date: ${_timestamp.toLocal().toString().split(' ')[0]}')),
                  TextButton(onPressed: _pickDate, child: const Text('Pick Date')),
                ],
              ),
              TextFormField(
                controller: _sgController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Specific Gravity'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Required';
                  final parsed = double.tryParse(value);
                  if (parsed == null || parsed <= 0 || parsed > 2.0) return 'Invalid SG';
                  return null;
                },
              ),
              TextFormField(
                controller: _tempController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Temperature (°C)'),
              ),
              TextFormField(
                controller: _pHController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'pH'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
