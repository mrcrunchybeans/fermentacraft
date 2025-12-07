import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // input formatters

import 'package:fermentacraft/utils/sugar_gravity_data.dart';
import '../../widgets/stabilization_guidance_dialog.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/widgets/soft_lock_overlay.dart';
import 'package:fermentacraft/utils/snacks.dart';

class GravityAdjustTool extends StatefulWidget {
  const GravityAdjustTool({super.key});

  @override
  State<GravityAdjustTool> createState() => _GravityAdjustToolState();
}

class _GravityAdjustToolState extends State<GravityAdjustTool> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gravity Adjustment Tool'),
          bottom: TabBar(
            indicatorColor: cs.primary,
            labelColor: cs.onSurface,
            unselectedLabelColor: cs.onSurface.withOpacity(0.65),
            tabs: const [
              Tab(text: 'Pre-Fermentation'),
              Tab(text: 'Backsweeten'),
            ],
          ),
        ),
        body: SoftLockOverlay(
          allow: FeatureGate.instance.allowGravityAdjust,
          message: 'Gravity Adjustment is a Premium feature',
          child: const TabBarView(
            children: [
              PreFermentationAdjustTab(),
              BacksweetenAdjustTab(),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------- Pre-Fermentation Tab -----------------------

class PreFermentationAdjustTab extends StatefulWidget {
  const PreFermentationAdjustTab({super.key});

  @override
  State<PreFermentationAdjustTab> createState() =>
      _PreFermentationAdjustTabState();
}

class _PreFermentationAdjustTabState extends State<PreFermentationAdjustTab> {
  // controllers
  final _volumeController = TextEditingController();
  final _currentSGController = TextEditingController();
  final _targetSGController = TextEditingController();
  final _abvController = TextEditingController();
  final _fgController = TextEditingController(text: '1.000');

  // focus (nice UX for mobile/web/desktop)
  final _fVolume = FocusNode();
  final _fCurrent = FocusNode();
  final _fTarget = FocusNode();
  final _fAbv = FocusNode();
  final _fFg = FocusNode();

  // state
  Timer? _abvDebounce;
  Timer? _sgDebounce;
  bool _userOverrodeAbv = false;
  bool _useGallons = true;
  String _selectedSugar = 'Table Sugar (sucrose)';
  String _result = '';
  String _formulaHelp = '';

  // formatters
  final _fmt3 = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
  ];
  final _fmt2 = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
  ];

  // helpers
  bool _isValidSg(double sg) => sg >= 0.990 && sg <= 1.200;
  bool _isPositive(double? v) => v != null && v > 0;
  String _normalize(String s) => s.trim().replaceAll(',', '.');

  double? _parseD(String s) => double.tryParse(_normalize(s));

  @override
  void initState() {
    super.initState();
    _abvController.addListener(() {
      final val = _parseD(_abvController.text);
      final fg = _parseD(_fgController.text) ?? 1.000;
      if (val == null) return;

      // clamp ABV to 0–25 for sanity
      final clamped = val.clamp(0, 25).toDouble();
      if (clamped != val) {
        final t = clamped.toStringAsFixed(2);
        _abvController.value = _abvController.value.copyWith(
          text: t,
          selection: TextSelection.collapsed(offset: t.length),
        );
      }

      if (clamped > 0) {
        _userOverrodeAbv = true;
        _sgDebounce?.cancel();
        _sgDebounce = Timer(const Duration(milliseconds: 500), () {
          final requiredOG = (clamped / 131.25) + fg;
          final ogText = requiredOG.toStringAsFixed(3);
          _targetSGController.text = ogText;
          _calculate();
        });
      }
    });
  }

  @override
  void dispose() {
    _abvDebounce?.cancel();
    _sgDebounce?.cancel();
    _volumeController.dispose();
    _currentSGController.dispose();
    _targetSGController.dispose();
    _abvController.dispose();
    _fgController.dispose();

    _fVolume.dispose();
    _fCurrent.dispose();
    _fTarget.dispose();
    _fAbv.dispose();
    _fFg.dispose();
    super.dispose();
  }

  void _calculate() {
    final volumeInput = _parseD(_volumeController.text);
    final currentSG = _parseD(_currentSGController.text);
    final targetSG = _parseD(_targetSGController.text);

    // guards
    if (!_isPositive(volumeInput)) {
      setState(() {
        _result = 'Please enter a volume greater than zero.';
        _formulaHelp = '';
      });
      return;
    }
    if (currentSG == null ||
        targetSG == null ||
        !_isValidSg(currentSG) ||
        !_isValidSg(targetSG)) {
      setState(() {
        _result = 'Enter SGs between 0.990 and 1.200.';
        _formulaHelp = '';
      });
      return;
    }

    final volumeGallons = _useGallons ? volumeInput! : volumeInput! / 3.78541;
    final deltaSG = targetSG - currentSG;

    if (deltaSG < 0) {
      setState(() {
        _result =
            'Target SG is below current SG. Reduce volume or set a higher target.';
        _formulaHelp = '';
      });
      return;
    }
    if (deltaSG == 0) {
      setState(() {
        _result = 'No adjustment needed. Target and current SG are equal.';
        _formulaHelp = '';
      });
      return;
    }

    final deltaPoints = deltaSG * 1000;
    final ppg = SugarGravityData.ppgMap[_selectedSugar];
    if (ppg == null) {
      setState(() {
        _result = 'Unknown sugar type selected.';
        _formulaHelp = '';
      });
      return;
    }

    final poundsNeeded = (deltaPoints * volumeGallons) / ppg;
    final gramsNeeded = poundsNeeded * 453.592;

    setState(() {
      _result =
          'Add ~${gramsNeeded.toStringAsFixed(1)} g of $_selectedSugar to reach ${targetSG.toStringAsFixed(3)} SG.';
      _formulaHelp =
          'Δ points = (${targetSG.toStringAsFixed(3)} - ${currentSG.toStringAsFixed(3)}) × 1000 = ${deltaPoints.toStringAsFixed(1)} pts\n'
          'Pounds = (Δ pts × Volume) / PPG\n'
          'Grams = Pounds × 453.592';
    });

    // auto ABV if not overridden
    if (!_userOverrodeAbv) {
      final og = _parseD(_targetSGController.text);
      final fg = _parseD(_fgController.text);
      if (og != null && fg != null && og > fg) {
        final abv = (og - fg) * 131.25;
        _abvController.text = abv.toStringAsFixed(2);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    InputDecorationThemeData idt = theme.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      border: const OutlineInputBorder(),
    );

    return Theme(
      data: theme.copyWith(inputDecorationTheme: idt),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pre-Fermentation Adjustment',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Volume + Units (bounded widths fix)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    focusNode: _fVolume,
                    controller: _volumeController,
                    textInputAction: TextInputAction.next,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _fmt3,
                    decoration: InputDecoration(
                      labelText: 'Volume (${_useGallons ? "gal" : "L"})',
                    ),
                    onSubmitted: (_) => _fCurrent.requestFocus(),
                    onChanged: (_) => _calculate(),
                    enableSuggestions: false,
                    autocorrect: false,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<bool>(
                    value: _useGallons,
                    decoration: const InputDecoration(labelText: 'Units'),
                    items: const [
                      DropdownMenuItem(value: true, child: Text('Gallons')),
                      DropdownMenuItem(value: false, child: Text('Liters')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _useGallons = value;
                          _calculate();
                        });
                      }
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            TextField(
              focusNode: _fCurrent,
              controller: _currentSGController,
              textInputAction: TextInputAction.next,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _fmt3,
              decoration: const InputDecoration(labelText: 'Current SG'),
              onSubmitted: (_) => _fTarget.requestFocus(),
              onChanged: (_) => _calculate(),
              enableSuggestions: false,
              autocorrect: false,
            ),

            const SizedBox(height: 12),
            TextField(
              focusNode: _fTarget,
              controller: _targetSGController,
              textInputAction: TextInputAction.next,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _fmt3,
              decoration: const InputDecoration(labelText: 'Target SG'),
              onSubmitted: (_) => _fAbv.requestFocus(),
              onChanged: (_) {
                _userOverrodeAbv = false; // re-enable ABV auto after SG edits
                _calculate();
              },
              enableSuggestions: false,
              autocorrect: false,
            ),

            const SizedBox(height: 12),
            TextField(
              focusNode: _fAbv,
              controller: _abvController,
              textInputAction: TextInputAction.next,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _fmt2,
              decoration: const InputDecoration(labelText: 'Desired ABV (%)'),
              onSubmitted: (_) => _fFg.requestFocus(),
              onChanged: (_) => _calculate(),
              enableSuggestions: false,
              autocorrect: false,
            ),

            const SizedBox(height: 12),
            TextField(
              focusNode: _fFg,
              controller: _fgController,
              textInputAction: TextInputAction.done,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _fmt3,
              decoration: const InputDecoration(labelText: 'Predicted FG'),
              onChanged: (_) => _calculate(),
              enableSuggestions: false,
              autocorrect: false,
            ),

            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedSugar,
              decoration: const InputDecoration(labelText: 'Sugar type'),
              isExpanded: true,
              items: SugarGravityData.ppgMap.keys
                  .map((type) =>
                      DropdownMenuItem(value: type, child: Text(type)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedSugar = value);
                  _calculate();
                }
              },
            ),

            const SizedBox(height: 16),
            if (_result.isNotEmpty) ...[
              _ThemedResult(_result),
              const SizedBox(height: 12),
            ],

            if (_formulaHelp.isNotEmpty)
              const SizedBox(height: 4),
            if (_formulaHelp.isNotEmpty)
              _ThemedCallout(
                text: _formulaHelp,
                icon: Icons.calculate_outlined,
              ),
          ],
        ),
      ),
    );
  }
}

