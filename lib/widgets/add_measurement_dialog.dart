// lib/widgets/add_measurement_dialog.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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

  // Focus
  final _gravityFocus = FocusNode();
  final _tempFocus = FocusNode();
  final _taFocus = FocusNode();
  final _noteFocus = FocusNode();

  // Focus sentry
  FocusNode? _activeTextNode;
  late VoidCallback _focusMgrListener;
  bool _guardFocus = true; // disabled on cancel/save/close
  bool get _isKeyboardOpen => MediaQuery.viewInsetsOf(context).bottom > 0;

  // Autofocus only once
  bool _didAutofocus = false;

  // State
  late DateTime _timestamp;
  late String _gravityUnit; // 'sg' or 'brix'
  late bool _isFahrenheitOverride; // true = F, false = C
  late List<String> _selectedInterventions;

  // Derived UI state
  bool _isValid = true; // no validate() during build
  double? _fsuPreview;
  double? _sgCorrectedPreview;
  String _daysText = 'Day 1';

  // Debounce to avoid thrashy rebuilds while typing
  Timer? _debounce;

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
        double t = m.temperature!; // stored as °C
        if (_isFahrenheitOverride) t = (t * 9 / 5) + 32;
        _tempController.text = t.toStringAsFixed(1);
      }
      final value = _gravityUnit == 'sg' ? m.gravity : m.brix;
      if (value != null) {
        _gravityController.text =
            _gravityUnit == 'sg' ? value.toStringAsFixed(3) : value.toStringAsFixed(1);
      }
    }

    // ---- Recalc + validity (debounced) ----
    void onAnyFieldChanged() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        _recalculateAllValues();
        _updateValidity();
      });
    }
    _gravityController.addListener(onAnyFieldChanged);
    _tempController.addListener(onAnyFieldChanged);
    _taController.addListener(onAnyFieldChanged);
    _noteController.addListener(_updateValidity);

    // ---- Track which text field should retain focus ----
    void bindFocusTracking(FocusNode n) {
      n.addListener(() {
        if (n.hasFocus) _activeTextNode = n;
      });
    }
    bindFocusTracking(_gravityFocus);
    bindFocusTracking(_tempFocus);
    bindFocusTracking(_taFocus);
    bindFocusTracking(_noteFocus);

    // ---- Focus Sentry: if external code unfocuses a field while keyboard is open, reclaim it ----
    _focusMgrListener = () {
      if (!_guardFocus) return;
      final node = _activeTextNode;
      if (!mounted || node == null) return;

      // If keyboard is open but no primary focus, pull focus back to the last active field.
      final hasPrimary = FocusManager.instance.primaryFocus != null;
      if (_isKeyboardOpen && !hasPrimary) {
        // Small delay lets Flutter settle focus transitions (avoids loops).
        Future.microtask(() {
          if (mounted && _isKeyboardOpen && _guardFocus) {
            node.requestFocus();
          }
        });
      }
    };
    FocusManager.instance.addListener(_focusMgrListener);

    // Initial compute
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recalculateAllValues();
      _updateValidity();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();

    _gravityController.dispose();
    _tempController.dispose();
    _taController.dispose();
    _noteController.dispose();

    _gravityFocus.dispose();
    _tempFocus.dispose();
    _taFocus.dispose();
    _noteFocus.dispose();

    FocusManager.instance.removeListener(_focusMgrListener);

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

  ButtonStyle get _segStyle {
    return const ButtonStyle(
      visualDensity: VisualDensity(horizontal: -2, vertical: -2),
      minimumSize: WidgetStatePropertyAll(Size(0, 36)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _segLabel(String text, {double width = 56}) {
    return SizedBox(
      width: width,
      height: 36,
      child: Center(
        child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
      ),
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

  // ---------- Validation & calcs ----------
  void _updateValidity() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ok = _formKey.currentState?.validate() ?? true;
      if (ok != _isValid) setState(() => _isValid = ok);
    });
  }

  void _recalculateAllValues() {
    // Compute, but only call setState if something changed (prevents noisy rebuilds).
    final gravityVal = double.tryParse(_gravityController.text.trim());
    final rawTemp = _tempController.text.trim();
    final sanitizedTemp = rawTemp.replaceAll(RegExp(r'[^\d.]'), '');
    final tempVal = double.tryParse(sanitizedTemp);

    String daysText = _daysText;
    if (widget.firstMeasurementDate != null) {
      final days = _timestamp.difference(widget.firstMeasurementDate!).inDays;
      daysText = 'Day ${days + 1}';
    }

    double? sgForCalcs;
    if (gravityVal != null) {
      sgForCalcs = _gravityUnit == 'sg' ? gravityVal : brixToSg(gravityVal);
    }

    double? sgCorr;
    if (sgForCalcs != null && tempVal != null) {
      final tempF = _isFahrenheitOverride ? tempVal : (tempVal * 9 / 5) + 32;
      sgCorr = getCorrectedSG(sgForCalcs, tempF);
    }

    final prevSg = widget.previousMeasurement?.sgCorrected ?? widget.previousMeasurement?.gravity;
    final currSg = sgCorr ?? sgForCalcs;

    double? fsu;
    if (prevSg != null && currSg != null && widget.previousMeasurement != null) {
      final difference = _timestamp.difference(widget.previousMeasurement!.timestamp);
      fsu = calculateFSU(prevSg, currSg, difference);
    }

    // Only setState on real change
    if (daysText != _daysText ||
        sgCorr != _sgCorrectedPreview ||
        fsu != _fsuPreview) {
      setState(() {
        _daysText = daysText;
        _sgCorrectedPreview = sgCorr;
        _fsuPreview = fsu;
      });
    }
  }

  // ---------- Actions ----------
  void _closeGuarded([Object? result]) {
    _guardFocus = false; // stop sentry so we don't fight the pop
    Navigator.of(context).pop(result);
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

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

    final prevSg = widget.previousMeasurement?.sgCorrected ?? widget.previousMeasurement?.gravity;
    final currSgForFsu = _sgCorrectedPreview ?? currentSg;

    double? fsuspeed;
    if (prevSg != null && currSgForFsu != null && widget.previousMeasurement != null) {
      final difference = _timestamp.difference(widget.previousMeasurement!.timestamp);
      fsuspeed = calculateFSU(prevSg, currSgForFsu, difference);
    }

    final measurement = Measurement(
      id: widget.existingMeasurement?.id,
      timestamp: _timestamp,
      gravityUnit: _gravityUnit,
      gravity: currentSg,
      brix: currentBrix,
      temperature: tempC, // stored as °C
      notes: note.isNotEmpty ? note : null,
      fsuspeed: fsuspeed,
      ta: taVal,
      sgCorrected: _sgCorrectedPreview,
      interventions: _selectedInterventions,
    );

    widget.onSave?.call(measurement);
    if (!mounted) return;

    unawaited(ReviewPrompter.instance.fireMeasurementLogged(context));
    _closeGuarded(measurement);
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

  // ---- Fields (stable keys + focus + traversal) ----
  TextFormField _gravityField(bool autofocus) {
    return TextFormField(
      key: const ValueKey('gravityField'),
      controller: _gravityController,
      focusNode: _gravityFocus,
      onTapOutside: (_) {
          if (MediaQuery.viewInsetsOf(context).bottom > 0) {
            _gravityFocus.requestFocus(); // 👈 keep keyboard up
          }
        },
      autofocus: !_didAutofocus && autofocus,
      onTap: () => _didAutofocus = true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) => _tempFocus.requestFocus(),
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
    );
  }

  TextFormField _tempField() {
    return TextFormField(
      key: const ValueKey('tempField'),
      controller: _tempController,
      focusNode: _tempFocus,
        onTapOutside: (_) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      _tempFocus.requestFocus(); // 👈 keep keyboard up
    }
  },
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) => _taFocus.requestFocus(),
      decoration: _dec(
        'Temperature',
        hint: _isFahrenheitOverride ? 'e.g. 68.0' : 'e.g. 20.0',
        suffix: _isFahrenheitOverride ? '°F' : '°C',
      ),
      validator: (v) =>
          (v != null && v.isNotEmpty && double.tryParse(v) == null) ? 'Enter a number' : null,
    );
  }

  TextFormField _taField() {
    return TextFormField(
      key: const ValueKey('taField'),
      controller: _taController,
      focusNode: _taFocus,
        onTapOutside: (_) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      _taFocus.requestFocus(); // 👈 keep keyboard up
    }
  },
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) => _noteFocus.requestFocus(),
      decoration: _dec('TA', hint: 'Titratable acidity', suffix: 'g/L'),
      validator: (v) =>
          (v != null && v.isNotEmpty && double.tryParse(v) == null) ? 'Enter a number' : null,
    );
  }

  TextFormField _notesField() {
    return TextFormField(
      key: const ValueKey('notesField'),
      controller: _noteController,
      focusNode: _noteFocus,
        onTapOutside: (_) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      _noteFocus.requestFocus(); // 👈 keep keyboard up
    }
  },
      maxLines: 3,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _save(),
      decoration: _dec(
        'Notes (optional)',
        hint: 'Comments, actions taken, aromas, etc.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 420;

    // A local FocusScope isolates us from parent unfocus gestures a bit more
    return FocusScope(
      debugLabel: 'AddMeasurementDialogScope',
      child: AlertDialog(
        title: Text(widget.existingMeasurement == null ? 'Add Measurement' : 'Edit Measurement'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        content: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
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
                    IconButton(icon: const Icon(Icons.calendar_today), onPressed: _pickDate),
                    IconButton(icon: const Icon(Icons.schedule), onPressed: _pickTime),
                  ],
                ),
                const SizedBox(height: 10),

                // Gravity + unit segment (stack on narrow)
                if (!isNarrow)
                  Row(
                    children: [
                      Expanded(flex: 3, child: _gravityField(widget.existingMeasurement == null)),
                      const SizedBox(width: 12),
                      Expanded(
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
                  )
                else ...[
                  _gravityField(widget.existingMeasurement == null),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
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
                ],

                const SizedBox(height: 10),

                // Temperature + unit segment (stack on narrow)
                if (!isNarrow)
                  Row(
                    children: [
                      Expanded(flex: 3, child: _tempField()),
                      const SizedBox(width: 12),
                      Expanded(
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
                  )
                else ...[
                  _tempField(),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
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
                ],

                const SizedBox(height: 10),

                _taField(),

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

                _notesField(),

                const SizedBox(height: 14),

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
          TextButton(
            onPressed: () => _closeGuarded(),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(onPressed: _isValid ? _save : null, child: const Text('SAVE')),
        ],
      ),
    );
  }
}
