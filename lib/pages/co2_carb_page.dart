// lib/pages/co2_carb_page.dart
import 'package:flutter/material.dart';

class CO2CarbPage extends StatefulWidget {
  const CO2CarbPage({super.key});

  @override
  State<CO2CarbPage> createState() => _CO2CarbPageState();
}

/* ────────────────────────────────────────────────────────────────────────────
   MATH HELPERS (self-contained)
   - Residual CO2 (vols) via (°F → vols) lookup + linear interpolation
   - Priming sugar factors (gal/L variants)
   - Force carb PSI equation (empirical)
   ──────────────────────────────────────────────────────────────────────────── */

class _CO2CarbMath {
  // °F → residual CO2 volumes (typical fermentation completion temps)
  static const List<double> _tempsF = [32, 40, 50, 60, 68, 70, 75];
  static const List<double> _vols   = [1.68, 1.45, 1.19, 0.93, 0.85, 0.85, 0.82];

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double residualVolsAtF(double tempF) {
    if (tempF <= _tempsF.first) return _vols.first;
    if (tempF >= _tempsF.last)  return _vols.last;
    for (int i = 0; i < _tempsF.length - 1; i++) {
      final t0 = _tempsF[i], t1 = _tempsF[i + 1];
      if (tempF >= t0 && tempF <= t1) {
        final v0 = _vols[i], v1 = _vols[i + 1];
        final f = (tempF - t0) / (t1 - t0);
        return _lerp(v0, v1, f);
      }
    }
    return _vols.last;
  }

  static double cToF(double c) => (c * 9.0 / 5.0) + 32.0;

  // Priming sugar factors (grams per unit-volume per “vol” CO2)
  // Choose galFactor if using gallons; lFactor if using liters.
  static const double cornSugarGalFactor  = 15.0; // g / gal / vol
  static const double tableSugarGalFactor = 13.7;
  static const double dmeGalFactor        = 18.9;

  static const double cornSugarLFactor  = 3.95; // g / L / vol
  static const double tableSugarLFactor = 3.61;
  static const double dmeLFactor        = 5.00;

  static double primingSugarGrams({
    required double targetVolumes,
    required double fermTemp,
    required bool tempIsF,
    required double batchVolume,
    required bool volumeIsGal,
    required double sugarFactor, // pick a *GalFactor or *LFactor matching volume unit
  }) {
    final tempF = tempIsF ? fermTemp : cToF(fermTemp);
    final residual = residualVolsAtF(tempF);
    final deltaV = (targetVolumes - residual).clamp(0.0, 10.0);
    final grams = deltaV * batchVolume * sugarFactor;
    return grams.isFinite ? grams : 0.0;
  }

  // Force carbonation: PSI for target vols at temp °F
  static double psiForVolumesF({
    required double targetVolumes,
    required double tempF,
  }) {
    final T = tempF;
    final V = targetVolumes;
    final psi = -16.6999
        - 0.0101059 * T
        + 0.00116512 * T * T
        + 0.173354 * T * V
        + 4.24267 * V
        - 0.0684226 * V * V;
    return psi.isFinite ? psi : 0.0;
  }
}


/* ────────────────────────────────────────────────────────────────────────────
   UI
   - Mirrors your existing Tools style:
     * AppBar w/ help icon → dialog
     * 16px padding
     * concise input rows
     * bold result box with secondary color accent
     * light safety note footer
   ──────────────────────────────────────────────────────────────────────────── */

class _CO2CarbPageState extends State<CO2CarbPage> {
  // Shared style state
  bool _useF = true;          // page-local temperature unit (F/C)
  bool _useGal = true;        // page-local volume unit (gal/L)

  // Priming sugar tab state
  final _batchCtrl = TextEditingController(text: '5.0');
  final _tempCtrl  = TextEditingController(text: '68');
  final _targetVolsCtrl = TextEditingController(text: '2.8');

  String _sugarType = 'Corn Sugar (Dextrose)';
  final _customFactorCtrl = TextEditingController(text: '');

  // Force-carb tab state
  final _forceTempCtrl  = TextEditingController(text: '38');
  final _forceVolsCtrl  = TextEditingController(text: '2.6');

  @override
  void dispose() {
    _batchCtrl.dispose();
    _tempCtrl.dispose();
    _targetVolsCtrl.dispose();
    _customFactorCtrl.dispose();
    _forceTempCtrl.dispose();
    _forceVolsCtrl.dispose();
    super.dispose();
  }

  double _parse(TextEditingController c, {double fallback = 0}) {
    final v = double.tryParse(c.text.trim());
    return (v == null || !v.isFinite) ? fallback : v;
    }

