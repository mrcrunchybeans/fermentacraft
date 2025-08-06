import 'package:flutter/material.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/models/tag.dart';
// import 'package:fermentacraft/utils/temp_display.dart'; // REMOVED: Duplicate import
import 'package:fermentacraft/utils/unit_conversion.dart';
import 'package:logger/logger.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart'; // ADDED: For context.watch
import 'models/ingredient.dart';
import 'models/inventory_item.dart';
import 'models/settings_model.dart'; // ADDED: For SettingsModel
import 'utils/sugar_gravity_data.dart';
import 'widgets/add_additive_dialog.dart';
import 'widgets/add_fermentation_stage_dialog.dart';
import 'widgets/add_ingredient_dialog.dart';
import 'utils/utils.dart';
import 'models/recipe_model.dart';
import 'recipe_list_page.dart';
import 'widgets/tag_picker_dialog.dart';
import 'widgets/add_yeast_dialog.dart';
import 'dart:async';
import 'models/purchase_transaction.dart';
import 'models/unit_type.dart';
import 'utils/temp_display.dart';

final logger = Logger();

double calculateAbv(double og, double fg) {
  return (og - fg) * 131.25;
}

class RecipeBuilderPage extends StatefulWidget {
  const RecipeBuilderPage({
    super.key,
    this.existingRecipe,
    this.recipeKey,
    this.isClone = false,
  });

  final RecipeModel? existingRecipe;
  final bool isClone;
  final dynamic recipeKey;

  @override
  State<RecipeBuilderPage> createState() => _RecipeBuilderPageState();
}

class _RecipeBuilderPageState extends State<RecipeBuilderPage> {
  double abv = 0.0;
  List<Map<dynamic, dynamic>> additives = [];
  double? batchVolumeGallons;
  double? desiredAbv;
  final TextEditingController desiredAbvController = TextEditingController();
  List<Map<dynamic, dynamic>> ingredients = [];
  List<FermentationStage> fermentationStages = [];
  double fg = 1.010;
  double? measuredMustSG;
  final TextEditingController measuredMustSGController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  TextEditingController notesController = TextEditingController();
  double? og;
  double originalGravity = 1.000;
  AbvSource selectedAbvSource = AbvSource.measured;
  SugarType selectedSugarType = sugarTypes.first;
  VolumeUnit selectedVolumeUnit = VolumeUnit.gallons;
  Timer? sgToAbvDebounce;
  bool showAdvanced = false;
  double? sugarNeededGrams;
  List<Tag> tags = [];
  double? targetMustSG;
  final TextEditingController targetMustSGController = TextEditingController();
  bool useAdjustedOG = false;
  bool userOverrodeAbv = false;
  bool userOverrodeMeasuredSG = false;
  bool userOverrodeBatchVolume = false;
  TextEditingController volumeController = TextEditingController(text: "5.0");
  double? waterToAddLiters;
  double? weightedAverageOG;
  List<Map<dynamic, dynamic>> yeast = [];
  // REMOVED: Cannot initialize here using 'context'
  // final settings = context.watch<SettingsModel>();


  @override
  void initState() {
    super.initState();
    desiredAbvController.addListener(() {
      final input = desiredAbvController.text;
      final parsed = double.tryParse(input);

      if (parsed != null && parsed > 0 && parsed < 25) {
        setState(() {
          userOverrodeAbv = true;
          final requiredOG = (parsed / 131.25) + fg;
          targetMustSG = double.parse(requiredOG.toStringAsFixed(3));
          targetMustSGController.text = targetMustSG!.toStringAsFixed(3);
          _calculateSugarNeeded();
          if (useAdjustedOG) calculateStats();
        });
      }
    });

    measuredMustSGController.addListener(() {
      final input = measuredMustSGController.text;
      final parsed = double.tryParse(input);
      if (parsed != null) {
        setState(() {
          measuredMustSG = parsed;
          userOverrodeMeasuredSG = true;
          _calculateSugarNeeded();
          calculateStats();
        });
      }
    });

    if (widget.existingRecipe != null) {
      final recipe = widget.existingRecipe!;
      nameController.text = recipe.name;
      notesController.text = recipe.notes;
      additives = List<Map<dynamic, dynamic>>.from(recipe.additives);
      ingredients = List<Map<dynamic, dynamic>>.from(recipe.ingredients);
      fermentationStages = List<FermentationStage>.from(recipe.fermentationStages);
      og = recipe.og;
      fg = recipe.fg!;
      abv = recipe.abv!;
      yeast = List<Map<dynamic, dynamic>>.from(recipe.yeast);
      tags = List<Tag>.from(recipe.tags);
    }

    calculateStats();
    if (measuredMustSG == null && weightedAverageOG != null) {
      measuredMustSG = weightedAverageOG;
      measuredMustSGController.text = measuredMustSG!.toStringAsFixed(3);
    }
  }