// ----------------------- Backsweeten Tab -----------------------

class BacksweetenAdjustTab extends StatefulWidget {
  const BacksweetenAdjustTab({super.key});

  @override
  State<BacksweetenAdjustTab> createState() => _BacksweetenAdjustTabState();
}

class _BacksweetenAdjustTabState extends State<BacksweetenAdjustTab> {
  final _volumeController = TextEditingController();
  final _currentSGController = TextEditingController();
  final _targetSGController = TextEditingController();
  final _phController = TextEditingController();

  final _fVolume = FocusNode();
  final _fCurrent = FocusNode();
  final _fTarget = FocusNode();
  final _fPh = FocusNode();

  String _result = '';
  String _selectedSugar = 'Table Sugar (sucrose)';
  bool _useGallons = true;

  // formatters
  final _fmt3 = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
  ];
  final _fmt2 = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
  ];

  bool _isValidSg(double sg) => sg >= 0.990 && sg <= 1.200;
  bool _isPositive(double? v) => v != null && v > 0;
  String _normalize(String s) => s.trim().replaceAll(',', '.');
  double? _parseD(String s) => double.tryParse(_normalize(s));

  @override
  void dispose() {
    _volumeController.dispose();
    _currentSGController.dispose();
    _targetSGController.dispose();
    _phController.dispose();
    _fVolume.dispose();
    _fCurrent.dispose();
    _fTarget.dispose();
    _fPh.dispose();
    super.dispose();
  }

  void _calculate() {
    final volumeInput = _parseD(_volumeController.text);
    final currentSG = _parseD(_currentSGController.text);
    final targetSG = _parseD(_targetSGController.text);

    if (!_isPositive(volumeInput)) {
      setState(() => _result = 'Please enter a volume greater than zero.');
      return;
    }
    if (currentSG == null ||
        targetSG == null ||
        !_isValidSg(currentSG) ||
        !_isValidSg(targetSG)) {
      setState(() => _result = 'Enter SGs between 0.990 and 1.200.');
      return;
    }

    final volumeGallons = _useGallons ? volumeInput! : volumeInput! / 3.78541;
    final deltaSG = targetSG - currentSG;
    if (deltaSG <= 0) {
      setState(() => _result = 'No sugar needed.');
      return;
    }

    final deltaPoints = deltaSG * 1000;
    final ppg = SugarGravityData.ppgMap[_selectedSugar];
    if (ppg == null) {
      setState(() => _result = 'Unknown sugar type selected.');
      return;
    }

    final poundsNeeded = (deltaPoints * volumeGallons) / ppg;
    final gramsNeeded = poundsNeeded * 453.592;
    setState(() => _result =
        'Add ~${gramsNeeded.toStringAsFixed(1)} g of $_selectedSugar to reach ${targetSG.toStringAsFixed(3)} SG.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    InputDecorationThemeData idt = theme.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      border: const OutlineInputBorder(),
    );

    return Theme(
      data: theme.copyWith(inputDecorationTheme: idt),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Backsweetening Adjustment',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    focusNode: _fVolume,
                    controller: _volumeController,
                    textInputAction: TextInputAction.next,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _fmt3,
                    decoration: InputDecoration(
                      labelText: 'Volume (${_useGallons ? "gal" : "L"})',
                    ),
                    onSubmitted: (_) => _fCurrent.requestFocus(),
                    onChanged: (_) => _calculate(),
                    enableSuggestions: false,
                    autocorrect: false,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<bool>(
                    value: _useGallons,
                    decoration: const InputDecoration(labelText: 'Units'),
                    items: const [
                      DropdownMenuItem(value: true, child: Text('Gallons')),
                      DropdownMenuItem(value: false, child: Text('Liters')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _useGallons = value;
                          _calculate();
                        });
                      }
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            TextField(
              focusNode: _fCurrent,
              controller: _currentSGController,
              textInputAction: TextInputAction.next,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _fmt3,
              decoration: const InputDecoration(labelText: 'Current SG'),
              onSubmitted: (_) => _fTarget.requestFocus(),
              onChanged: (_) => _calculate(),
              enableSuggestions: false,
              autocorrect: false,
            ),

            const SizedBox(height: 12),
            TextField(
              focusNode: _fTarget,
              controller: _targetSGController,
              textInputAction: TextInputAction.next,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _fmt3,
              decoration: const InputDecoration(labelText: 'Target SG'),
              onSubmitted: (_) => _fPh.requestFocus(),
              onChanged: (_) => _calculate(),
              enableSuggestions: false,
              autocorrect: false,
            ),

            const SizedBox(height: 12),
            TextField(
              focusNode: _fPh,
              controller: _phController,
              textInputAction: TextInputAction.done,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _fmt2,
              decoration:
                  const InputDecoration(labelText: 'Measured pH (optional)'),
              onChanged: (_) => _calculate(),
              enableSuggestions: false,
              autocorrect: false,
            ),

            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedSugar,
              decoration: const InputDecoration(labelText: 'Sugar type'),
              isExpanded: true,
              items: SugarGravityData.ppgMap.keys
                  .map((type) =>
                      DropdownMenuItem(value: type, child: Text(type)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedSugar = value);
                  _calculate();
                }
              },
            ),

            const SizedBox(height: 16),
            if (_result.isNotEmpty) _ThemedResult(_result),

            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.shield),
              label: const Text('Stabilization Dose Guide'),
              onPressed: () {
                final volumeInput = _parseD(_volumeController.text);
                if (!_isPositive(volumeInput)) {
                  snacks.show(const SnackBar(
                      content: Text('Please enter a valid volume first.')));
                  return;
                }
                final volume = volumeInput!;
                final ph = _parseD(_phController.text);

                showDialog(
                  context: context,
                  builder: (_) => StabilizationGuidanceDialog(
                    volume: volume,
                    isGallons: _useGallons,
                    ph: ph,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------- Shared UI -----------------------

class _ThemedCallout extends StatelessWidget {
  final String text;
  final IconData icon;
  const _ThemedCallout({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: cs.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemedResult extends StatelessWidget {
  final String text;
  const _ThemedResult(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Semantics(
        label: 'Gravity adjustment result',
        child: SelectableText(
          text,
          style: TextStyle(
            color: cs.onTertiaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
