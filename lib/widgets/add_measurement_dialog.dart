import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/measurement.dart';
import '../models/settings_model.dart';
import '../utils/gravity_utils.dart';
import '../utils/fsu_utils.dart';
import '../utils/hydrometer_correction.dart';

class AddMeasurementDialog extends StatefulWidget {
  final Measurement? existingMeasurement;
  final Measurement? previousMeasurement;
  final DateTime? firstMeasurementDate;
  final void Function(Measurement)? onSave;

  const AddMeasurementDialog({
    super.key,
    this.existingMeasurement,
    this.previousMeasurement,
    this.firstMeasurementDate,
    this.onSave,
  });

  @override
  State<AddMeasurementDialog> createState() => _AddMeasurementDialogState();
}

class _AddMeasurementDialogState extends State<AddMeasurementDialog> {
  final _formKey = GlobalKey<FormState>();

  // --- Controllers ---
  final _gravityController = TextEditingController();
  final _tempController = TextEditingController();
  final _taController = TextEditingController();
  final _noteController = TextEditingController();

  // --- State Variables ---
  late DateTime _timestamp;
  late String _gravityUnit;
  late bool _isFahrenheitOverride;
  late List<String> _selectedInterventions;

  // --- Auto-calculated Preview Variables ---
  double? _fsuPreview;
  double? _sgCorrectedPreview;
  String _daysText = 'Day 1';

  final List<String> _allInterventions = [
    'Pressing', 'Yeast Inoculation', 'Temperature Control', 'First Racking',
    'Secondary Racking', 'Stabilization Racking', 'Back Sweetening', 'Carbonation', 'Bottling'
  ];

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsModel>(context, listen: false);
    final m = widget.existingMeasurement;

    _timestamp = m?.timestamp ?? DateTime.now();
    _gravityUnit = m?.gravityUnit ?? 'sg';
    _isFahrenheitOverride = settings.unit == 'F';
    _selectedInterventions = List<String>.from(m?.interventions ?? []);

    _noteController.text = m?.notes ?? '';
    _taController.text = m?.ta?.toString() ?? '';

    if (m != null) {
      if (m.temperature != null) {
        // FIXED: Replaced the non-existent method with correct conversion logic.
        double tempDisplayValue = m.temperature!; // Stored as Celsius
        if (settings.unit == 'F') {
          tempDisplayValue = (m.temperature! * 9 / 5) + 32;
        }
        _tempController.text = tempDisplayValue.toStringAsFixed(1);
      }
      final value = _gravityUnit == 'sg' ? m.gravity : m.brix;
      if (value != null) {
        _gravityController.text = _gravityUnit == 'sg'
            ? value.toStringAsFixed(3)
            : value.toStringAsFixed(1);
      }
    }

    _gravityController.addListener(_recalculateAllValues);
    _tempController.addListener(_recalculateAllValues);

    _recalculateAllValues();
  }

  @override
  void dispose() {
    _gravityController.dispose();
    _tempController.dispose();
    _taController.dispose();
    _noteController.dispose();
    super.dispose();
  }

