// lib/pages/recipe_builder_page.dart
import 'dart:async';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

// Sections / Widgets
import 'package:fermentacraft/widgets/fermentable_tile.dart';
import 'package:fermentacraft/widgets/yeast_section.dart';
import 'package:fermentacraft/widgets/additives_section.dart';

// Controller + services
import 'package:fermentacraft/controllers/recipe_builder_controller.dart';
import 'package:fermentacraft/services/usda_service.dart';

// Utils & persistence
import 'package:fermentacraft/utils/calc_utils.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fermentacraft/utils/boxes.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/services/firestore_sync_service.dart';
import 'package:fermentacraft/pages/recipe_detail_page.dart';
import 'package:fermentacraft/widgets/fermentation_stages_editor.dart';

import '../models/enums.dart';

final logger = Logger();

class RecipeBuilderPage extends StatefulWidget {
  const RecipeBuilderPage({
    super.key,
    this.existingRecipe,
    this.recipeKey,
    this.isClone = false,
  });

  /// If provided, we treat this as “edit”. When `isClone == true`, we still make a new id.
  final RecipeModel? existingRecipe;
  final dynamic recipeKey; // Hive key (string/int) if editing an existing recipe
  final bool isClone;

  @override
  State<RecipeBuilderPage> createState() => _RecipeBuilderPageState();
}

class _CategoryChoice {
  final String label;
  final IconData icon;
  const _CategoryChoice(this.label, this.icon);
}

class _SugarSource {
  final String key;
  final String label;
  /// Fraction of the source that is fermentable sugar solids (0–1).
  final double solidsFraction;
  /// Density in g/mL if liquid or bulk density known; null if unknown.
  final double? densityGperMl;

  const _SugarSource({
    required this.key,
    required this.label,
    required this.solidsFraction,
    this.densityGperMl,
  });
}

/// Common sugar sources for cider/mead work. Values are typical approximations:
/// - Honey ~80% solids, ~1.42 g/mL
/// - Maple syrup ~66% solids, ~1.33 g/mL
/// - Corn syrup ~80% solids, ~1.38 g/mL
/// - Apple juice concentrate (70°Bx) ~70% solids, ~1.37 g/mL
const List<_SugarSource> _kSugarSources = [
  _SugarSource(key: 'sucrose', label: 'Table sugar (sucrose)', solidsFraction: 1.00, densityGperMl: null),
  _SugarSource(key: 'dextrose', label: 'Corn sugar (dextrose)', solidsFraction: 1.00, densityGperMl: null),
  _SugarSource(key: 'honey', label: 'Honey (~80% solids)', solidsFraction: 0.80, densityGperMl: 1.42),
  _SugarSource(key: 'maple', label: 'Maple syrup (~66% solids)', solidsFraction: 0.66, densityGperMl: 1.33),
  _SugarSource(key: 'cornsyrup', label: 'Corn syrup (~80% solids)', solidsFraction: 0.80, densityGperMl: 1.38),
  _SugarSource(key: 'ajc70', label: 'Apple juice concentrate (~70°Bx)', solidsFraction: 0.70, densityGperMl: 1.37),
];


class _RecipeBuilderPageState extends State<RecipeBuilderPage> {
  // Page fields
  final nameController = TextEditingController();
  final notesController = TextEditingController();
  final categoryController = TextEditingController();

  _CategoryChoice? _selectedCategory;
  _CategoryChoice? _userCategory;
  late final List<_CategoryChoice> _defaultCategories;
  late final _CategoryChoice _customSentinel;
  List<FermentationStage> _stages = [];


  // Gravity/ABV final
  double fg = 1.000;
  final fgController = TextEditingController(text: '1.000');
  double originalGravity = 1.000;
  double abv = 0.0;