  void _updateMeasuredMustSGIfNotOverridden() {
    if (!userOverrodeMeasuredSG && weightedAverageOG != null) {
      measuredMustSG = weightedAverageOG;
      measuredMustSGController.text = measuredMustSG!.toStringAsFixed(3);
    }
  }

  void calculateStats() {
    double totalVolumeGallons = 0;
    double weightedOGSum = 0;

    for (final f in ingredients) {
      final og = f['og'];
      final amount = f['amount'];
      final unit = f['unit'];

      if (og == null || amount == null || unit == null) continue;

      final amountValue = double.tryParse(amount.toString()) ?? 0;
      double amountInGallons;

      switch (unit.toString().toLowerCase()) {
        case 'oz':
        case 'ounces':
          amountInGallons = amountValue / 128.0;
          break;
        case 'liters':
        case 'l':
          amountInGallons = amountValue / 3.78541;
          break;
        case 'ml':
          amountInGallons = amountValue / 3785.41;
          break;
        case 'gallons':
        case 'gallon':
        default:
          amountInGallons = amountValue;
      }

      totalVolumeGallons += amountInGallons;
      weightedOGSum += (og as double) * amountInGallons;
    }

    weightedAverageOG =
        totalVolumeGallons > 0 ? weightedOGSum / totalVolumeGallons : null;
    _updateMeasuredMustSGIfNotOverridden();
    batchVolumeGallons = totalVolumeGallons;

    if (batchVolumeGallons != null && !userOverrodeBatchVolume) {
      final double value = selectedVolumeUnit == VolumeUnit.ounces
          ? batchVolumeGallons! * 128.0
          : selectedVolumeUnit == VolumeUnit.liters
              ? batchVolumeGallons! * 3.78541
              : batchVolumeGallons!;
      volumeController.text = value.toStringAsFixed(2);
    }

    originalGravity = !showAdvanced
        ? (weightedAverageOG ?? 1.000)
        : (useAdjustedOG
            ? (targetMustSG ?? weightedAverageOG ?? 1.000)
            : (measuredMustSG ?? weightedAverageOG ?? 1.000));

    abv = calculateAbv(originalGravity, fg);

    if (!userOverrodeAbv) {
      desiredAbv = abv;
      desiredAbvController.text = abv.toStringAsFixed(2);
    }
  }

  void addIngredient(Map<String, dynamic> ingredientMap) {
    final cleanIngredient = Map<String, dynamic>.from(ingredientMap);
    cleanIngredient.forEach((key, value) {
      if (value is DateTime) {
        cleanIngredient[key] = value.toIso8601String();
      }
    });

    setState(() {
      ingredients.add(cleanIngredient);
    });
    calculateStats();
    _updateMeasuredMustSGIfNotOverridden();
  }

