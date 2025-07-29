import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/measurement.dart';
import '../models/settings_model.dart';
import '../utils/gravity_utils.dart';
import '../utils/temp_display.dart';
import '../utils/fsu_utils.dart';

class AddMeasurementDialog extends StatefulWidget {
  final Measurement? existingMeasurement;
  final Measurement? previousMeasurement;
  final void Function(Measurement)? onSave;

  const AddMeasurementDialog({
    super.key,
    this.existingMeasurement,
    this.previousMeasurement,
    this.onSave,
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
  String _gravityUnit = 'sg'; // 'sg' or 'brix'

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
      _tempController.text = m.temperature?.toStringAsFixed(1) ?? '';
      final value = _gravityUnit == 'sg' ? m.sg : m.brix;
      if (value != null) {
        _gravityController.text = _gravityUnit == 'sg'
            ? value.toStringAsFixed(3)
            : value.toStringAsFixed(1);
      }
      _calculatePreview();
    }
  }

  @override
  void dispose() {
    _gravityController.dispose();
    _tempController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _calculatePreview() {
    final gravityVal = double.tryParse(_gravityController.text);

    double? sg;
    if (gravityVal != null) {
      if (_gravityUnit == 'sg') {
        sg = gravityVal;
        _convertedGravity = sgToBrix(gravityVal);
      } else {
        sg = brixToSg(gravityVal);
        _convertedGravity = sgToBrix(sg);
      }
    } else {
      _convertedGravity = null;
    }

    // FSU preview logic
    if (widget.previousMeasurement?.sg != null && sg != null) {
    final prev = widget.previousMeasurement!;
    final difference = _timestamp.difference(prev.timestamp);
    _fsuPreview = calculateFSU(prev.sg!, sg, difference);
  } else {
    _fsuPreview = null;
  }

    setState(() {});
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final gravityVal = double.tryParse(_gravityController.text);
    final tempVal = double.tryParse(_tempController.text);
    final note = _noteController.text.trim();
    final settings = Provider.of<SettingsModel>(context, listen: false);

    if (gravityVal == null && tempVal == null && note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least one value.'),
        ),
      );
      return;
    }

    final double? tempC =
        tempVal != null ? TempDisplay.convertToCelsius(tempVal, settings.unit) : null;

    double? currentSg;
    double? currentBrix;

    if (gravityVal != null) {
      if (_gravityUnit == 'sg') {
        currentSg = gravityVal;
        currentBrix = sgToBrix(gravityVal);
      } else {
        currentBrix = gravityVal;
        currentSg = brixToSg(gravityVal);
      }
    }

    double? fsuspeed;
  if (widget.previousMeasurement?.sg != null && currentSg != null) {
    final difference = _timestamp.difference(widget.previousMeasurement!.timestamp);
    fsuspeed = calculateFSU(widget.previousMeasurement!.sg!, currentSg, difference);
  }

    final measurement = Measurement(
      timestamp: _timestamp,
      gravityUnit: _gravityUnit,
      sg: currentSg,
      brix: currentBrix,
      temperature: tempC,
      note: note.isEmpty ? null : note,
      fsuspeed: fsuspeed,
    );

    widget.onSave?.call(measurement);
    Navigator.of(context).pop(measurement);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _timestamp,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _timestamp = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _timestamp.hour,
          _timestamp.minute,
        );
        _calculatePreview();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final tempUnitLabel = settings.unit.toUpperCase();
    final showConverted =
        _gravityController.text.isNotEmpty && _convertedGravity != null;

    return AlertDialog(
      title: Text(
          widget.existingMeasurement == null ? 'Add Measurement' : 'Edit Measurement'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('Date: ${DateFormat.yMMMd().format(_timestamp)}')),
                  TextButton(onPressed: _pickDate, child: const Text('CHANGE')),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _gravityController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText:
                            _gravityUnit == 'sg' ? 'Specific Gravity' : 'Brix',
                      ),
                      onChanged: (_) => _calculatePreview(),
                      validator: (value) {
                        if (value == null || value.isEmpty) return null;
                        if (double.tryParse(value) == null) {
                          return 'Invalid number';
                        }
                        return null;
                      },
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
                      DropdownMenuItem(value: 'brix', child: Text('°Bx')),
                    ],
                  ),
                ],
              ),
              if (showConverted)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      _gravityUnit == 'sg'
                          ? '≈ ${_convertedGravity!.toStringAsFixed(1)} °Bx'
                          // Show the converted SG value when input is Brix
                          : '≈ ${brixToSg(double.tryParse(_gravityController.text) ?? 0).toStringAsFixed(3)} SG',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              TextFormField(
                controller: _tempController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: 'Temperature ($tempUnitLabel)'),
                validator: (value) {
                  if (value == null || value.isEmpty) return null;
                  if (double.tryParse(value) == null) {
                    return 'Invalid number';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Notes'),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
              ),
              if (_fsuPreview != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Text(
                      'Est. Fermentation Speed: ${_fsuPreview!.toStringAsFixed(1)} FSU',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: _save,
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}