  // Advanced tool fields
  bool showAdvanced = false;
  final measuredMustSGController = TextEditingController();
  final targetMustSGController = TextEditingController();
  final desiredAbvController = TextEditingController();
  final volumeController = TextEditingController(text: '5.0');
  bool userOverrodeMeasuredSG = false;
  bool userOverrodeAbv = false;
  bool userOverrodeBatchVolume = false;
  double? measuredMustSG;
  double? targetMustSG;
  double? sugarNeededGrams;
  double? waterToAddLiters;
  // Advanced tools – sugar source selection
_SugarSource _selectedSugar = _kSugarSources.first; // defaults to table sugar

// Derived convenience getters (calculated in UI from sugarNeededGrams)
double? get _selectedSourceGrams =>
    sugarNeededGrams != null ? (sugarNeededGrams! / _selectedSugar.solidsFraction) : null;

double? get _selectedSourceMl => (_selectedSourceGrams != null && _selectedSugar.densityGperMl != null)
    ? _selectedSourceGrams! / _selectedSugar.densityGperMl!
    : null;


  VolumeUnit selectedVolumeUnit = VolumeUnit.gallons;

  // USDA + Fermentables Controller
  late final RecipeBuilderController c;

  @override
  void initState() {
    super.initState();

    _defaultCategories = const [
      _CategoryChoice('Cider', Icons.local_drink),
      _CategoryChoice('Mead', Icons.hive_outlined),
      _CategoryChoice('Wine', Icons.wine_bar),
      _CategoryChoice('Fruit Wine', Icons.local_florist),
      _CategoryChoice('Seltzer', Icons.bubble_chart),
      _CategoryChoice('Other', Icons.category_outlined),
    ];
    _customSentinel = const _CategoryChoice('Custom…', Icons.add_circle_outline);

    c = RecipeBuilderController(usda: UsdaService());
    c.addListener(_onControllerChanged);

    // Seed from existingRecipe if provided
    final er = widget.existingRecipe;
    if (er != null) {
      nameController.text = er.name;
      notesController.text = er.notes;
      categoryController.text = er.categoryLabel;
      if (er.fg != null) {
        fg = er.fg!;
        fgController.text = fg.toStringAsFixed(3);
      }
      
      if (er.abv != null) abv = er.abv!;
        c.seedFromRecipe(er);
        } else {
          c.addFermentable();
                }
                _onControllerChanged();
if (er != null) {
  // Normalize whatever is stored into real FermentationStage objects
  _stages = (er.fermentationStages as List).map<FermentationStage>((s) {
    try {
      if (s is FermentationStage) return s;
      return FermentationStage.fromJson(Map<String, dynamic>.from(s as Map));
    } catch (_) {
      return FermentationStage(name: 'Stage', durationDays: 0, targetTempC: null);
    }
  }).toList();
} else {
  _stages = [];
}


      

    // Preselect category
    final initialLabel = categoryController.text.trim();
    final match = _defaultCategories.where(
      (c) => c.label.toLowerCase() == initialLabel.toLowerCase(),
    );
    if (initialLabel.isNotEmpty && match.isNotEmpty) {
      _selectedCategory = match.first;
    } else if (initialLabel.isNotEmpty) {
      _userCategory = _CategoryChoice(initialLabel, Icons.label_outline);
      _selectedCategory = _userCategory;
    }

    // ABV quick calculator listener (cleaned)
    desiredAbvController.addListener(() {
      final parsed = double.tryParse(desiredAbvController.text);
      if (parsed != null && parsed > 0 && parsed < 25) {
        setState(() {
          userOverrodeAbv = true;
          final requiredOG = (parsed / 131.25) + fg;
          targetMustSG = double.parse(requiredOG.toStringAsFixed(3));
          targetMustSGController.text = targetMustSG!.toStringAsFixed(3);
          _calculateSugarNeeded();
        });
      }
    });

    measuredMustSGController.addListener(() {
      final parsed = double.tryParse(measuredMustSGController.text);
      if (parsed != null) {
        setState(() {
          measuredMustSG = parsed;
          userOverrodeMeasuredSG = true;
          _calculateSugarNeeded();
        });
      }
    });
  }

