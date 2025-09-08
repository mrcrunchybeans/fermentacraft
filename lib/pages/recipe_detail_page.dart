// lib/pages/recipe_detail_page.dart
import 'package:fermentacraft/services/firestore_sync_service.dart';
import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:fermentacraft/models/settings_model.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/models/enums.dart';
import 'package:fermentacraft/utils/gravity_utils.dart' as gu;
import 'package:fermentacraft/utils/temp_display.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/utils/id.dart';
import 'package:fermentacraft/utils/boxes.dart';
import 'package:fermentacraft/utils/recipe_to_batch.dart';

import 'recipe_builder_page.dart';
import 'recipe_list_page.dart';
import 'batch_detail_page.dart';
import '../models/batch_model.dart';

String _unitSymbol(dynamic unit) {
  final s = unit?.toString().toLowerCase() ?? '';
  return s.startsWith('f') ? '°F' : '°C';
}

class RecipeDetailPage extends StatefulWidget {
  const RecipeDetailPage({super.key, required this.recipe, required this.recipeKey});

  final RecipeModel recipe;
  final dynamic recipeKey;

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

void _upsell(BuildContext context, String reason) {
  debugPrint('Upsell trigger: $reason');
  showPaywall(context);
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  // Scroll + section anchors
  final _scroll = ScrollController();
  final _kStats = GlobalKey();
  final _kFermentables = GlobalKey();
  final _kYeast = GlobalKey();
  final _kAdditives = GlobalKey();
  final _kFermentation = GlobalKey();
  final _kNotes = GlobalKey();

  // UI state for stats volume unit (default to gallons)
  VolumeUiUnit _statsUnit = VolumeUiUnit.gallons;

  // ---------- responsive font scale ----------
  double _fontScale(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 1200) return 1.10;
    if (w >= 900)  return 1.05;
    if (w >= 600)  return 1.02;
    return 1.00;
  }

  // ---------- light helpers ----------
  double _normDensity(double? d, {required double fallback}) {
    if (d == null) return fallback;
    if (d >= 100.0) return d / 1000.0; // g/L → g/mL
    if (d > 5.0 && d < 25.0) return d / 10.0; // 14.2 → 1.42
    if (d < 0.2) return d * 10.0; // 0.14 → 1.4
    return d;
  }

