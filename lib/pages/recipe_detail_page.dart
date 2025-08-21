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

// Optional helper: human-friendly fermentable lines if you already have it

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
  // UI state for stats volume unit (default to gallons)
  VolumeUiUnit _statsUnit = VolumeUiUnit.gallons;

  // ---------- lightweight, local copies of controller math ----------
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
      final updated = widget.recipe..lastOpened = DateTime.now();
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

    // Inputs (nullable)
    final double? brix = (m['brix'] as num?)?.toDouble();
    final double? density = (m['density'] as num?)?.toDouble();
    final double? weightG = (m['weightG'] as num?)?.toDouble();
    final double? volumeMl = (m['volumeMl'] as num?)?.toDouble();

    // Normalize density to g/mL
    final double dens = _normDensity(
      density ?? type.defaultDensity,
      fallback: type.defaultDensity,
    );

    // Use line volume directly if present, else derive from weight / density
    double lineMl = 0.0;
    if (volumeMl != null && volumeMl > 0) {
      lineMl = volumeMl;
    } else if (weightG != null && weightG > 0) {
      lineMl = weightG / dens; // g / (g/mL) => mL
    }

    // Sugar fraction (brix as fraction)
    final double b = (brix ?? type.defaultBrix) / 100.0;

    // Sugar contribution: if weight given, b * weight; else b * (volume * density)
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

  // Map all rows to batch schema
  final clonedIngredients = recipe.ingredients
      .map<Map<String, dynamic>>((e) => recipeIngredientToBatch(sm(e)))
      .toList();

  final clonedAdditives = recipe.additives
      .map<Map<String, dynamic>>((e) => recipeAdditiveToBatch(sm(e)))
      .toList();

  final clonedYeast = recipe.yeast
      .map<Map<String, dynamic>>((e) => recipeYeastToBatch(sm(e)))
      .toList();

  // Clone stages
  final List<FermentationStage> clonedStages =
      recipe.fermentationStages.map<FermentationStage>((dynamic s) {
    if (s is FermentationStage) return FermentationStage.fromJson(s.toJson());
    return FermentationStage.fromJson(Map<String, dynamic>.from(s as Map));
  }).toList();

  // Derive overall stats to seed batch targets
  final stats = _deriveStats(recipe); // volumeMl + sg

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
    // Seed Planning targets so the card isn't blank
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



