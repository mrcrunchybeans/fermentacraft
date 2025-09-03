// lib/widgets/add_measurement_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../models/measurement.dart';
import '../models/settings_model.dart';
import '../utils/gravity_utils.dart';
import '../utils/fsu_utils.dart';
import '../utils/hydrometer_correction.dart';
import 'package:fermentacraft/services/review_prompter.dart';


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

  // Controllers
  final _gravityController = TextEditingController();
  final _tempController = TextEditingController();
  final _taController = TextEditingController();
  final _noteController = TextEditingController();

  // State
  late DateTime _timestamp;
  late String _gravityUnit; // 'sg' or 'brix'
  late bool _isFahrenheitOverride; // true = F, false = C
  late List<String> _selectedInterventions;

  // Auto-calculated previews
  double? _fsuPreview;
  double? _sgCorrectedPreview;
  String _daysText = 'Day 1';

  final List<String> _allInterventions = const [
    'Pressing',
    'Yeast Inoculation',
    'Temperature Control',
    'First Racking',
    'Secondary Racking',
    'Stabilization Racking',
    'Back Sweetening',
    'Carbonation',
    'Bottling'
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
        double tempDisplayValue = m.temperature!; // stored as °C
        if (_isFahrenheitOverride) tempDisplayValue = (tempDisplayValue * 9 / 5) + 32;
        _tempController.text = tempDisplayValue.toStringAsFixed(1);
      }
      final value = _gravityUnit == 'sg' ? m.gravity : m.brix;
      if (value != null) {
        _gravityController.text =
            _gravityUnit == 'sg' ? value.toStringAsFixed(3) : value.toStringAsFixed(1);
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

  // ---------- UI helpers ----------
  InputDecoration _dec(String label, {String? hint, String? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  // compact segmented style (height ~36)
  ButtonStyle get _segStyle {
    return const ButtonStyle(
      visualDensity: VisualDensity(horizontal: -2, vertical: -2),
      minimumSize: WidgetStatePropertyAll(Size(0, 36)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // Prevent label wrapping + force fixed height to avoid weird growth
Widget _segLabel(String text, {double width = 56}) {
  return SizedBox(
    width: width,
    height: 36,
    child: Center(
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis, // 👈
      ),
    ),
  );
}


  // Local Theme wrapper to suppress any error text spacing that can stretch controls
  Widget _noErrorTheme({required Widget child}) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        inputDecorationTheme: const InputDecorationTheme(
          errorStyle: TextStyle(height: 0, fontSize: 0),
        ),
      ),
      child: child,
    );
  }

  Widget _pill(String label, String value, {IconData? icon}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
        Text('$label: ', style: Theme.of(context).textTheme.labelMedium),
        Text(
          value,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }

  // ---------- Calc ----------
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

    // Use corrected SG when available for FSU preview
    final prevSg = widget.previousMeasurement?.sgCorrected ?? widget.previousMeasurement?.gravity;
    final currSg = _sgCorrectedPreview ?? sgForCalcs;

    if (prevSg != null && currSg != null && widget.previousMeasurement != null) {
      final difference = _timestamp.difference(widget.previousMeasurement!.timestamp);
      _fsuPreview = calculateFSU(prevSg, currSg, difference);
    } else {
      _fsuPreview = null;
    }

    setState(() {});
  }

  // ---------- Actions ----------
  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final gravityVal = double.tryParse(_gravityController.text);
    final tempVal = double.tryParse(_tempController.text);
    final taVal = double.tryParse(_taController.text);
    final note = _noteController.text.trim();

    final double? tempC =
        tempVal != null ? (_isFahrenheitOverride ? (tempVal - 32) * 5 / 9 : tempVal) : null;

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

    // Prefer corrected SG for FSU if we have it
    final prevSg = widget.previousMeasurement?.sgCorrected ?? widget.previousMeasurement?.gravity;
    final currSgForFsu = _sgCorrectedPreview ?? currentSg;

    double? fsuspeed;
    if (prevSg != null && currSgForFsu != null && widget.previousMeasurement != null) {
      final difference = _timestamp.difference(widget.previousMeasurement!.timestamp);
      fsuspeed = calculateFSU(prevSg, currSgForFsu, difference);
    }

    final measurement = Measurement(
      // preserve id when editing so replacement-in-list works
      id: widget.existingMeasurement?.id,
      timestamp: _timestamp,
      gravityUnit: _gravityUnit,
      gravity: currentSg,
      brix: currentBrix,
      temperature: tempC,
      notes: note.isNotEmpty ? note : null,
      fsuspeed: fsuspeed,
      ta: taVal,
      sgCorrected: _sgCorrectedPreview,
      interventions: _selectedInterventions,
    );

widget.onSave?.call(measurement);

// ✅ We may have awaited earlier in this method; guard context usage:
if (!mounted) return;

// Fire review trigger without awaiting (no need to hold the dialog)
unawaited(ReviewPrompter.instance.fireMeasurementLogged(context));

// Close safely
if (Navigator.canPop(context)) {
  Navigator.of(context).pop(measurement);
}


  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _timestamp,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
if (!mounted || picked == null) return;
setState(() {
  _timestamp = DateTime(
    picked.year, picked.month, picked.day, _timestamp.hour, _timestamp.minute,
  );
  _recalculateAllValues();
});
  }
  Future<void> _pickTime() async {
  final initial = TimeOfDay.fromDateTime(_timestamp);
  final picked = await showTimePicker(context: context, initialTime: initial);
  if (!mounted || picked == null) return;
  setState(() {
    _timestamp = DateTime(
      _timestamp.year, _timestamp.month, _timestamp.day, picked.hour, picked.minute,
    );
    _recalculateAllValues();
  });
}


  @override
  Widget build(BuildContext context) {
    final isValid = _formKey.currentState?.validate() ?? true;

    // “Narrow” = most phones in portrait. We’ll stack rows there.
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 420;

    return AlertDialog(
      title: Text(widget.existingMeasurement == null ? 'Add Measurement' : 'Edit Measurement'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        scrollable: true, // 👈 add this

      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: Date + Day chip
              Row(
                children: [
                Expanded(child: Text('Date: ${DateFormat.yMMMd().format(_timestamp)}')),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(_daysText, style: Theme.of(context).textTheme.labelMedium),
                  ),
    IconButton(
      icon: const Icon(Icons.calendar_today),
      tooltip: 'Change Date',
      onPressed: _pickDate,
    ),
    IconButton(
      icon: const Icon(Icons.schedule),
      tooltip: 'Change Time',
      onPressed: _pickTime,
    ),
  ],
),
              const SizedBox(height: 10),

              // Gravity + unit segment (stack on narrow)
              if (!isNarrow)
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _gravityController,
                        autofocus: widget.existingMeasurement == null,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration: _dec(
                          _gravityUnit == 'sg' ? 'Specific Gravity' : 'Brix',
                          hint: _gravityUnit == 'sg' ? 'e.g. 1.010' : 'e.g. 12.5',
                          suffix: _gravityUnit == 'sg' ? null : '°Bx',
                        ),
                        validator: (v) {
                          if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                            return 'Enter a number';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _noErrorTheme(
                        child: SegmentedButton<String>(
                          style: _segStyle,
                          segments: [
                            ButtonSegment(value: 'sg', label: _segLabel('SG')),
                            ButtonSegment(value: 'brix', label: _segLabel('°Bx')),
                          ],
                          selected: {_gravityUnit},
                          onSelectionChanged: (s) {
                            setState(() => _gravityUnit = s.first);
                            _recalculateAllValues();
                          },
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                TextFormField(
                  controller: _gravityController,
                  autofocus: widget.existingMeasurement == null,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: _dec(
                    _gravityUnit == 'sg' ? 'Specific Gravity' : 'Brix',
                    hint: _gravityUnit == 'sg' ? 'e.g. 1.010' : 'e.g. 12.5',
                    suffix: _gravityUnit == 'sg' ? null : '°Bx',
                  ),
                  validator: (v) {
                    if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                      return 'Enter a number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                _noErrorTheme(
                  child: SegmentedButton<String>(
                    style: _segStyle,
                    segments: [
                      ButtonSegment(value: 'sg', label: _segLabel('SG')),
                      ButtonSegment(value: 'brix', label: _segLabel('°Bx')),
                    ],
                    selected: {_gravityUnit},
                    onSelectionChanged: (s) {
                      setState(() => _gravityUnit = s.first);
                      _recalculateAllValues();
                    },
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Temperature + unit segment (stack on narrow)
              if (!isNarrow)
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _tempController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration: _dec(
                          'Temperature',
                          hint: _isFahrenheitOverride ? 'e.g. 68.0' : 'e.g. 20.0',
                          suffix: _isFahrenheitOverride ? '°F' : '°C',
                        ),
                        validator: (v) =>
                            (v != null && v.isNotEmpty && double.tryParse(v) == null)
                                ? 'Enter a number'
                                : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _noErrorTheme(
                        child: SegmentedButton<bool>(
                          style: _segStyle,
                          segments: [
                            ButtonSegment(value: true, label: _segLabel('°F')),
                            ButtonSegment(value: false, label: _segLabel('°C')),
                          ],
                          selected: {_isFahrenheitOverride},
                          onSelectionChanged: (s) {
                            setState(() => _isFahrenheitOverride = s.first);
                            _recalculateAllValues();
                          },
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                TextFormField(
                  controller: _tempController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: _dec(
                    'Temperature',
                    hint: _isFahrenheitOverride ? 'e.g. 68.0' : 'e.g. 20.0',
                    suffix: _isFahrenheitOverride ? '°F' : '°C',
                  ),
                  validator: (v) =>
                      (v != null && v.isNotEmpty && double.tryParse(v) == null)
                          ? 'Enter a number'
                          : null,
                ),
                const SizedBox(height: 8),
                _noErrorTheme(
                  child: SegmentedButton<bool>(
                    style: _segStyle,
                    segments: [
                      ButtonSegment(value: true, label: _segLabel('°F')),
                      ButtonSegment(value: false, label: _segLabel('°C')),
                    ],
                    selected: {_isFahrenheitOverride},
                    onSelectionChanged: (s) {
                      setState(() => _isFahrenheitOverride = s.first);
                      _recalculateAllValues();
                    },
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // TA
              TextFormField(
                controller: _taController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                decoration: _dec('TA', hint: 'Titratable acidity', suffix: 'g/L'),
                validator: (v) =>
                    (v != null && v.isNotEmpty && double.tryParse(v) == null)
                        ? 'Enter a number'
                        : null,
              ),

              const SizedBox(height: 12),

              // Live preview pills
              if (_sgCorrectedPreview != null || _fsuPreview != null)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (_sgCorrectedPreview != null)
                        _pill('Corrected SG', _sgCorrectedPreview!.toStringAsFixed(3),
                            icon: Icons.tune),
                      if (_fsuPreview != null) ...[
                        const SizedBox(width: 8),
                        _pill('Est. FSU', _fsuPreview!.toStringAsFixed(1),
                            icon: Icons.trending_down),
                      ],
                    ],
                  ),
                ),

              const SizedBox(height: 14),
              // Notes (optional)
              TextFormField(
                controller: _noteController,
                maxLines: 3,
                decoration: _dec(
                  'Notes (optional)',
                  hint: 'Comments, actions taken, aromas, etc.',
                ),
              ),

              const SizedBox(height: 14),


              // Interventions as FilterChips
              Text('Interventions', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _allInterventions.map((i) {
                  final selected = _selectedInterventions.contains(i);
                  return FilterChip(
                    label: Text(i),
                    selected: selected,
                    onSelected: (v) {
                      setState(() {
                        v ? _selectedInterventions.add(i) : _selectedInterventions.remove(i);
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('CANCEL')),
        ElevatedButton(onPressed: isValid ? _save : null, child: const Text('SAVE')),
      ],
    );
  }
}