  double _sugarFactorForSelection() {
  switch (_sugarType) {
    case 'Corn Sugar (Dextrose)':
      return _useGal ? _CO2CarbMath.cornSugarGalFactor : _CO2CarbMath.cornSugarLFactor;
    case 'Table Sugar (Sucrose)':
      return _useGal ? _CO2CarbMath.tableSugarGalFactor : _CO2CarbMath.tableSugarLFactor;
    case 'DME (Light)':
      return _useGal ? _CO2CarbMath.dmeGalFactor : _CO2CarbMath.dmeLFactor;
    case 'Custom…':
      final v = double.tryParse(_customFactorCtrl.text.trim());
      return (v == null || v <= 0)
          ? (_useGal ? _CO2CarbMath.cornSugarGalFactor : _CO2CarbMath.cornSugarLFactor)
          : v;
    default:
      return _useGal ? _CO2CarbMath.cornSugarGalFactor : _CO2CarbMath.cornSugarLFactor;
  }
}


  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CO₂ & Carbonation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const _CO2HelpDialog(),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _UnitRow(
            useF: _useF,
            useGal: _useGal,
            onTempChanged: (v) => setState(() => _useF = v),
            onVolChanged: (v) => setState(() => _useGal = v),
          ),
          const SizedBox(height: 12),
          _PrimingSugarCard(
            batchCtrl: _batchCtrl,
            tempCtrl: _tempCtrl,
            targetVolsCtrl: _targetVolsCtrl,
            sugarType: _sugarType,
            onSugarTypeChanged: (v) => setState(() => _sugarType = v),
            customFactorCtrl: _customFactorCtrl,
            useF: _useF,
            useGal: _useGal,
            secondary: secondary,
            compute: () {
              final grams = _CO2CarbMath.primingSugarGrams(
                targetVolumes: _parse(_targetVolsCtrl, fallback: 2.8),
                fermTemp: _parse(_tempCtrl, fallback: _useF ? 68 : 20),
                tempIsF: _useF,
                batchVolume: _parse(_batchCtrl, fallback: _useGal ? 5.0 : 19.0),
                volumeIsGal: _useGal,
                sugarFactor: _sugarFactorForSelection(),
              );
              final ounces = grams / 28.349523125;
              final tempF = _useF ? _parse(_tempCtrl, fallback: 68) : _CO2CarbMath.cToF(_parse(_tempCtrl, fallback: 20));
              final residual = _CO2CarbMath.residualVolsAtF(tempF);
              return _PrimingResult(grams: grams, ounces: ounces, residualVols: residual);
            },
          ),
          const SizedBox(height: 16),
          _ForceCarbCard(
            tempCtrl: _forceTempCtrl,
            volsCtrl: _forceVolsCtrl,
            useF: _useF,
            secondary: secondary,
            compute: () {
              final targetVols = _parse(_forceVolsCtrl, fallback: 2.6);
              final tempF = _useF
                  ? _parse(_forceTempCtrl, fallback: 38)
                  : _CO2CarbMath.cToF(_parse(_forceTempCtrl, fallback: 3.3));
              final psi = _CO2CarbMath.psiForVolumesF(targetVolumes: targetVols, tempF: tempF);
              final kPa = psi * 6.89476;
              return _ForceResult(psi: psi, kPa: kPa);
            },
          ),
          const SizedBox(height: 16),
          _SafetyNote(secondary: secondary),
        ],
      ),
    );
  }
}

/* ───────────────────────── widgets ───────────────────────── */

class _UnitRow extends StatelessWidget {
  final bool useF, useGal;
  final ValueChanged<bool> onTempChanged, onVolChanged;