  void editIngredient(int index) async {
    final existing = ingredients[index];
    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AddIngredientDialog(
        unitType: inferUnitType(existing['unit'] ?? 'g'),
        existing: Map<String, dynamic>.from(existing),
        onAddToRecipe: (updated) {
          setState(() {
            ingredients[index] = updated;
          });
          calculateStats();
        },
      ),
    );
  }

  void editAdditive(int index) async {
    final existing = additives[index];
    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AddAdditiveDialog(
        mustPH: 3.4,
        volume: 5.0,
        existing: Map<String, dynamic>.from(existing),
        onAdd: (updated) {
          setState(() {
            additives[index] = updated;
          });
          calculateStats();
        },
      ),
    );
  }

  void addYeast(Map<String, dynamic> yeastMap) {
    final cleanYeast = Map<String, dynamic>.from(yeastMap);
    cleanYeast.forEach((key, value) {
      if (value is DateTime) {
        cleanYeast[key] = value.toIso8601String();
      }
    });

    setState(() {
      yeast = [cleanYeast];
    });
  }

  void editYeast() async {
    if (yeast.isEmpty) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => AddYeastDialog(
        onAdd: addYeast,
        existing: Map<String, dynamic>.from(yeast.first),
        onAddToInventory: (yeastData) async {
          final purchase = PurchaseTransaction(
            amount: (yeastData['amount'] as num?)?.toDouble() ?? 0.0,
            cost: (yeastData['cost'] as num?)?.toDouble() ?? 0.0,
            date: yeastData['purchaseDate'] as DateTime? ?? DateTime.now(),
            expirationDate: yeastData['expirationDate'] as DateTime?,
          );
          // FIX: Use the new InventoryItem constructor pattern
          final item = InventoryItem(
            name: yeastData['name'] as String? ?? 'Unnamed',
            unit: yeastData['unit'] as String? ?? 'packets',
            unitType: inferUnitType(yeastData['unit'] as String? ?? 'packets'),
            category: 'Yeast',
            purchaseHistory: [purchase],
          );
          final box = Hive.box<InventoryItem>('inventory');
          await box.add(item);
          if (!mounted) return;
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text("Added '${item.name}' to Inventory")),
          );
          addYeast(yeastData);
        },
      ),
    );
  }

  void addAdditive(Map<String, dynamic> additiveMap) {
    final cleanAdditive = Map<String, dynamic>.from(additiveMap);
    cleanAdditive.forEach((key, value) {
      if (value is DateTime) {
        cleanAdditive[key] = value.toIso8601String();
      }
    });

    setState(() {
      additives.add(cleanAdditive);
    });
  }

  void saveRecipe() {
    final recipeName = nameController.text.trim();
    if (recipeName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a recipe name.")),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirm Save"),
        content: Text("Save recipe as \"$recipeName\"?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newRecipe = RecipeModel(
                name: recipeName,
                tags: tags,
                createdAt: DateTime.now(),
                fg: fg,
                abv: abv,
                additives: additives,
                og: originalGravity,
                ingredients: ingredients,
                yeast: yeast,
                fermentationStages: fermentationStages,
                notes: notesController.text.trim(),
              );
              final box = Hive.box<RecipeModel>('recipes');
              if (widget.existingRecipe != null && !widget.isClone && widget.recipeKey != null) {
                await box.put(widget.recipeKey, newRecipe);
              } else {
                await box.add(newRecipe);
              }
              if (!mounted) return;
              Navigator.of(context).pop(); 
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const RecipeListPage()),
                (route) => route.isFirst,
              );
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _calculateSugarNeeded() {
    sugarNeededGrams = null;
    waterToAddLiters = null;

    if (measuredMustSG == null || targetMustSG == null) {
      setState(() {});
      return;
    }

    final sgDelta = targetMustSG! - measuredMustSG!;
    final batchVolume = double.tryParse(volumeController.text) ?? 0;
    final batchLiters = selectedVolumeUnit == VolumeUnit.gallons
        ? batchVolume * 3.78541
        : selectedVolumeUnit == VolumeUnit.ounces
            ? batchVolume * 0.0295735
            : selectedVolumeUnit == VolumeUnit.liters
                ? batchVolume
                : batchVolume;

    if (sgDelta > 0) {
      sugarNeededGrams =
          sgDelta / selectedSugarType.sgPerGramPerLiter * batchLiters;
    } else if (sgDelta < 0) {
      final dilutionRatio = measuredMustSG! / targetMustSG!;
      final newTotalVolume = batchLiters * dilutionRatio;
      waterToAddLiters = newTotalVolume - batchLiters;
    }
    setState(() {});
  }

  String _formatDilutionVolume(double liters) {
    if (liters <= 0) return "0";

    const double litersPerGallon = 3.78541;
    const double litersPerCup = 0.236588;
    const double litersPerFlOz = 0.0295735;

    final gallons = (liters / litersPerGallon).floor();
    var remainder = liters % litersPerGallon;

    final cups = (remainder / litersPerCup).floor();
    remainder %= litersPerCup;

    final ounces = (remainder / litersPerFlOz);

    List<String> parts = [];
    if (gallons > 0) parts.add("$gallons gal");
    if (cups > 0) parts.add("$cups cup${cups > 1 ? 's' : ''}");

    if (ounces >= 0.1 || parts.isEmpty) {
      parts.add("${ounces.toStringAsFixed(1)} fl oz");
    }

    return parts.join(' ');
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }

  Widget _buildIngredientsSummary() {
    if (ingredients.length <= 1) return const SizedBox();
    return ListTile(
      leading: const Icon(Icons.summarize_outlined),
      title: const Text("Ingredients Summary"),
      subtitle: Text(
          "Weighted Avg OG: ${weightedAverageOG?.toStringAsFixed(3) ?? 'N/A'}\nTotal Volume: ${batchVolumeGallons?.toStringAsFixed(2) ?? 'N/A'} gal"),
    );
  }

  Widget _buildCalculatedABVSection() {
    final ogDisplay = originalGravity.toStringAsFixed(3);
    final abvDisplay = abv.toStringAsFixed(2);
    return ListTile(
      leading: const Icon(Icons.percent),
      title: const Text("Estimated ABV"),
      subtitle: Text("$abvDisplay% (from OG: $ogDisplay)"),
    );
  }

  @override
  Widget build(BuildContext context) {
    // MOVED: settings initialization to here, where context is available.
    final settings = context.watch<SettingsModel>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.existingRecipe == null ? "Recipe Builder" : "Edit Recipe"),
        actions: [
          IconButton(onPressed: saveRecipe, icon: const Icon(Icons.save)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: "Recipe Name",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text("Tags", style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () async {
                          final result = await showTagPickerDialog(context, tags);
                          if (result != null) {
                            setState(() => tags = result);
                          }
                        },
                        child: const Text("Choose Tags"),
                      ),
                    ],
                  ),
                  if (tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children:
                            tags.map((tag) => Chip(label: Text(tag.name))).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _sectionTitle("Ingredients"),
          Card(
            child: Column(
              children: [
                if (ingredients.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("No ingredients added yet."),
                  ),
                ...ingredients.asMap().entries.map((entry) {
                  final i = entry.key;
                  final f = entry.value;
                  return ListTile(
                    title: Text(f['name'] ?? 'Unnamed'),
                    subtitle: Text(
                        "${f['amount'] ?? '—'} ${f['unit'] ?? ''}, OG: ${f['og']?.toStringAsFixed(3) ?? '—'}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => editIngredient(i)),
                        IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              setState(() => ingredients.removeAt(i));
                              calculateStats();
                            }),
                      ],
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text("Add Ingredient"),
                    onPressed: () async {
                      await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (_) => AddIngredientDialog(
                          unitType: UnitType.mass,
                          onAddToRecipe: addIngredient,
                          onAddToInventory: (ingredientData) async {
                            final scaffoldMessenger =
                                ScaffoldMessenger.of(context);
                            final purchase = PurchaseTransaction(
                              amount: (ingredientData['amount'] as num?)?.toDouble() ?? 0.0,
                              cost: (ingredientData['cost'] as num?)?.toDouble() ?? 0.0,
                              date: ingredientData['purchaseDate'] as DateTime? ?? DateTime.now(),
                              expirationDate: ingredientData['expirationDate'] as DateTime?,
                            );
                            
                            // FIX: Use the new InventoryItem constructor
                            final item = InventoryItem(
                              name: ingredientData['name'] as String? ?? 'Unnamed',
                              unit: ingredientData['unit'] as String? ?? 'oz',
                              unitType: inferUnitType(ingredientData['unit'] as String? ?? 'oz'),
                              category: ingredientData['type'] as String? ?? 'Other',
                              purchaseHistory: [purchase],
                            );
                            
                            final box = Hive.box<InventoryItem>('inventory');
                            await box.add(item);
                            if (!mounted) return;
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                  content:
                                      Text("Added '${item.name}' to Inventory")),
                            );
                            addIngredient(Map<String, dynamic>.from(ingredientData));
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          _sectionTitle("Additives"),
          Card(
            child: Column(
              children: [
                if (additives.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("No additives added yet."),
                  ),
                ...additives.asMap().entries.map((entry) {
                  final i = entry.key;
                  final a = entry.value;
                  return ListTile(
                    title: Text(a['name']),
                    subtitle: Text("${a['amount']} ${a['unit']}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => editAdditive(i)),
                        IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => setState(() => additives.removeAt(i))),
                      ],
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text("Add Additive"),
                    onPressed: () async {
                      await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (_) => AddAdditiveDialog(
                          mustPH: 3.4,
                          volume: 5.0,
                          onAdd: addAdditive,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          _sectionTitle("Yeast"),
          Card(
            child: Column(
              children: [
                if (yeast.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("No yeast added yet."),
                  ),
                ...yeast.map((y) {
                  final amount = y['amount'];
                  final unit = y['unit'];
                  final displayUnit =
                      (unit == 'packets' && amount == 1.0) ? 'packet' : unit;
                  return ListTile(
                    title: Text(y['name']),
                    subtitle: Text("$amount $displayUnit"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.edit), onPressed: editYeast),
                        IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => setState(() => yeast.clear())),
                      ],
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(yeast.isEmpty ? "Add Yeast" : "Edit Yeast"),
                    onPressed: yeast.isEmpty
                        ? () async {
                            final scaffoldMessenger =
                                ScaffoldMessenger.of(context);

                            await showDialog<Map<String, dynamic>>(
                              context: context,
                              builder: (_) => AddYeastDialog(
                                onAdd: addYeast,
                                onAddToInventory: (yeastData) async {
                                  final purchase = PurchaseTransaction(
                                    amount: (yeastData['amount'] as num?)?.toDouble() ?? 0.0,
                                    cost: (yeastData['cost'] as num?)?.toDouble() ?? 0.0,
                                    date: yeastData['purchaseDate'] as DateTime? ?? DateTime.now(),
                                    expirationDate: yeastData['expirationDate'] as DateTime?,
                                  );

                                  // FIX: Use the new InventoryItem constructor
                                  final item = InventoryItem(
                                    name: yeastData['name'] as String? ?? 'Unnamed',
                                    unit: yeastData['unit'] as String? ?? 'packets',
                                    unitType: inferUnitType(yeastData['unit'] as String? ?? 'packets'),
                                    category: 'Yeast',
                                    purchaseHistory: [purchase],
                                  );
                                  
                                  final box = Hive.box<InventoryItem>('inventory');
                                  await box.add(item);
                                  if (!mounted) return;
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            "Added '${item.name}' to Inventory")),
                                  );
                                  addYeast(Map<String, dynamic>.from(yeastData));
                                },
                              ),
                            );
                          }
                        : editYeast,
                  ),
                ),
              ],
            ),
          ),
          _sectionTitle("Fermentation"),
          Card(
            child: Column(
              children: [
                if (fermentationStages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("No fermentation stages added yet."),
                  ),
                ...fermentationStages.asMap().entries.map((entry) {
                  final i = entry.key;
                  final stage = entry.value;
                  final tempString = stage.targetTempC?.toDisplay(targetUnit: settings.unit) ?? '—';

                  return ListTile(
                    title: Text(stage.name),
                    // FIXED: Used the tempString variable which respects user settings.
                    subtitle: Text(
                        "${stage.durationDays} days @ $tempString"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () async {
                              await showDialog(
                                context: context,
                                builder: (_) => AddFermentationStageDialog(
                                  existing: stage,
                                  onSave: (updated) => setState(
                                      () => fermentationStages[i] = updated),
                                ),
                              );
                            }),
                        IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () =>
                                setState(() => fermentationStages.removeAt(i))),
                      ],
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text("Add Stage"),
                    onPressed: () async {
                      await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (_) => AddFermentationStageDialog(
                          onSave: (stage) {
                            setState(() => fermentationStages.add(stage));
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          _sectionTitle("Notes"),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextFormField(
                controller: notesController,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: "Tasting notes, process details, etc.",
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          _sectionTitle("Gravity & ABV"),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  if (ingredients.length > 1) ...[
                    _buildIngredientsSummary(),
                    const Divider(),
                  ],
                  _buildCalculatedABVSection(),
                  TextFormField(
                    initialValue: fg.toStringAsFixed(3),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Final Gravity"),
                    onChanged: (val) {
                      final parsed = double.tryParse(val);
                      if (parsed != null && parsed >= 0.990 && parsed <= 1.200) {
                        setState(() {
                          fg = parsed;
                          calculateStats();
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Gravity Adjustment",
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: volumeController,
                            decoration: const InputDecoration(
                              labelText: "Batch Volume",
                              border: OutlineInputBorder(),
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
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
                          items: VolumeUnit.values.map((unit) {
                            return DropdownMenuItem(
                              value: unit,
                              child: Text(unit.label),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: measuredMustSGController,
                      decoration: const InputDecoration(
                        labelText: "Measured Initial SG (Must)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: targetMustSGController,
                      decoration: const InputDecoration(
                        labelText: "Target Initial SG",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
                      decoration: const InputDecoration(
                        labelText: "Desired ABV (%)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 12),
                    DropdownButton<SugarType>(
                      isExpanded: true,
                      value: selectedSugarType,
                      onChanged: (type) {
                        setState(() {
                          selectedSugarType = type!;
                          _calculateSugarNeeded();
                        });
                      },
                      items: sugarTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type.name),
                        );
                      }).toList(),
                    ),
                    if (sugarNeededGrams != null)
                      ListTile(
                        title: const Text("Sugar Needed"),
                        subtitle: Text(
                            "${sugarNeededGrams!.toStringAsFixed(1)} grams of ${selectedSugarType.name}"),
                      ),
                    if (waterToAddLiters != null && waterToAddLiters! > 0)
                      ListTile(
                        title: const Text("Dilution Needed"),
                        subtitle: Text(
                            "${_formatDilutionVolume(waterToAddLiters!)} of water"),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}