  @override
  void dispose() {
    c.removeListener(_onControllerChanged);
    c.dispose();
    nameController.dispose();
    notesController.dispose();
    categoryController.dispose();
    fgController.dispose();
    measuredMustSGController.dispose();
    targetMustSGController.dispose();
    desiredAbvController.dispose();
    volumeController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ogRaw = measuredMustSG ?? c.stats.estimatedOg;
      final ogClamped = ogRaw.clamp(0.990, 1.300);
      final ogRounded = double.parse(ogClamped.toStringAsFixed(3));
      setState(() {
        originalGravity = ogRounded;
        abv = CalcUtils.abvFromSG(ogRounded, fg);
      });
    });
  }

  // —————————————————— Advanced (sugar / dilution) ——————————————————
  void _calculateSugarNeeded() {
    sugarNeededGrams = null;
    waterToAddLiters = null;

    if (measuredMustSG == null || targetMustSG == null) {
      setState(() {});
      return;
    }

    final sgDelta = targetMustSG! - measuredMustSG!;
    final batchVolume = double.tryParse(volumeController.text) ?? 0;
    final batchLiters = switch (selectedVolumeUnit) {
      VolumeUnit.gallons => batchVolume * 3.78541,
      VolumeUnit.ounces => batchVolume * 0.0295735,
      VolumeUnit.liters => batchVolume,
    };

    if (sgDelta > 0) {
      final s = CalcUtils.brixFromSg(targetMustSG!) - CalcUtils.brixFromSg(measuredMustSG!);
      final totalMassG = batchLiters * 1000.0;
      sugarNeededGrams = (s / 100.0) * totalMassG;
    } else if (sgDelta < 0) {
      final msg = CalcUtils.formatWaterToDilute(
        currentSg: measuredMustSG!,
        targetSg: targetMustSG!,
        currentVolumeL: batchLiters,
      );
      if (msg.endsWith(' L water')) {
        final val = double.tryParse(msg.replaceAll(' L water', '').trim());
        waterToAddLiters = val;
      }
    }
    setState(() {});
  }

  String _formatDilutionVolume(double liters) {
    if (liters <= 0) return "0";
    const litersPerGallon = 3.78541;
    const litersPerCup = 0.236588;
    const litersPerFlOz = 0.0295735;

    final gallons = (liters / litersPerGallon).floor();
    var remainder = liters % litersPerGallon;

    final cups = (remainder / litersPerCup).floor();
    remainder %= litersPerCup;

    final ounces = (remainder / litersPerFlOz);

    final parts = <String>[];
    if (gallons > 0) parts.add("$gallons gal");
    if (cups > 0) parts.add("$cups cup${cups > 1 ? 's' : ''}");
    if (ounces >= 0.1 || parts.isEmpty) parts.add("${ounces.toStringAsFixed(1)} fl oz");
    return parts.join(' ');
  }

  String _formatMlToKitchen(double ml) {
  if (ml <= 0) return '0 mL';
  // Use the same constants you already use elsewhere for consistency:
  const double mlPerCup = 236.588; // US cup
  const double mlPerFlOz = 29.5735;

  final cups = (ml / mlPerCup).floor();
  final remAfterCups = ml - cups * mlPerCup;

  final floz = remAfterCups / mlPerFlOz;

  final parts = <String>[];
  if (cups > 0) parts.add('$cups cup${cups > 1 ? 's' : ''}');
  if (floz >= 0.1) parts.add('${floz.toStringAsFixed(1)} fl oz');

  return parts.isEmpty ? '${ml.toStringAsFixed(0)} mL' : parts.join(' ');
}


  // —————————————————— Save ——————————————————

  /// Build a `RecipeModel` directly from controller + page state.
  RecipeModel _buildRecipeModel() {
    final now = DateTime.now();
    final editing = widget.existingRecipe != null && widget.isClone == false;

    final createdAt = editing ? widget.existingRecipe!.createdAt : now;
    final isArchived = editing ? widget.existingRecipe!.isArchived : false;

    // Decide id:
    //  - clone/new -> new id (let RecipeModel default uuid)
    //  - edit -> keep existing id
    final idForEdit = editing ? widget.existingRecipe!.id : null;

    final name = nameController.text.trim();
    final notes = notesController.text.trim();
    final category = (_selectedCategory?.label ?? '').trim();
    final finalCategory = category.isEmpty ? null : category;


    // Map controller lines to simple maps that your RecipeModel expects
    final fermentablesAsIngredientMaps = c.fermentables.map((f) {
      return <String, dynamic>{
        'id': f.id,
        'name': f.name,
        'type': f.type.name,
        'brix': f.brix,
        'density': f.density,
        'weightG': f.weightG,
        'volumeMl': f.volumeMl,
        'syncWeightVolume': f.syncWeightVolume,
        'usdaBacked': f.usdaBacked,
        'usdaFdcId': f.usdaFdcId,
      };
    }).toList();

    final yeastsMaps = c.yeasts.map((y) {
      return <String, dynamic>{
        'id': y.id,
        'name': y.name,
        'form': y.form.name,
        'quantity': y.quantity,
        'unit': y.unit.name,
        'notes': y.notes,
      };
    }).toList();

    final additivesMaps = c.additives.map((a) {
      return <String, dynamic>{
        'id': a.id,
        'name': a.name,
        'quantity': a.quantity,
        'unit': a.unit.name,
        'when': a.when,
        'notes': a.notes,
      };
    }).toList();

    // Stats (use measuredMustSG if present)
    final ogVal = double.parse((measuredMustSG ?? c.stats.estimatedOg).toStringAsFixed(3));
    final fgVal = double.parse(fg.toStringAsFixed(3));
    final abvVal = double.parse(CalcUtils.abvFromSG(ogVal, fgVal).toStringAsFixed(2));

final model = RecipeModel(
  id: idForEdit,
  name: name.isEmpty ? 'Untitled' : name,
  createdAt: createdAt,
  category: finalCategory,
  og: ogVal,
  fg: fgVal,
  abv: abvVal,
  ingredients: fermentablesAsIngredientMaps,
  additives: additivesMaps,
  yeast: yeastsMaps,
  notes: notes,
  lastOpened: now,
  batchVolume: null,
  plannedOg: null,
  plannedAbv: null,
  isArchived: isArchived,
  // ✅ add this line (use JSON so Hive/serialization stays simple)
fermentationStages: _stages, // ✅ List<FermentationStage>
);

    // Normalize for any future migrations/dirty data
    model.normalizeInPlace();
    return model;
  }

  Future<void> _saveRecipe() async {
    final recipes = Hive.box<RecipeModel>(Boxes.recipes);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final model = _buildRecipeModel();
      final newKey = model.id.trim();
      if (newKey.isEmpty) {
        throw StateError('Recipe id missing');
      }

      if (widget.existingRecipe != null && widget.isClone == false) {
        final oldKeyRaw = (widget.recipeKey ?? widget.existingRecipe!.key);
        final oldKey = oldKeyRaw?.toString().trim();
        if (oldKey != null && oldKey.isNotEmpty && oldKey != newKey) {
          await recipes.put(newKey, model);
          await recipes.delete(oldKey);
        } else {
          await recipes.put(newKey, model);
        }
      } else {
        await recipes.put(newKey, model);
      }

      await FirestoreSyncService.instance.forceSync();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recipe saved'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );

      // Navigate to the detail page of the saved recipe.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RecipeDetailPage(
            recipeKey: newKey,
            recipe: model,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Failed to save: $e'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }



  // —————————————————— Build ——————————————————
  @override
  Widget build(BuildContext context) {
    // Compute once per build to avoid rebuilding/transient model twice in the Preview card

    return ChangeNotifierProvider.value(
      value: c,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.existingRecipe == null || widget.isClone ? "Recipe Builder" : "Edit Recipe"),
          actions: [
            IconButton(
              onPressed: _saveRecipe,
              icon: const Icon(Icons.save),
              tooltip: 'Save',
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            c.recalc();
            await Future<void>.delayed(const Duration(milliseconds: 1));
          },
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // ——— Recipe Info ———
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(children: [
                        const Icon(Icons.receipt_long),
                        const SizedBox(width: 8),
                        Text('Recipe Info', style: Theme.of(context).textTheme.titleMedium),
                      ]),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Recipe Name',
                          hintText: 'e.g., Dry Traditional Mead',
                          prefixIcon: Icon(Icons.edit),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 8),
                      _CategoryField(
                        selected: _selectedCategory,
                        userCategory: _userCategory,
                        defaults: _defaultCategories,
                        sentinel: _customSentinel,
                        onPick: (choice, maybeCustom) {
                          setState(() {
                            _selectedCategory = choice;
                            _userCategory = maybeCustom ?? _userCategory;
                            categoryController.text = choice.label;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: notesController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Notes'),
                      ),
                    ],
                  ),
                ),
              ),

              // ——— Must Stats ———
              Consumer<RecipeBuilderController>(
                builder: (_, c, __) {
                  final tgtText = targetMustSGController.text.trim();
                  final tgt = double.tryParse(tgtText);
                  final useOg = measuredMustSG ?? c.stats.estimatedOg;

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                       Row(children: [
                          const Icon(Icons.science),
                          const SizedBox(width: 8),
                          Text('Must Stats', style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          DropdownButton<VolumeUiUnit>(
                            value: c.statsVolumeUnit,
                            underline: const SizedBox.shrink(),
                            items: VolumeUiUnit.values
                                .map((u) => DropdownMenuItem(value: u, child: Text(u.label)))
                                .toList(),
                            onChanged: (u) => u == null ? null : c.setStatsVolumeUnit(u),
                          ),
                          IconButton(onPressed: c.recalc, icon: const Icon(Icons.refresh)),
                        ]),

                        const Divider(),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            _kv(
                              'Estimated OG',
                              (useOg).toStringAsFixed(3),
                              trailing: _badgeForOg(useOg, tgt),
                            ),
                            _kv('Brix', c.stats.brix.toStringAsFixed(1)),
_kv(
  'Total volume',
  '${c.statsVolumeUnit.fromMl(c.stats.totalVolumeMl).toStringAsFixed(3)} ${c.statsVolumeUnit.label}',
),                            _kv('Total sugar', '${c.stats.totalSugarG.toStringAsFixed(0)} g'),
                            _kv('Est. ABV', '${abv.toStringAsFixed(1)}%'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: measuredMustSGController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Measured OG (override, optional)',
                            helperText: 'If provided, stats will use this instead of estimated OG.',
                          ),
                          onChanged: (_) {
                            userOverrodeMeasuredSG = true;
                            _onControllerChanged();
                          },
                        ),
                      ]),
                    ),
                  );
                },
              ),

              // ——— Fermentables (USDA) ———
              Row(children: [
                const Icon(Icons.local_fire_department_outlined),
                const SizedBox(width: 8),
                Text('Fermentables', style: Theme.of(context).textTheme.titleMedium),
              ]),
              const SizedBox(height: 12),
              Consumer<RecipeBuilderController>(
                builder: (_, c, __) => Column(
                  children: [
                    for (int i = 0; i < c.fermentables.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FermentableTile(
                          key: ValueKey(c.fermentables[i].id),
                          index: i,
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: c.addFermentable,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Fermentable'),
                      ),
                    ),
                  ],
                ),
              ),

              // ——— Yeast ———
              const SizedBox(height: 16),
              const YeastSection(),

              // ——— Additives ———
              const SizedBox(height: 16),
              const AdditivesSection(),

              const SizedBox(height: 16),
              FermentationStagesEditor(
              stages: _stages,
              onChanged: (next) => setState(() => _stages = next),
            ),


              // ——— Gravity & ABV (final) ———
              _SectionTitle("Gravity & ABV"),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.percent),
                      title: const Text("Estimated ABV"),
                      subtitle: Text(
                        "${abv.toStringAsFixed(2)}% (from OG: ${originalGravity.toStringAsFixed(3)})",
                      ),
                    ),
                    TextFormField(
                      controller: fgController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: "Final Gravity"),
                      onChanged: (val) {
                        final parsed = double.tryParse(val);
                        if (parsed != null && parsed >= 0.990 && parsed <= 1.200) {
                          setState(() {
                            fg = double.parse(parsed.toStringAsFixed(3));
                            _onControllerChanged();
                          });
                        }
                      },
                      onFieldSubmitted: (_) {
                        final parsed = double.tryParse(fgController.text);
                        if (parsed != null) {
                          final clamped = parsed.clamp(0.990, 1.200);
                          setState(() {
                            fg = double.parse(clamped.toStringAsFixed(3));
                            fgController.text = fg.toStringAsFixed(3);
                            _onControllerChanged();
                          });
                        }
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ]),
                ),
              ),

              // ——— Advanced Tools (dilute / raise) ———
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Show Advanced Tools"),
                    Switch(
                      value: showAdvanced,
                      onChanged: (val) => setState(() => showAdvanced = val),
                    ),
                  ],
                ),
              ),
              if (showAdvanced)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("Gravity Adjustment", style: Theme.of(context).textTheme.titleLarge),
                      // (Inside the Advanced Tools Card > Column children)