  const _UnitRow({
    required this.useF,
    required this.useGal,
    required this.onTempChanged,
    required this.onVolChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text('Temp:', style: textStyle),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('°F'),
                selected: useF,
                onSelected: (_) => onTempChanged(true),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('°C'),
                selected: !useF,
                onSelected: (_) => onTempChanged(false),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Volume:', style: textStyle),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('gal'),
                selected: useGal,
                onSelected: (_) => onVolChanged(true),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('L'),
                selected: !useGal,
                onSelected: (_) => onVolChanged(false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrimingResult {
  final double grams, ounces, residualVols;
  _PrimingResult({required this.grams, required this.ounces, required this.residualVols});
}

class _PrimingSugarCard extends StatelessWidget {
  final TextEditingController batchCtrl, tempCtrl, targetVolsCtrl, customFactorCtrl;
  final String sugarType;
  final ValueChanged<String> onSugarTypeChanged;
  final bool useF, useGal;
  final Color secondary;
  final _PrimingResult Function() compute;

  const _PrimingSugarCard({
    required this.batchCtrl,
    required this.tempCtrl,
    required this.targetVolsCtrl,
    required this.sugarType,
    required this.onSugarTypeChanged,
    required this.customFactorCtrl,
    required this.useF,
    required this.useGal,
    required this.secondary,
    required this.compute,
  });

  @override
  Widget build(BuildContext context) {
    final res = compute();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: _LabeledNumberField(label: 'Batch Size', controller: batchCtrl, suffix: useGal ? 'gal' : 'L')),
              const SizedBox(width: 12),
              Expanded(child: _LabeledNumberField(label: 'Fermentation Temp', controller: tempCtrl, suffix: useF ? '°F' : '°C')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _LabeledNumberField(label: 'Target CO₂ Volumes', controller: targetVolsCtrl, suffix: 'vols')),
              const SizedBox(width: 12),
              Expanded(
                child: _SugarTypePicker(
                  sugarType: sugarType,
                  onChanged: onSugarTypeChanged,
                  customFactorCtrl: customFactorCtrl,
                  useGal: useGal,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: secondary.withOpacity(0.08),
                border: Border.all(color: secondary.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${res.grams.toStringAsFixed(1)} g  •  ${(res.ounces).toStringAsFixed(2)} oz',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: secondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Residual CO₂ at ${tempCtrl.text}${useF ? '°F' : '°C'} ≈ ${res.residualVols.toStringAsFixed(2)} vols',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SugarTypePicker extends StatelessWidget {
  final String sugarType;
  final ValueChanged<String> onChanged;
  final TextEditingController customFactorCtrl;
  final bool useGal;

  const _SugarTypePicker({
    required this.sugarType,
    required this.onChanged,
    required this.customFactorCtrl,
    required this.useGal,
  });

  @override
  Widget build(BuildContext context) {
    final options = const [
      'Corn Sugar (Dextrose)',
      'Table Sugar (Sucrose)',
      'DME (Light)',
      'Custom…',
    ];

    final hint = useGal
        ? 'Factor (g/gal/vol)'
        : 'Factor (g/L/vol)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sugar Type', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: sugarType,
          isExpanded: true,
          items: options.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => onChanged(v ?? options.first),
        ),
        if (sugarType == 'Custom…') ...[
          const SizedBox(height: 8),
          _LabeledNumberField(label: hint, controller: customFactorCtrl, suffix: ''),
        ],
      ],
    );
  }
}

class _ForceResult {
  final double psi, kPa;
  _ForceResult({required this.psi, required this.kPa});
}

class _ForceCarbCard extends StatelessWidget {
  final TextEditingController tempCtrl, volsCtrl;
  final bool useF;
  final Color secondary;
  final _ForceResult Function() compute;

  const _ForceCarbCard({
    required this.tempCtrl,
    required this.volsCtrl,
    required this.useF,
    required this.secondary,
    required this.compute,
  });

  @override
  Widget build(BuildContext context) {
    final res = compute();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: _LabeledNumberField(label: 'Beverage Temp', controller: tempCtrl, suffix: useF ? '°F' : '°C')),
              const SizedBox(width: 12),
              Expanded(child: _LabeledNumberField(label: 'Target CO₂ Volumes', controller: volsCtrl, suffix: 'vols')),
            ]),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: secondary.withOpacity(0.08),
                border: Border.all(color: secondary.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${res.psi.toStringAsFixed(1)} PSI  •  ${res.kPa.toStringAsFixed(1)} kPa',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: secondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tip: Colder liquid needs less PSI for the same carbonation.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledNumberField extends StatelessWidget {
  final String label, suffix;
  final TextEditingController controller;

  const _LabeledNumberField({
    required this.label,
    required this.controller,
    required this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _SafetyNote extends StatelessWidget {
  final Color secondary;
  const _SafetyNote({required this.secondary});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Safety: High carbonation (>3.0 vols) increases bottling pressure. Use proper bottles, '
      'verify priming rates, and when in doubt, keg or use thicker glass.',
      style: TextStyle(fontSize: 12, color: secondary.withOpacity(0.9)),
      textAlign: TextAlign.center,
    );
  }
}

class _CO2HelpDialog extends StatelessWidget {
  const _CO2HelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('CO₂ & Carbonation'),
      content: const Text(
        '• “CO₂ Volumes” describes how much dissolved CO₂ is in your beverage.\n'
        '• For bottling: enter your batch size, fermentation temp, target volumes, and sugar type. '
        'We’ll subtract residual CO₂ and compute priming sugar.\n'
        '• For kegging: enter the beverage temp and desired volumes to get regulator PSI.\n\n'
        'Notes:\n'
        '• Residual CO₂ is based on beer/cider residuals at the listed temps.\n'
        '• Factors (g/gal/vol or g/L/vol) can be customized.\n'
        '• Use appropriate bottles for high-volume carbonation.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
      ],
    );
  }
}
