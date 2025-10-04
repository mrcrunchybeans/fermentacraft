// lib/pages/co2_carb_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CO2CarbPage extends StatefulWidget {
  const CO2CarbPage({super.key});

  @override
  State<CO2CarbPage> createState() => _CO2CarbPageState();
}

/* ────────────────────────────────────────────────────────────────────────────
   MATH HELPERS (self-contained, unit-safe)
   - Residual CO2 (vols) via (°F → vols) lookup + linear interpolation
   - Priming sugar factors (gal/L variants)
   - Force carb PSI equation (empirical, standard homebrew)
   - Per-bottle sugar computation (mL-based)
   ──────────────────────────────────────────────────────────────────────────── */

class _CO2CarbMath {
  // Updated table: °F → residual CO2 (vols)
  static const List<double> _tempsF = [32, 40, 50, 60, 68, 70, 75];
  static const List<double> _vols   = [1.68, 1.53, 1.26, 1.05, 0.85, 0.85, 0.82];

  static const double _galToMl = 3785.411784;
  static const double _lToMl   = 1000.0;
  static const double _gPerOz  = 28.349523125;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double residualVolsAtF(double tempF) {
    if (!tempF.isFinite) return 0.85; // safe default ~68°F
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

  // Priming sugar factors (g per unit-volume per "vol" CO2)
  static const double cornSugarGalFactor  = 15.0; // g / gal / vol
  static const double tableSugarGalFactor = 13.7;
  static const double dmeGalFactor        = 18.9;

  static const double cornSugarLFactor  = 3.95; // g / L / vol
  static const double tableSugarLFactor = 3.62;
  static const double dmeLFactor        = 5.00;

  static double _sanitize(double x, double fallback) {
    return (x.isFinite) ? x : fallback;
  }

  /// Priming sugar needed in grams.
  /// volumeIsGal controls whether `batchVolume` is in gal (true) or liters (false).
  /// sugarFactor must match the same volume unit system (gal- or L- factor).
  static double primingSugarGrams({
    required double targetVolumes,
    required double fermTemp,
    required bool tempIsF,
    required double batchVolume,
    required bool volumeIsGal,
    required double sugarFactor,
  }) {
    final vt   = _sanitize(targetVolumes, 2.6).clamp(0.0, 5.0);
    final vol  = _sanitize(batchVolume, volumeIsGal ? 5.0 : 19.0).clamp(0.0, 10000.0);
    final fact = _sanitize(sugarFactor, volumeIsGal ? cornSugarGalFactor : cornSugarLFactor)
        .clamp(0.1, 50.0);

    final tempF = tempIsF ? _sanitize(fermTemp, 68.0) : cToF(_sanitize(fermTemp, 20.0));
    final residual = residualVolsAtF(tempF);

    final deltaV = (vt - residual);
    if (deltaV <= 0) return 0.0;

    final grams = deltaV * vol * fact;
    return grams.isFinite ? grams : 0.0;
  }

  /// Force carbonation: PSI for target vols at temp °F
  static double psiForVolumesF({
    required double targetVolumes,
    required double tempF,
  }) {
    final V = _sanitize(targetVolumes, 2.6).clamp(0.0, 5.0);
    final T = _sanitize(tempF, 38.0);

    final psi = -16.6999
        - 0.0101059 * T
        + 0.00116512 * T * T
        + 0.173354 * T * V
        + 4.24267 * V
        - 0.0684226 * V * V;

    if (!psi.isFinite) return 0.0;
    return psi < 0 ? 0.0 : psi;
  }

  /// Batch volume (gal/L) → mL
  static double batchToMl(double batchVolume, {required bool volumeIsGal}) {
    if (!batchVolume.isFinite || batchVolume <= 0) return 0.0;
    return volumeIsGal ? batchVolume * _galToMl : batchVolume * _lToMl;
  }

  /// Per-bottle sugar (grams), using mL bottle size and total grams for batch.
  static double perBottleGrams({
    required double totalPrimingGrams,
    required double batchVolume,
    required bool volumeIsGal,
    required double bottleSizeMl,
  }) {
    if (!totalPrimingGrams.isFinite || totalPrimingGrams <= 0) return 0.0;
    final batchMl = batchToMl(batchVolume, volumeIsGal: volumeIsGal);
    if (batchMl <= 0) return 0.0;
    final ml = bottleSizeMl.isFinite && bottleSizeMl > 0 ? bottleSizeMl : 355.0; // default 12 oz
    final g = totalPrimingGrams * (ml / batchMl);
    return g.isFinite && g > 0 ? g : 0.0;
  }

  static double gramsToOz(double grams) => grams / _gPerOz;
}

/* ────────────────────────────────────────────────────────────────────────────
   UI
   - AppBar w/ help icon → dialog
   - Unit toggles (°F/°C, gal/L)
   - Priming sugar card with residual note + per-bottle helper (presets + custom)
   - Force-carb card with PSI/kPa
   - Theme-friendly result panels (surfaceVariant / onSurfaceVariant)
   ──────────────────────────────────────────────────────────────────────────── */

class _CO2CarbPageState extends State<CO2CarbPage> {
  // Page-local unit toggles
  bool _useF = true;
  bool _useGal = true;

