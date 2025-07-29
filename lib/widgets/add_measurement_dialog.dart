import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/measurement.dart';
import '../utils/fsu_utils.dart';
import '../utils/gravity_utils.dart';

class AddMeasurementDialog extends StatefulWidget {
  final Measurement? existingMeasurement;
  final void Function(Measurement) onSave;

  const AddMeasurementDialog({
    super.key,
    this.existingMeasurement,
    required this.onSave,
  });

  @override
  State<AddMeasurementDialog> createState() => _AddMeasurementDialogState();
}

class _AddMeasurementDialogState extends State<AddMeasurementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _gravityController = TextEditingController();
  final _tempController = TextEditingController();
  final _noteController = TextEditingController();

  DateTime _timestamp = DateTime.now();
  String _gravityUnit = 'sg'; // or 'brix'

  double? _fsuPreview;
  double? _convertedGravity;

  @override
  void initState() {
    super.initState();
    if (widget.existingMeasurement != null) {
      final m = widget.existingMeasurement!;
      _timestamp = m.timestamp;
      _gravityUnit = m.gravityUnit;
      _noteController.text = m.note ?? '';
      _tempController.text = m.temperature?.toString() ?? '';

      final inputValue = _gravityUnit == 'sg' ? m.sg : m.brix;
      if (inputValue != null) {
        _gravityController.text = inputValue.toStringAsFixed(3);
      }

      _calculatePreview();
    }
  }

  void _calculatePreview() {
    final gravityVal = double.tryParse(_gravityController.text);
    final tempVal = double.tryParse(_tempController.text);

    double? sg;
    if (_gravityUnit == 'sg') {
      sg = gravityVal;
      _convertedGravity = sgToBrix(gravityVal ?? 0);
    } else {
      sg = brixToSg(gravityVal ?? 0);
      _convertedGravity = sg;
    }

    if (tempVal != null && sg != null) {
      _fsuPreview = calculateFSU(tempVal, sg);
    } else {
      _fsuPreview = null;
    }

    setState(() {});
  }

  Future<void> _pickDate() async {
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

    final temp = double.tryParse(_tempController.text);
    final gravityInput = double.tryParse(_gravityController.text);
    final note = _noteController.text.trim().isEmpty ? null : _noteController.text.trim();

    final measurement = Measurement(
      timestamp: _timestamp,
      temperature: temp,
      gravityUnit: _gravityUnit,
      specificGravity: _gravityUnit == 'sg' ? gravityInput : null,
      brixValue: _gravityUnit == 'brix' ? gravityInput : null,
      note: note,
    );

    widget.onSave(measurement);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy-MM-dd').format(_timestamp);
    final showConverted = _gravityController.text.isNotEmpty;

    return AlertDialog(
      title: Text(widget.existingMeasurement == null ? 'Add Measurement' : 'Edit Measurement'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: Text('Date: $dateStr')),
                  TextButton(onPressed: _pickDate, child: const Text('Pick Date')),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _gravityController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: _gravityUnit == 'sg' ? 'Specific Gravity' : 'Brix'),
                      validator: (value) {
                        final v = double.tryParse(value ?? '');
                        if (v == null || v <= 0) return 'Invalid';
                        return null;
                      },
                      onChanged: (_) => _calculatePreview(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _gravityUnit,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _gravityUnit = val);
                        _calculatePreview();
                      }
                    },
                    items: const [
                      DropdownMenuItem(value: 'sg', child: Text('SG')),
                      DropdownMenuItem(value: 'brix', child: Text('Brix')),
                    ],
                  ),
                ],
              ),
              if (showConverted)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _gravityUnit == 'sg'
                        ? '≈ ${_convertedGravity?.toStringAsFixed(1)}°Bx'
                        : '≈ SG ${_convertedGravity?.toStringAsFixed(3)}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              TextFormField(
                controller: _tempController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Temperature (°C)'),
                onChanged: (_) => _calculatePreview(),
              ),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 2,
              ),
              if (_fsuPreview != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('FSU: ${_fsuPreview!.toStringAsFixed(1)}'),
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