const SizedBox(height: 8),
Row(
  children: [
    Expanded(
      child: DropdownButtonFormField<_SugarSource>(
        value: _selectedSugar,
        decoration: const InputDecoration(
          labelText: 'Sugar Source',
          helperText: 'Choose what you will add to raise OG',
        ),
        items: _kSugarSources
            .map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s.label),
                ))
            .toList(),
        onChanged: (s) {
          if (s == null) return;
          setState(() => _selectedSugar = s);
          // No need to recalc sugarNeededGrams; it's solids.
          // Conversion to source grams/mL happens via getters.
        },
      ),
    ),
  ],
),
const SizedBox(height: 12),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: volumeController,
                            decoration: const InputDecoration(labelText: "Batch Volume"),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) {
                              setState(() {
                                userOverrodeBatchVolume = true;
                                _calculateSugarNeeded();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<VolumeUnit>(
                          value: selectedVolumeUnit,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                selectedVolumeUnit = val;
                                _calculateSugarNeeded();
                              });
                            }
                          },
                          items: VolumeUnit.values
                              .map((unit) => DropdownMenuItem(value: unit, child: Text(unit.label)))
                              .toList(),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: measuredMustSGController,
                        decoration: const InputDecoration(labelText: "Measured Initial SG (Must)"),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: targetMustSGController,
                        decoration: const InputDecoration(labelText: "Target Initial SG"),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null) {
                            setState(() {
                              userOverrodeAbv = false;
                              targetMustSG = parsed;
                              _calculateSugarNeeded();
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: desiredAbvController,
                        decoration: const InputDecoration(labelText: "Desired ABV (%)"),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      if (sugarNeededGrams != null) ...[
  ListTile(
    title: Text("Add as ${_selectedSugar.label}"),
    subtitle: Builder(
      builder: (_) {
        final grams = _selectedSourceGrams;
        final ml = _selectedSourceMl;
        final parts = <String>[];
        if (grams != null) parts.add("${grams.toStringAsFixed(1)} g");
        if (ml != null) {
          parts.add("${ml.toStringAsFixed(0)} mL (${_formatMlToKitchen(ml)})");
        }
        return Text(parts.isEmpty ? '—' : parts.join("  •  "));
      },
    ),
  ),
],

                      if (waterToAddLiters != null && waterToAddLiters! > 0)
                        ListTile(
                          title: const Text("Dilution Needed"),
                          subtitle: Text(_formatDilutionVolume(waterToAddLiters!)),
                        ),
                    ]),
                  ),
                ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  // —————————————————— Small helpers ——————————————————
  Widget _kv(String k, String v, {Widget? trailing}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      );

  Widget _badgeForOg(double? og, double? target) {
    if (og == null || target == null) return const SizedBox.shrink();
    final diff = (og - target).abs();
    MaterialColor bg;
    String label;
    if (diff < 0.003) {
      bg = Colors.green;
      label = 'on target';
    } else if (diff < 0.010) {
      bg = Colors.orange;
      label = 'close';
    } else {
      bg = Colors.red;
      label = 'off';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: bg.shade700, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// Keep consistent with earlier enum in your code base
enum VolumeUnit { gallons, liters, ounces }

extension VolumeUnitLabel on VolumeUnit {
  String get label => switch (this) {
        VolumeUnit.gallons => 'gal',
        VolumeUnit.liters => 'L',
        VolumeUnit.ounces => 'fl oz',
      };
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _CategoryField extends StatelessWidget {
  final _CategoryChoice? selected;
  final _CategoryChoice? userCategory;
  final List<_CategoryChoice> defaults;
  final _CategoryChoice sentinel;
  final void Function(_CategoryChoice choice, _CategoryChoice? created) onPick;

  const _CategoryField({
    required this.selected,
    required this.userCategory,
    required this.defaults,
    required this.sentinel,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<_CategoryChoice>(
      value: selected,
      items: [
        ...defaults,
        if (userCategory != null) userCategory!,
        sentinel,
      ].map((c) {
        return DropdownMenuItem(
          value: c,
          child: Row(children: [Icon(c.icon, size: 20), const SizedBox(width: 10), Text(c.label)]),
        );
      }).toList(),
      selectedItemBuilder: (_) => [
        ...defaults,
        if (userCategory != null) userCategory!,
        sentinel,
      ].map((c) => Text(c.label)).toList(),

      decoration: InputDecoration(
        labelText: 'Category',
        prefixIcon: Icon(selected?.icon ?? Icons.category_outlined),
        border: const OutlineInputBorder(),
      ),
      hint: const Text('Select a category'),
      onChanged: (choice) async {
        if (choice == null) return;
        if (identical(choice, sentinel)) {
          final created = await _openCustomCategoryDialog(context);
          if (created != null) onPick(created, created);
          return;
        }
        onPick(choice, null);
      },
    );
  }

  Future<_CategoryChoice?> _openCustomCategoryDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final iconChoices = <IconData>[
      Icons.wine_bar,
      Icons.hive_outlined,
      Icons.local_drink,
      Icons.local_florist,
      Icons.bubble_chart,
      Icons.category_outlined,
      Icons.local_bar,
      Icons.emoji_food_beverage,
      Icons.spa,
      Icons.grass,
    ];
    IconData picked = iconChoices.first;

    return showDialog<_CategoryChoice>(
      context: context,
      builder: (ctx) {
        int idx = 0;
        return StatefulBuilder(
          builder: (ctx, setSB) => AlertDialog(
            title: const Text('Custom Category'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Category name')),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text('Icon', style: Theme.of(ctx).textTheme.titleSmall)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(iconChoices.length, (i) {
                    final icon = iconChoices[i];
                    final sel = i == idx;
                    return ChoiceChip(
                      label: Icon(icon, size: 18),
                      selected: sel,
                      onSelected: (_) => setSB(() {
                        idx = i;
                        picked = iconChoices[idx];
                      }),
                    );
                  }),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final label = nameCtrl.text.trim();
                  if (label.isEmpty) return;
                  Navigator.pop(ctx, _CategoryChoice(label, picked));
                },
                child: const Text('Use'),
              ),
            ],
          ),
        );
      },
    );
  }
}