  // Priming sugar inputs
  final _batchCtrl = TextEditingController(text: '5.0');
  final _tempCtrl  = TextEditingController(text: '68');
  final _targetVolsCtrl = TextEditingController(text: '2.8');

  String _sugarType = 'Corn Sugar (Dextrose)';
  final _customFactorCtrl = TextEditingController(text: '');

  // Per-bottle helper
  String _bottlePreset = '355 mL (12 oz)';
  final _customBottleMlCtrl = TextEditingController(text: '');

  // Force-carb inputs
  final _forceTempCtrl  = TextEditingController(text: '38');
  final _forceVolsCtrl  = TextEditingController(text: '2.6');

  @override
  void dispose() {
    _batchCtrl.dispose();
    _tempCtrl.dispose();
    _targetVolsCtrl.dispose();
    _customFactorCtrl.dispose();
    _customBottleMlCtrl.dispose();
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
            : v.clamp(0.1, 50.0);
      default:
        return _useGal ? _CO2CarbMath.cornSugarGalFactor : _CO2CarbMath.cornSugarLFactor;
    }
  }

  // Bottle preset → mL
  double _bottlePresetToMl(String preset) {
    switch (preset) {
      case '330 mL':
        return 330.0;
      case '355 mL (12 oz)':
        return 355.0;
      case '375 mL':
        return 375.0;
      case '500 mL (pint-ish)':
        return 500.0;
      case '650 mL (22 oz bomber)':
        return 650.0;
      case '750 mL':
        return 750.0;
      case 'Custom…':
        final v = double.tryParse(_customBottleMlCtrl.text.trim());
        return (v == null || v <= 0) ? 355.0 : v; // default 12 oz if empty
      default:
        return 355.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
            scheme: scheme,
            batchCtrl: _batchCtrl,
            tempCtrl: _tempCtrl,
            targetVolsCtrl: _targetVolsCtrl,
            sugarType: _sugarType,
            onSugarTypeChanged: (v) => setState(() => _sugarType = v),
            customFactorCtrl: _customFactorCtrl,
            useF: _useF,
            useGal: _useGal,
            computePriming: () {
              final grams = _CO2CarbMath.primingSugarGrams(
                targetVolumes: _parse(_targetVolsCtrl, fallback: 2.8),
                fermTemp: _parse(_tempCtrl, fallback: _useF ? 68 : 20),
                tempIsF: _useF,
                batchVolume: _parse(_batchCtrl, fallback: _useGal ? 5.0 : 19.0),
                volumeIsGal: _useGal,
                sugarFactor: _sugarFactorForSelection(),
              );
              final ounces = _CO2CarbMath.gramsToOz(grams);
              final tempF = _useF
                  ? _parse(_tempCtrl, fallback: 68)
                  : _CO2CarbMath.cToF(_parse(_tempCtrl, fallback: 20));
              final residual = _CO2CarbMath.residualVolsAtF(tempF);
              return _PrimingResult(grams: grams, ounces: ounces, residualVols: residual);
            },
            // Per-bottle helper wires
            bottlePreset: _bottlePreset,
            onBottlePresetChanged: (v) => setState(() => _bottlePreset = v),
            customBottleMlCtrl: _customBottleMlCtrl,
            computePerBottle: (totalGrams) {
              final ml = _bottlePresetToMl(_bottlePreset);
              return _CO2CarbMath.perBottleGrams(
                totalPrimingGrams: totalGrams,
                batchVolume: _parse(_batchCtrl, fallback: _useGal ? 5.0 : 19.0),
                volumeIsGal: _useGal,
                bottleSizeMl: ml,
              );
            },
          ),
          const SizedBox(height: 16),
          _ForceCarbCard(
            scheme: scheme,
            tempCtrl: _forceTempCtrl,
            volsCtrl: _forceVolsCtrl,
            useF: _useF,
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
          _SafetyNote(scheme: scheme),
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
  final ColorScheme scheme;
  final TextEditingController batchCtrl, tempCtrl, targetVolsCtrl, customFactorCtrl;
  final String sugarType;
  final ValueChanged<String> onSugarTypeChanged;
  final bool useF, useGal;
  final _PrimingResult Function() computePriming;

  // Per-bottle helper
  final String bottlePreset;
  final ValueChanged<String> onBottlePresetChanged;
  final TextEditingController customBottleMlCtrl;
  final double Function(double totalGrams) computePerBottle;

  const _PrimingSugarCard({
    required this.scheme,
    required this.batchCtrl,
    required this.tempCtrl,
    required this.targetVolsCtrl,
    required this.sugarType,
    required this.onSugarTypeChanged,
    required this.customFactorCtrl,
    required this.useF,
    required this.useGal,
    required this.computePriming,
    required this.bottlePreset,
    required this.onBottlePresetChanged,
    required this.customBottleMlCtrl,
    required this.computePerBottle,
  });

  @override
  Widget build(BuildContext context) {
    final res = computePriming();
    final sugarIsZero = (res.grams <= 0.0001);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: _LabeledNumberField(
                  label: 'Batch Size',
                  controller: batchCtrl,
                  suffix: useGal ? 'gal' : 'L',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LabeledNumberField(
                  label: 'Fermentation Temp',
                  controller: tempCtrl,
                  suffix: useF ? '°F' : '°C',
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _LabeledNumberField(
                  label: 'Target CO₂ Volumes',
                  controller: targetVolsCtrl,
                  suffix: 'vols',
                ),
              ),
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
                borderRadius: BorderRadius.circular(12),
                color: scheme.surfaceVariant,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${res.grams.toStringAsFixed(1)} g  •  ${res.ounces.toStringAsFixed(2)} oz',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Residual CO₂ at ${tempCtrl.text}${useF ? '°F' : '°C'} ≈ ${res.residualVols.toStringAsFixed(2)} vols',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  if (sugarIsZero) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Target ≤ residual CO₂ — no priming sugar needed.',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _PerBottleHelper(
              scheme: scheme,
              enabled: !sugarIsZero,
              bottlePreset: bottlePreset,
              onBottlePresetChanged: onBottlePresetChanged,
              customBottleMlCtrl: customBottleMlCtrl,
              computePerBottle: () => computePerBottle(res.grams),
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
    const options = [
      'Corn Sugar (Dextrose)',
      'Table Sugar (Sucrose)',
      'DME (Light)',
      'Custom…',
    ];

    final hint = useGal ? 'Factor (g/gal/vol)' : 'Factor (g/L/vol)';

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

class _PerBottleHelper extends StatelessWidget {
  final ColorScheme scheme;
  final bool enabled;
  final String bottlePreset;
  final ValueChanged<String> onBottlePresetChanged;
  final TextEditingController customBottleMlCtrl;
  final double Function() computePerBottle;

  const _PerBottleHelper({
    required this.scheme,
    required this.enabled,
    required this.bottlePreset,
    required this.onBottlePresetChanged,
    required this.customBottleMlCtrl,
    required this.computePerBottle,
  });

  @override
  Widget build(BuildContext context) {
    const presets = [
      '330 mL',
      '355 mL (12 oz)',
      '375 mL',
      '500 mL (pint-ish)',
      '650 mL (22 oz bomber)',
      '750 mL',
      'Custom…',
    ];

    final gPerBottle = enabled ? computePerBottle() : 0.0;
    final ozPerBottle = enabled ? _CO2CarbMath.gramsToOz(gPerBottle) : 0.0;

    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Per-bottle dosing'),
              childrenPadding: const EdgeInsets.only(top: 8, left: 0, right: 0, bottom: 8),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: bottlePreset,
                        isExpanded: true,
                        items: presets.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) => onBottlePresetChanged(v ?? presets.first),
                        decoration: const InputDecoration(
                          labelText: 'Bottle Size',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (bottlePreset == 'Custom…')
                      Expanded(
                        child: _LabeledNumberField(
                          label: 'Custom mL',
                          controller: customBottleMlCtrl,
                          suffix: 'mL',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: scheme.surfaceVariant,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${gPerBottle.toStringAsFixed(1)} g  •  ${ozPerBottle.toStringAsFixed(2)} oz per bottle',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tip: Mix a priming solution and dose evenly, or bulk-prime then bottle.',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ForceResult {
  final double psi, kPa;
  _ForceResult({required this.psi, required this.kPa});
}

class _ForceCarbCard extends StatelessWidget {
  final ColorScheme scheme;
  final TextEditingController tempCtrl, volsCtrl;
  final bool useF;
  final _ForceResult Function() compute;

  const _ForceCarbCard({
    required this.scheme,
    required this.tempCtrl,
    required this.volsCtrl,
    required this.useF,
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
              Expanded(
                child: _LabeledNumberField(
                  label: 'Beverage Temp',
                  controller: tempCtrl,
                  suffix: useF ? '°F' : '°C',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LabeledNumberField(
                  label: 'Target CO₂ Volumes',
                  controller: volsCtrl,
                  suffix: 'vols',
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: scheme.surfaceVariant,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${res.psi.toStringAsFixed(1)} PSI  •  ${res.kPa.toStringAsFixed(1)} kPa',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tip: Colder liquid needs less PSI for the same carbonation.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
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
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^[0-9]*[.]?[0-9]*$')),
      ],
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
  final ColorScheme scheme;
  const _SafetyNote({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Safety: High carbonation (>3.0 vols) increases bottling pressure. Use proper bottles, '
      'verify priming rates, and when in doubt, keg or use thicker glass.',
      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      textAlign: TextAlign.center,
    );
  }
}

class _CO2HelpDialog extends StatelessWidget {
  const _CO2HelpDialog();

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AlertDialog(
      title: const Text('CO₂ & Carbonation'),
      content: Text(
        '• “CO₂ Volumes” describes how much dissolved CO₂ is in your beverage.\n'
        '• For bottling: enter your batch size, fermentation temp, target volumes, and sugar type. '
        'We’ll subtract residual CO₂ and compute priming sugar.\n'
        '• For kegging: enter the beverage temp and desired volumes to get regulator PSI.\n\n'
        'Notes:\n'
        '• Residual CO₂ is based on beer/cider residuals at the listed temps.\n'
        '• Factors (g/gal/vol or g/L/vol) can be customized.\n'
        '• Use appropriate bottles for high-volume carbonation.',
        style: TextStyle(color: onSurface),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
      ],
    );
  }
}