  Map<String, dynamic> safeMap(dynamic input) {
    if (input is Map<String, dynamic>) return input;
    if (input is Map) return input.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final box = Hive.box<RecipeModel>(Boxes.recipes);
      DateTime roundToHour(DateTime t) => DateTime(t.year, t.month, t.day, t.hour);

      final updated = widget.recipe..lastOpened = roundToHour(DateTime.now());
      await box.put(widget.recipeKey, updated);

    });
  }

  ({double sugarG, double volumeMl, double brix, double sg}) _deriveStats(RecipeModel r) {
    double totalSugarG = 0.0;
    double totalMl = 0.0;

    for (final raw in r.ingredients) {
      final m = safeMap(raw);

      final typeName = (m['type'] ?? '').toString();
      final FermentableType type = FermentableType.values.firstWhere(
        (t) => t.name == typeName,
        orElse: () => FermentableType.sugar,
      );

      final double? brix = (m['brix'] as num?)?.toDouble();
      final double? density = (m['density'] as num?)?.toDouble();
      final double? weightG = (m['weightG'] as num?)?.toDouble();
      final double? volumeMl = (m['volumeMl'] as num?)?.toDouble();

      final double dens = _normDensity(
        density ?? type.defaultDensity,
        fallback: type.defaultDensity,
      );

      // Volume
      double lineMl = 0.0;
      if (volumeMl != null && volumeMl > 0) {
        lineMl = volumeMl;
      } else if (weightG != null && weightG > 0 && type.isLiquid) {
        lineMl = weightG / dens;
      } else if (type == FermentableType.fruit) {
        lineMl = _estimateFruitMlFromMap(m, weightG);
      }

      // Sugar grams
      final double b = (brix ?? type.defaultBrix) / 100.0;
      double lineSugarG = 0.0;
      if (weightG != null && weightG > 0) {
        lineSugarG = b * weightG;
      } else if (lineMl > 0) {
        lineSugarG = b * (lineMl * dens);
      }

      totalMl += lineMl;
      totalSugarG += lineSugarG;
    }

    final double brixOut = totalMl > 0 ? (totalSugarG / totalMl) * 100.0 : 0.0;
    final double sgOut = gu.brixToSg(brixOut);

    return (sugarG: totalSugarG, volumeMl: totalMl, brix: brixOut, sg: sgOut);
  }

  double _estimateFruitMlFromMap(Map<String, dynamic> m, double? weightG) {
    if ((weightG ?? 0) <= 0) return 0.0;

    final double? overrideGalPerLb = (m['fruitYieldGalPerLb'] as num?)?.toDouble();

    FruitCategory cat;
    final fc = (m['fruitCategory'] ?? '').toString();
    switch (fc) {
      case 'stone':     cat = FruitCategory.stone; break;
      case 'pome':      cat = FruitCategory.pome; break;
      case 'tropical':  cat = FruitCategory.tropical; break;
      case 'other':     cat = FruitCategory.other; break;
      case 'berries':
      default:          cat = FruitCategory.berries; break;
    }

    final double baseGalPerLb = overrideGalPerLb ?? cat.defaultGalPerLb;
    final double galPerLb = baseGalPerLb.clamp(0.05, 0.20);

    const double lbsPerGram = 0.00220462262185;
    const double mlPerGal = 3785.411784;

    final pounds = (weightG ?? 0.0) * lbsPerGram;
    return pounds * galPerLb * mlPerGal;
  }

  // ---------- App bar actions ----------
  void _editRecipe(BuildContext context, RecipeModel recipe) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeBuilderPage(
        existingRecipe: recipe,
        recipeKey: widget.recipeKey,
      ),
    ));
  }

  void _cloneRecipe(BuildContext context, RecipeModel recipe) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeBuilderPage(
        existingRecipe: recipe,
        isClone: true,
      ),
    ));
  }

  Future<void> _createBatchFromRecipe(RecipeModel recipe) async {
    Map<String, dynamic> sm(dynamic x) => safeMap(x);

    final clonedIngredients = recipe.ingredients
        .map<Map<String, dynamic>>((e) => recipeIngredientToBatch(sm(e)))
        .toList();

    final clonedAdditives = recipe.additives
        .map<Map<String, dynamic>>((e) => recipeAdditiveToBatch(sm(e)))
        .toList();

    final clonedYeast = recipe.yeast
        .map<Map<String, dynamic>>((e) => recipeYeastToBatch(sm(e)))
        .toList();

    final List<FermentationStage> clonedStages =
        recipe.fermentationStages.map<FermentationStage>((dynamic s) {
      if (s is FermentationStage) return FermentationStage.fromJson(s.toJson());
      return FermentationStage.fromJson(Map<String, dynamic>.from(s as Map));
    }).toList();

    final stats = _deriveStats(recipe);

    final now = DateTime.now();
    final pretty = DateFormat.yMMMd().add_jm().format(now);

    final batch = BatchModel(
      id: generateId(),
      name: recipe.name,
      recipeId: recipe.id,
      startDate: now,
      createdAt: now,
      ingredients: clonedIngredients,
      additives: clonedAdditives,
      yeast: clonedYeast,
      fermentationStages: clonedStages,
      batchVolume: VolumeUiUnit.gallons.fromMl(stats.volumeMl),
      plannedOg: recipe.og ?? stats.sg,
      plannedAbv: recipe.abv,
      notes: 'Created from recipe "${recipe.name}" on $pretty',
    );

    final box = Hive.box<BatchModel>(Boxes.batches);
    await box.put(batch.id, batch);

    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BatchDetailPage(batchKey: batch.id),
    ));
  }

  Future<void> _deleteRecipe(BuildContext context) async {
    final navigator = Navigator.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Recipe'),
        content: const Text('Are you sure you want to delete this recipe? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    final box = Hive.box<RecipeModel>(Boxes.recipes);
    final RecipeModel? current = (widget.recipeKey != null) ? box.get(widget.recipeKey) : null;

    final String? id = current?.id;
    if (id != null && id.trim().isNotEmpty) {
      await FirestoreSyncService.instance.markDeleted(collection: Boxes.recipes, id: id);
    }

    dynamic keyToDelete = widget.recipeKey;
    if (current != null && current.key != null) {
      keyToDelete = current.key;
    } else if (id != null && id.trim().isNotEmpty) {
      final map = box.toMap();
      for (final entry in map.entries) {
        final v = entry.value;
        if (v.id == id) {
          keyToDelete = entry.key;
          break;
        }
      }
    }

    final idsToTombstone = <String>{};
    if (id != null && id.trim().isNotEmpty) idsToTombstone.add(id.trim());
    final keyStr = widget.recipeKey?.toString().trim();
    if (keyStr != null && keyStr.isNotEmpty) idsToTombstone.add(keyStr);
    final objKeyStr = (current?.key)?.toString().trim();
    if (objKeyStr != null && objKeyStr.isNotEmpty) idsToTombstone.add(objKeyStr);
    for (final rid in idsToTombstone) {
      await FirestoreSyncService.instance.markDeleted(collection: Boxes.recipes, id: rid);
    }

    await box.delete(keyToDelete);
    await FirestoreSyncService.instance.forceSync();

    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacement(MaterialPageRoute(builder: (_) => const RecipeListPage()));
    }
  }

  // ---------- UI helpers ----------
  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ', style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  Widget _jumpBar() {
    final items = [
      ('Stats', _kStats, Icons.analytics_outlined),
      ('Fermentables', _kFermentables, Icons.local_fire_department_outlined),
      ('Yeast', _kYeast, Icons.biotech_outlined),
      ('Additives', _kAdditives, Icons.science_outlined),
      ('Fermentation', _kFermentation, Icons.timeline),
      ('Notes', _kNotes, Icons.note_alt_outlined),
    ];
    final lbl = Theme.of(context).textTheme.labelLarge;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: DefaultTextStyle.merge(
          style: lbl?.copyWith(
            fontSize: (lbl.fontSize ?? 14) * _fontScale(context),
            fontWeight: FontWeight.w600,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map((t) => ActionChip(
                      avatar: Icon(t.$3, size: 18),
                      label: Text(t.$1),
                      onPressed: () => _scrollTo(t.$2),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _heroCard(RecipeModel recipe) {
    final created = DateFormat.yMMMd().format(recipe.createdAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            const Icon(Icons.receipt_long),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(spacing: 12, runSpacing: 8, children: [
                _chip('Category', recipe.categoryLabel),
                _chip('Created', created),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // --- subtle metric + unit dropdown + target chip helpers -------------------
  Widget _miniMetric(BuildContext context, {required String label, required String value, bool muted = false}) {
    final t  = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s  = _fontScale(context);

    final labelStyle = t.labelSmall?.copyWith(
      fontSize: (t.labelSmall?.fontSize ?? 12) * (s * 0.95),
      color: cs.onSurface.withOpacity(0.68),
      letterSpacing: 0.15,
    );

    final valueStyle = t.titleMedium?.copyWith(
      fontSize: ((t.titleMedium?.fontSize ?? 16) * (s * 1.00)).clamp(14, 18),
      fontWeight: FontWeight.w700,
      color: muted ? cs.onSurface.withOpacity(0.60) : cs.onSurface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 2),
        Text(value, style: valueStyle),
      ],
    );
  }

  Widget _unitDropdownPill({
    required BuildContext context,
    required VolumeUiUnit value,
    required ValueChanged<VolumeUiUnit> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<VolumeUiUnit>(
          isDense: true,
          value: value,
          onChanged: (u) => onChanged(u ?? value),
          items: const [
            DropdownMenuItem(value: VolumeUiUnit.gallons, child: Text('gal')),
            DropdownMenuItem(value: VolumeUiUnit.liters,  child: Text('L')),
          ],
        ),
      ),
    );
  }

  Widget _targetChip(BuildContext context, String label, String value, {bool muted = false}) {
    final cs = Theme.of(context).colorScheme;
    final t  = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: t.labelSmall?.copyWith(color: cs.onSurface.withOpacity(0.65))),
          const SizedBox(width: 6),
          Text(
            value,
            style: t.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: muted ? cs.onSurface.withOpacity(0.60) : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // --- subtle Must Stats card ------------------------------------------------
  Widget _statsCard(RecipeModel recipe) {
    final d = _deriveStats(recipe);
    String fmt(num? v, {int frac = 3}) => (v == null) ? '—' : v.toStringAsFixed(frac);
    final estVol = _statsUnit.fromMl(d.volumeMl);

    final cs = Theme.of(context).colorScheme;
    final t  = Theme.of(context).textTheme;
    final s  = _fontScale(context);

    return Card(
      elevation: 0,
      color: cs.surfaceVariant.withOpacity(0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          key: _kStats,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science_outlined, size: 18, color: cs.onSurface.withOpacity(0.85)),
                const SizedBox(width: 8),
                Text(
                  'Must Stats',
                  style: t.titleMedium?.copyWith(
                    fontSize: (t.titleMedium?.fontSize ?? 18) * (s * 1.00),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _unitDropdownPill(
                  context: context,
                  value: _statsUnit,
                  onChanged: (u) => setState(() => _statsUnit = u),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (_, c) {
              final isNarrow = c.maxWidth < 520;
              final spacing = isNarrow ? 16.0 : 22.0;
              final run = isNarrow ? 10.0 : 12.0;

              return Wrap(
                spacing: spacing,
                runSpacing: run,
                children: [
                  _miniMetric(context, label: 'Est. OG',      value: d.sg.toStringAsFixed(3)),
                  _miniMetric(context, label: 'Est. Brix',    value: d.brix.toStringAsFixed(1)),
                  _miniMetric(context, label: 'Total Volume', value: '${estVol.toStringAsFixed(2)} ${_statsUnit.label}'),
                  _miniMetric(context, label: 'Total Sugar',  value: '${d.sugarG.toStringAsFixed(0)} g'),
                ],
              );
            }),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _targetChip(context, 'Target OG',  fmt(recipe.og, frac: 3), muted: recipe.og == null),
                _targetChip(context, 'Target FG',  fmt(recipe.fg, frac: 3), muted: recipe.fg == null),
                _targetChip(context, 'Target ABV', recipe.abv == null ? '—' : '${fmt(recipe.abv, frac: 1)}%', muted: recipe.abv == null),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fermentablesCard(RecipeModel recipe) {
    final lines = recipe.ingredients;
    if (lines.isEmpty) return const SizedBox.shrink();

    String fmtWeight(double? g) {
      if (g == null || g <= 0) return '';
      final lbs = WeightUnit.pounds.fromGrams(g);
      return '${lbs.toStringAsFixed(2)} ${WeightUnit.pounds.label}';
    }

    String fmtVolume(double? ml) {
      if (ml == null || ml <= 0) return '';
      final gal = VolumeUiUnit.gallons.fromMl(ml);
      return '${gal.toStringAsFixed(2)} ${VolumeUiUnit.gallons.label}';
    }

    return Card(
      key: _kFermentables,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(children: [
          const Icon(Icons.local_fire_department_outlined),
          const SizedBox(width: 8),
          Text('Fermentables', style: Theme.of(context).textTheme.titleMedium),
        ]),
        children: lines.map<Widget>((raw) {
          final m = safeMap(raw);
          final name = (m['name'] ?? 'Unnamed').toString();
          final typeName = (m['type'] ?? '').toString();
          final FermentableType type = FermentableType.values.firstWhere(
            (t) => t.name == typeName,
            orElse: () => FermentableType.sugar,
          );

          final weight = fmtWeight((m['weightG'] as num?)?.toDouble());
          final volume = fmtVolume((m['volumeMl'] as num?)?.toDouble());
          final brix = (m['brix'] as num?)?.toDouble();
          final density = (m['density'] as num?)?.toDouble();

          final subParts = <String>[];
          if (weight.isNotEmpty) subParts.add(weight);
          if (volume.isNotEmpty) subParts.add(volume);
          if (brix != null) subParts.add('${brix.toStringAsFixed(1)}°Bx');
          if (density != null) subParts.add('SG ${density.toStringAsFixed(3)}');

          return ListTile(
            title: Text(name),
            subtitle: Text(subParts.isEmpty ? type.label : '${type.label} • ${subParts.join(' • ')}'),
            dense: true,
          );
        }).toList(),
      ),
    );
  }

  Widget _yeastCard(RecipeModel recipe) {
    if (recipe.yeast.isEmpty) return const SizedBox.shrink();

    return Card(
      key: _kYeast,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(children: [
          const Icon(Icons.biotech_outlined),
          const SizedBox(width: 8),
          Text('Yeast', style: Theme.of(context).textTheme.titleMedium),
        ]),
        children: recipe.yeast.map((raw) {
          final y = safeMap(raw);
          final name = (y['name'] ?? 'Unnamed').toString();
          final form = (y['form'] ?? '').toString();
          final qty = (y['quantity'] as num?)?.toDouble();
          final unit = (y['unit'] ?? '').toString();

          final parts = <String>[];
          if (form.isNotEmpty) parts.add(form);
          if (qty != null) {
            final show = qty == qty.roundToDouble() ? qty.toStringAsFixed(0) : qty.toStringAsFixed(1);
            parts.add(unit.isNotEmpty ? '$show $unit' : show);
          }

          return ListTile(
            title: Text(name),
            subtitle: Text(parts.isEmpty ? '—' : parts.join(' • ')),
            dense: true,
          );
        }).toList(),
      ),
    );
  }

  Widget _additivesCard(RecipeModel recipe) {
    if (recipe.additives.isEmpty) return const SizedBox.shrink();

    return Card(
      key: _kAdditives,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(children: [
          const Icon(Icons.science_outlined),
          const SizedBox(width: 8),
          Text('Additives', style: Theme.of(context).textTheme.titleMedium),
        ]),
        children: recipe.additives.map((raw) {
          final a = safeMap(raw);
          final name = (a['name'] ?? 'Unnamed').toString();
          final qty = (a['quantity'] as num?)?.toDouble();
          final unit = (a['unit'] ?? '').toString();
          final when = (a['when'] ?? '').toString();
          final notes = (a['notes'] ?? '').toString();

          final parts = <String>[];
          if (qty != null) {
            final show = qty == qty.roundToDouble() ? qty.toStringAsFixed(0) : qty.toStringAsFixed(1);
            parts.add(unit.isNotEmpty ? '$show $unit' : show);
          }
          if (when.isNotEmpty) parts.add(when);
          if (notes.isNotEmpty) parts.add(notes);

          return ListTile(
            title: Text(name),
            subtitle: Text(parts.isEmpty ? '—' : parts.join(' • ')),
            dense: true,
          );
        }).toList(),
      ),
    );
  }

  Widget _fermentationCard(RecipeModel recipe) {
    final settings = context.watch<SettingsModel>();
    if (recipe.fermentationStages.isEmpty) return const SizedBox.shrink();

    return Card(
      key: _kFermentation,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(children: [
          const Icon(Icons.timeline),
          const SizedBox(width: 8),
          Text('Fermentation Profile', style: Theme.of(context).textTheme.titleMedium),
        ]),
        children: recipe.fermentationStages.map<Widget>((dynamic stage) {
          final FermentationStage s = (stage is FermentationStage)
              ? stage
              : FermentationStage.fromJson(Map<String, dynamic>.from(stage as Map));
          final temp = s.targetTempC?.toDisplay(targetUnit: settings.unit);
          final tempStr = temp == null ? '—' : '$temp${_unitSymbol(settings.unit)}';

          return ListTile(
            leading: const Icon(Icons.thermostat),
            title: Text(s.name),
            subtitle: Text('${s.durationDays} ${s.durationDays == 1 ? 'day' : 'days'} @ $tempStr'),
            dense: true,
          );
        }).toList(),
      ),
    );
  }

  Widget _notesCard(RecipeModel recipe) {
    if (recipe.notes.trim().isEmpty) return const SizedBox.shrink();
    return Card(
      key: _kNotes,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Notes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(recipe.notes),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<RecipeModel>>(
      valueListenable: Hive.box<RecipeModel>(Boxes.recipes).listenable(keys: [widget.recipeKey]),
      builder: (context, box, _) {
        final recipe = box.get(widget.recipeKey);
        if (recipe == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Recipe not found. It may have been deleted.')),
          );
        }

        final fg = context.watch<FeatureGate>();
        final freeLimit = fg.recipeLimitFree;
        final recipeCount = Hive.box<RecipeModel>(Boxes.recipes).length;
        final atRecipeLimit = !fg.isPremium && recipeCount >= freeLimit;

        return Scaffold(
          appBar: AppBar(
            title: Builder(
              builder: (ctx) {
                final s = _fontScale(ctx);
                final base = Theme.of(ctx).textTheme.titleLarge;
                return Text(
                  recipe.name,
                  style: base?.copyWith(
                    fontSize: (base.fontSize ?? 20) * (s * 1.05),
                    fontWeight: FontWeight.w800,
                  ),
                );
              },
            ),
            actions: [
              IconButton(onPressed: () => _editRecipe(context, recipe), icon: const Icon(Icons.edit), tooltip: 'Edit'),
              IconButton(
                onPressed: atRecipeLimit
                    ? () => _upsell(context, 'Free limit reached ($freeLimit recipes). Upgrade to copy.')
                    : () => _cloneRecipe(context, recipe),
                icon: const Icon(Icons.copy),
                tooltip: atRecipeLimit ? 'Upgrade to copy' : 'Copy recipe',
              ),
              PopupMenuButton<String>(
                onSelected: (v) { if (v == 'delete') _deleteRecipe(context); },
                itemBuilder: (context) => const [PopupMenuItem(value: 'delete', child: Text('Delete'))],
              ),
            ],
          ),
          body: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            children: [
              _heroCard(recipe),
              const SizedBox(height: 8),
              _jumpBar(),
              const SizedBox(height: 12),
              _statsCard(recipe),
              const SizedBox(height: 12),
              _fermentablesCard(recipe),
              const SizedBox(height: 12),
              _yeastCard(recipe),
              const SizedBox(height: 12),
              _additivesCard(recipe),
              const SizedBox(height: 12),
              _fermentationCard(recipe),
              const SizedBox(height: 12),
              _notesCard(recipe),
              const SizedBox(height: 80), // breathing room above bottom bar
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                      onPressed: () => _editRecipe(context, recipe),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Create batch from recipe'),
                      onPressed: () => _createBatchFromRecipe(recipe),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