void _recalculateAllValues() {
  final gravityVal = double.tryParse(_gravityController.text.trim());

  final rawTemp = _tempController.text.trim();
  final sanitizedTemp = rawTemp.replaceAll(RegExp(r'[^\d.]'), '');
  final tempVal = double.tryParse(sanitizedTemp);

  if (widget.firstMeasurementDate != null) {
    final days = _timestamp.difference(widget.firstMeasurementDate!).inDays;
    _daysText = 'Day ${days + 1}';
  }

  double? sgForCalcs;
  if (gravityVal != null) {
    sgForCalcs = _gravityUnit == 'sg' ? gravityVal : brixToSg(gravityVal);
  }

  if (sgForCalcs != null && tempVal != null) {
    final tempF = _isFahrenheitOverride ? tempVal : (tempVal * 9 / 5) + 32;
    _sgCorrectedPreview = getCorrectedSG(sgForCalcs, tempF);
  } else {
    _sgCorrectedPreview = null;
  }

  if (widget.previousMeasurement?.gravity != null && sgForCalcs != null) {
    final prev = widget.previousMeasurement!;
    final difference = _timestamp.difference(prev.timestamp);
    _fsuPreview = calculateFSU(prev.gravity!, sgForCalcs, difference);
  } else {
    _fsuPreview = null;
  }

  setState(() {});
}

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final gravityVal = double.tryParse(_gravityController.text);
    final tempVal = double.tryParse(_tempController.text);
    final taVal = double.tryParse(_taController.text);
    final note = _noteController.text.trim();

    final double? tempC = tempVal != null
        ? (_isFahrenheitOverride ? (tempVal - 32) * 5 / 9 : tempVal)
        : null;

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
    if (widget.previousMeasurement?.gravity != null && currentSg != null) {
      final difference = _timestamp.difference(widget.previousMeasurement!.timestamp);
      fsuspeed = calculateFSU(widget.previousMeasurement!.gravity!, currentSg, difference);
    }
    
    final measurement = Measurement(
      timestamp: _timestamp,
      gravityUnit: _gravityUnit,
      gravity: currentSg,
      brix: currentBrix,
      temperature: tempC,
      notes: note.isEmpty ? null : note,
      fsuspeed: fsuspeed,
      ta: taVal,
      sgCorrected: _sgCorrectedPreview,
      interventions: _selectedInterventions,
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
      final now = DateTime.now();
      setState(() {
        _timestamp = DateTime(picked.year, picked.month, picked.day, now.hour, now.minute);
        _recalculateAllValues();
      });
    }
  }

  void _showInterventionsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final tempSelected = List<String>.from(_selectedInterventions);
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Select Interventions'),
            content: SingleChildScrollView(
              child: ListBody(
                children: _allInterventions.map((item) {
                  return CheckboxListTile(
                    value: tempSelected.contains(item),
                    title: Text(item),
                    onChanged: (bool? value) {
                      setDialogState(() {
                        if (value == true) {
                          tempSelected.add(item);
                        } else {
                          tempSelected.remove(item);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() => _selectedInterventions = tempSelected);
                  Navigator.pop(context);
                },
                child: const Text('DONE'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existingMeasurement == null ? 'Add Measurement' : 'Edit Measurement'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Date: ${DateFormat.yMMMd().format(_timestamp)}')),
                  Text(_daysText, style: Theme.of(context).textTheme.bodySmall),
                  IconButton(icon: const Icon(Icons.calendar_today), onPressed: _pickDate, tooltip: 'Change Date'),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _gravityController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: _gravityUnit == 'sg' ? 'Specific Gravity' : 'Brix'),
                      validator: (v) => (v != null && v.isNotEmpty && double.tryParse(v) == null) ? 'Invalid number' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _gravityUnit,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _gravityUnit = val);
                        _recalculateAllValues();
                      }
                    },
                    items: const [
                      DropdownMenuItem(value: 'sg', child: Text('SG')),
                      DropdownMenuItem(value: 'brix', child: Text('°Bx')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tempController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Temperature'),
                      validator: (v) => (v != null && v.isNotEmpty && double.tryParse(v) == null) ? 'Invalid number' : null,
                    ),
                  ),
                   const SizedBox(width: 12),
                  ToggleButtons(
                    isSelected: [_isFahrenheitOverride, !_isFahrenheitOverride],
                    onPressed: (index) => setState(() {
                      _isFahrenheitOverride = index == 0;
                      _recalculateAllValues();
                    }),
                    borderRadius: BorderRadius.circular(8),
                    constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
                    children: const [Text('°F'), Text('°C')],
                  ),
                ],
              ),
               TextFormField(
                  controller: _taController,
                  decoration: const InputDecoration(labelText: 'TA (g/L)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) => (v != null && v.isNotEmpty && double.tryParse(v) == null) ? 'Invalid number' : null,
              ),
              const SizedBox(height: 16),
              
              if (_sgCorrectedPreview != null || _fsuPreview != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                         if (_sgCorrectedPreview != null)
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [const Text('Corrected SG'), Text(_sgCorrectedPreview!.toStringAsFixed(3), style: const TextStyle(fontWeight: FontWeight.bold))],
                          ),
                         if (_fsuPreview != null)
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                           children: [const Text('Est. FSU'), Text(_fsuPreview!.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold))],
                         ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              
              OutlinedButton.icon(
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Log Interventions'),
                onPressed: _showInterventionsDialog,
              ),
              if (_selectedInterventions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Wrap(
                    spacing: 6.0,
                    runSpacing: 6.0,
                    children: _selectedInterventions.map((i) => Chip(label: Text(i))).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('CANCEL')),
        ElevatedButton(onPressed: _save, child: const Text('SAVE')),
      ],
    );
  }
}