void _deleteRecipe(BuildContext context) async {
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

  // Grab the attached recipe (if we navigated in with a key)
  final RecipeModel? current =
      (widget.recipeKey != null) ? box.get(widget.recipeKey) : null;

  final String? id = current?.id;
  if (id != null && id.trim().isNotEmpty) {
    // Tombstone remotely to prevent re-sync resurrection
    await FirestoreSyncService.instance.markDeleted(
      collection: Boxes.recipes,
      id: id,
    );
  }

  // Resolve the *actual* Hive key we should delete
  dynamic keyToDelete = widget.recipeKey;
  if (current != null && current.key != null) {
    keyToDelete = current.key;
  } else if (id != null && id.trim().isNotEmpty) {
    // Fallback scan by id
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

if (id != null && id.trim().isNotEmpty) {
  idsToTombstone.add(id.trim());
}
final keyStr = widget.recipeKey?.toString().trim();
if (keyStr != null && keyStr.isNotEmpty) {
  idsToTombstone.add(keyStr);
}
final objKeyStr = (current?.key)?.toString().trim();
if (objKeyStr != null && objKeyStr.isNotEmpty) {
  idsToTombstone.add(objKeyStr);
}

for (final rid in idsToTombstone) {
  await FirestoreSyncService.instance.markDeleted(
    collection: Boxes.recipes,
    id: rid,
  );
}

  await box.delete(keyToDelete);
await FirestoreSyncService.instance.forceSync();

  // Leave the detail page; no need to construct a page with null
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    // If this page is root for some reason, go back to list cleanly
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const RecipeListPage()),
    );
  }
}


  // ---------- sections ----------
  Widget _heroCard(RecipeModel recipe) {
    final created = DateFormat.yMMMd().format(recipe.createdAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            const Icon(Icons.receipt_long),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 12, runSpacing: 6, children: [
                  _chip('Category', recipe.categoryLabel),
                  _chip('Created', created),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsCard(RecipeModel recipe) {
    final d = _deriveStats(recipe);
    String fmt(num? v, {int frac = 3}) => (v == null) ? '—' : v.toStringAsFixed(frac);

    final estVol = _statsUnit.fromMl(d.volumeMl);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.science),
            const SizedBox(width: 8),
            Text('Must Stats', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            DropdownButton<VolumeUiUnit>(
              value: _statsUnit,
              underline: const SizedBox.shrink(),
              items: VolumeUiUnit.values.map((u) => DropdownMenuItem(value: u, child: Text(u.label))).toList(),
              onChanged: (u) => setState(() => _statsUnit = u ?? _statsUnit),
            ),
          ]),
          const Divider(),
          Wrap(spacing: 16, runSpacing: 8, children: [
            _stat('Est. OG', d.sg.toStringAsFixed(3)),
            _stat('Est. Brix', d.brix.toStringAsFixed(1)),
            _stat('Total Volume', '${estVol.toStringAsFixed(2)} ${_statsUnit.label}'),
            _stat('Total Sugar', '${d.sugarG.toStringAsFixed(0)} g'),
          ]),
          const SizedBox(height: 10),
          if (recipe.og != null || recipe.fg != null || recipe.abv != null) ...[
            Text('Saved Targets', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 16, runSpacing: 8, children: [
              _stat('OG', fmt(recipe.og, frac: 3)),
              _stat('FG', fmt(recipe.fg, frac: 3)),
              _stat('ABV', recipe.abv == null ? '—' : '${fmt(recipe.abv, frac: 1)}%'),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _fermentablesCard(RecipeModel recipe) {
    final lines = recipe.ingredients;
    if (lines.isEmpty) return const SizedBox.shrink();

    // prefer rich tile; fall back to extension strings if needed
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
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(children: [
          const Icon(Icons.local_fire_department_outlined),
          const SizedBox(width: 8),
          Text('Fermentables', style: Theme.of(context).textTheme.titleLarge),
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
          );
        }).toList(),
      ),
    );
  }

  Widget _yeastCard(RecipeModel recipe) {
    if (recipe.yeast.isEmpty) return const SizedBox.shrink();

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(children: [
          const Icon(Icons.biotech_outlined),
          const SizedBox(width: 8),
          Text('Yeast', style: Theme.of(context).textTheme.titleLarge),
        ]),
        children: recipe.yeast.map((raw) {
          final y = safeMap(raw);
          final name = (y['name'] ?? 'Unnamed').toString();
          final form = (y['form'] ?? '').toString();
          final qty = (y['quantity'] as num?)?.toDouble();
          final unit = (y['unit'] ?? '').toString();

          final parts = <String>[];
          if (form.isNotEmpty) parts.add(form);
          if (qty != null) parts.add(unit.isNotEmpty ? '${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} $unit' : '$qty');

          return ListTile(title: Text(name), subtitle: Text(parts.isEmpty ? '—' : parts.join(' • ')));
        }).toList(),
      ),
    );
  }

  Widget _additivesCard(RecipeModel recipe) {
    if (recipe.additives.isEmpty) return const SizedBox.shrink();

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(children: [
          const Icon(Icons.science_outlined),
          const SizedBox(width: 8),
          Text('Additives', style: Theme.of(context).textTheme.titleLarge),
        ]),
        children: recipe.additives.map((raw) {
          final a = safeMap(raw);
          final name = (a['name'] ?? 'Unnamed').toString();
          final qty = (a['quantity'] as num?)?.toDouble();
          final unit = (a['unit'] ?? '').toString();
          final when = (a['when'] ?? '').toString();
          final notes = (a['notes'] ?? '').toString();

          final parts = <String>[];
          if (qty != null) parts.add(unit.isNotEmpty ? '${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} $unit' : '$qty');
          if (when.isNotEmpty) parts.add(when);
          if (notes.isNotEmpty) parts.add(notes);

          return ListTile(title: Text(name), subtitle: Text(parts.isEmpty ? '—' : parts.join(' • ')));
        }).toList(),
      ),
    );
  }

  Widget _fermentationCard(RecipeModel recipe) {
    final settings = context.watch<SettingsModel>();
    if (recipe.fermentationStages.isEmpty) return const SizedBox.shrink();

    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(children: [
          const Icon(Icons.timeline),
          const SizedBox(width: 8),
          Text('Fermentation Profile', style: Theme.of(context).textTheme.titleLarge),
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
          );
        }).toList(),
      ),
    );
  }

  Widget _notesCard(RecipeModel recipe) {
    if (recipe.notes.trim().isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Notes', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(recipe.notes),
        ]),
      ),
    );
  }

  // ---------- tiny UI helpers ----------
  Widget _stat(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
    ]);
  }

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
            title: Text(recipe.name),
            actions: [
              IconButton(onPressed: () => _editRecipe(context, recipe), icon: const Icon(Icons.edit), tooltip: 'Edit'),
              IconButton(
                onPressed: atRecipeLimit
                    ? () => _upsell(context, 'Free limit reached ($freeLimit recipes). Upgrade to copy.')
                    : () => _cloneRecipe(context, recipe),
                icon: const Icon(Icons.copy),
                tooltip: atRecipeLimit ? 'Upgrade to copy' : 'Copy recipe',
              ),
              IconButton(onPressed: () => _deleteRecipe(context), icon: const Icon(Icons.delete), tooltip: 'Delete'),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _heroCard(recipe),
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
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Create batch from recipe'),
                  onPressed: () => _createBatchFromRecipe(recipe),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
