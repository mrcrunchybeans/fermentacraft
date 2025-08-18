// lib/recipe_builder_page.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/utils/unit_conversion.dart';
import 'package:logger/logger.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'models/ingredient.dart';
import 'recipe_detail_page.dart';
import 'models/inventory_item.dart';
import 'models/settings_model.dart';
import 'utils/boxes.dart';
import 'utils/sugar_gravity_data.dart';
import 'widgets/add_additive_dialog.dart';
import 'widgets/add_fermentation_stage_dialog.dart';
import 'widgets/add_ingredient_dialog.dart';
import 'utils/utils.dart';
import 'models/recipe_model.dart';
import 'widgets/add_yeast_dialog.dart';
import 'dart:async';
import 'models/purchase_transaction.dart';
import 'models/unit_type.dart';
import 'utils/temp_display.dart';
import 'package:fermentacraft/utils/snacks.dart';

// NEW: gravity points estimator
import 'services/gravity_service.dart';

// Import the unique ID generator
import 'utils/id.dart';

final logger = Logger();
class _CategoryChoice {
  final String label;
  final IconData icon;
  const _CategoryChoice(this.label, this.icon);
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
  final TextEditingController categoryController = TextEditingController();
  final TextEditingController fgController = TextEditingController();
_CategoryChoice? _selectedCategory;
_CategoryChoice? _userCategory; // if user creates a custom category
late final List<_CategoryChoice> _defaultCategories;
late final _CategoryChoice _customSentinel;

List<DropdownMenuItem<_CategoryChoice>> _categoryItems() {
  final items = <_CategoryChoice>[
    ..._defaultCategories,
    if (_userCategory != null) _userCategory!,
    _customSentinel,
  ];
  return items.map((c) {
    return DropdownMenuItem<_CategoryChoice>(
      value: c,
      child: Row(
        children: [
          Icon(c.icon, size: 20),
          const SizedBox(width: 10),
          Text(c.label),
        ],
      ),
    );
  }).toList();
}

// NEW: dialog to create a custom category (name + icon)
Future<void> _openCustomCategoryDialog() async {
  final nameCtrl = TextEditingController();
  IconData selectedIcon = Icons.label_outline;
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

  final created = await showDialog<_CategoryChoice>(
    context: context,
    builder: (ctx) {
      int picked = 0;
      return StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Custom Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Category name',
                  hintText: 'e.g., Cyser',
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Icon', style: Theme.of(ctx).textTheme.titleSmall),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(iconChoices.length, (i) {
                  final icon = iconChoices[i];
                  final isSelected = i == picked;
                  return ChoiceChip(
                    label: Icon(icon, size: 18),
                    selected: isSelected,
                    onSelected: (_) {
                      setSt(() {
                        picked = i;
                        selectedIcon = iconChoices[picked];
                      });
                    },
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final label = nameCtrl.text.trim();
                if (label.isEmpty) return;
                Navigator.pop(ctx, _CategoryChoice(label, selectedIcon));
              },
              child: const Text('Use'),
            ),
          ],
        ),
      );
    },
  );

  if (created != null) {
    setState(() {
      _userCategory = created;
      _selectedCategory = created;
      categoryController.text = created.label; // keep existing save path
    });
  }
}



  // REPLACED: old OG fields
  double? _estimatedOG;        // from GravityService
  double _totalVolGal = 0.0;   // from GravityService
  double originalGravity = 1.000;

  AbvSource selectedAbvSource = AbvSource.measured;
  SugarType selectedSugarType = sugarTypes.first;
  VolumeUnit selectedVolumeUnit = VolumeUnit.gallons;
  Timer? sgToAbvDebounce;
  bool showAdvanced = false;
  double? sugarNeededGrams;
  double? targetMustSG;
  final TextEditingController targetMustSGController = TextEditingController();
  bool useAdjustedOG = false;
  bool userOverrodeAbv = false;
  bool userOverrodeMeasuredSG = false;
  bool userOverrodeBatchVolume = false;
  TextEditingController volumeController = TextEditingController(text: "5.0");
  double? waterToAddLiters;

  // Yeast (unchanged here; D is implemented in AddYeastDialog/YeastPicker)
  List<Map<dynamic, dynamic>> yeast = [];

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

      categoryController.text = widget.existingRecipe?.categoryLabel ?? '';
_defaultCategories = const [
  _CategoryChoice('Cider', Icons.local_drink),
  _CategoryChoice('Mead', Icons.hive_outlined),
  _CategoryChoice('Wine', Icons.wine_bar),
  _CategoryChoice('Fruit Wine', Icons.local_florist),
  _CategoryChoice('Seltzer', Icons.bubble_chart),
  _CategoryChoice('Other', Icons.category_outlined),
];
_customSentinel = const _CategoryChoice('Custom…', Icons.add_circle_outline);

final initialLabel = categoryController.text.trim();
final match = _defaultCategories.where((c) => c.label.toLowerCase() == initialLabel.toLowerCase());
if (initialLabel.isNotEmpty && match.isNotEmpty) {
  _selectedCategory = match.first;
} else if (initialLabel.isNotEmpty) {
  // load existing non-default as a "user category"
  _userCategory = _CategoryChoice(initialLabel, Icons.label_outline);
  _selectedCategory = _userCategory;
} else {
  // nothing set yet — leave null so the field shows placeholder
  _selectedCategory = null;
}

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
      fg = recipe.fg ?? fg;


      // Prefill all the regular fields
      nameController.text = recipe.name;
      notesController.text = recipe.notes;
      additives = List<Map<dynamic, dynamic>>.from(recipe.additives);
      ingredients = List<Map<dynamic, dynamic>>.from(recipe.ingredients);
      fermentationStages = List<FermentationStage>.from(recipe.fermentationStages);
      _estimatedOG = recipe.og; // best-effort seed
      abv = recipe.abv ?? abv;
      yeast = List<Map<dynamic, dynamic>>.from(recipe.yeast);


    }
    fgController.text = fg.toStringAsFixed(3);

    calculateStats();

    // Auto-fill measuredMustSG from estimatedOG (older behavior) if not overridden
    if (measuredMustSG == null && _estimatedOG != null) {
      measuredMustSG = _estimatedOG;
      measuredMustSGController.text = measuredMustSG!.toStringAsFixed(3);
    }
  }

  // ---------- Units helpers ----------
  static bool _isMassUnit(String u) {
    final s = u.toLowerCase();
    return s == 'g' || s == 'gram' || s == 'grams' ||
        s == 'kg' || s == 'kilogram' || s == 'kilograms' ||
        s == 'lb' || s == 'lbs' || s == 'pound' || s == 'pounds' ||
        s == 'oz (weight)' || s == 'ounce (weight)';
  }

  static bool _isVolumeUnit(String u) {
    final s = u.toLowerCase();
    return s == 'gallon' || s == 'gallons' || s == 'gal' ||
        s == 'l' || s == 'liter' || s == 'liters' ||
        s == 'ml' || s == 'milliliter' || s == 'milliliters' ||
        s == 'fl oz' || s == 'fluid ounce' || s == 'fluid ounces' ||
        s == 'oz' || s == 'ounces';
  }

  static double _toGallons(String unit, double amount) {
    switch (unit.toLowerCase()) {
      case 'oz':
      case 'ounces':
      case 'fl oz':
      case 'fluid ounce':
      case 'fluid ounces':
        return amount / 128.0;
      case 'l':
      case 'liter':
      case 'liters':
        return amount / 3.78541;
      case 'ml':
      case 'milliliter':
      case 'milliliters':
        return amount / 3785.41;
      case 'gallon':
      case 'gallons':
      case 'gal':
      default:
        return amount;
    }
  }

  static double _toPounds(String unit, double amount) {
    switch (unit.toLowerCase()) {
      case 'g':
      case 'gram':
      case 'grams':
        return amount / 453.59237;
      case 'kg':
      case 'kilogram':
      case 'kilograms':
        return amount * 2.20462262;
      case 'lb':
      case 'lbs':
      case 'pound':
      case 'pounds':
        return amount;
      case 'oz (weight)':
      case 'ounce (weight)':
        return amount / 16.0;
      default:
        return 0.0; // non-mass units
    }
  }

  static double _ppgForName(String name) {
    final n = name.toLowerCase();
    if (n.contains('sucrose') || n.contains('table sugar') || n == 'sugar') return 46.0;
    if (n.contains('dextrose') || n.contains('corn sugar')) return 46.0;
    if (n.contains('honey')) return 35.0;
    return 46.0;
  }

  List<FermentableItem> _buildItemsFromIngredients(List<Map<dynamic, dynamic>> ings) {
    final List<FermentableItem> items = [];
    for (final raw in ings) {
      final f = Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
      final name = (f['name'] ?? '').toString();
      final unit = (f['unit'] ?? '').toString();
      final amount = (f['amount'] as num?)?.toDouble() ?? 0.0;
      final og = (f['og'] as num?)?.toDouble();
      final ppg = (f['ppg'] as num?)?.toDouble();

      if (amount <= 0) continue;

      if (_isVolumeUnit(unit)) {
        final volGal = _toGallons(unit, amount);
        items.add(FermentableItem(
          isLiquid: true,
          volumeGal: volGal,
          sg: (og != null && og >= 1.0) ? og : null,
        ));
      } else if (_isMassUnit(unit)) {
        final pounds = _toPounds(unit, amount);
        final p = ppg ?? _ppgForName(name);
        if (pounds > 0 && p > 0) {
          items.add(FermentableItem(
            isLiquid: false,
            weightLb: pounds,
            ppg: p,
          ));
        }
      } else {
        debugPrint('Ignored ingredient with unknown unit "$unit": $name');
      }
    }
    return items;
  }

void _updateMeasuredMustSGIfNotOverridden() {
  if (!userOverrodeMeasuredSG && _estimatedOG != null) {
    measuredMustSG = _estimatedOG;
    measuredMustSGController.text = measuredMustSG!.toStringAsFixed(3);
  }
}

void setFg(double value) {
  fg = value;
  fgController.text = value.toStringAsFixed(3);
  calculateStats();
  setState(() {});
}

void calculateStats() {
  // 1) Build inputs for the corrected gravity math
  final items = _buildItemsFromIngredients(ingredients);

  // 2) Call the new API and use the new field names
  final GravityResult result = GravityService.estimate(items);
  _estimatedOG = result.og;                    // was result.estimatedOG
  _totalVolGal = result.totalVolumeGal;

  // 3) Mirror volume where you store it
  batchVolumeGallons = _totalVolGal;

  // 4) If the user didn’t override measured SG, prefill it from estimate
  _updateMeasuredMustSGIfNotOverridden();

  // 5) Update the visible volume field if not overridden
  if (batchVolumeGallons != null && !userOverrodeBatchVolume) {
    final double value =
        (selectedVolumeUnit == VolumeUnit.ounces)
            ? (batchVolumeGallons! * 128.0)
            : (selectedVolumeUnit == VolumeUnit.liters)
                ? (batchVolumeGallons! * 3.78541)
                : batchVolumeGallons!;
    volumeController.text = value.toStringAsFixed(2);
  }

  // 6) Choose OG (estimated vs user-adjusted/measured)
  if (!showAdvanced) {
    originalGravity = _estimatedOG ?? 1.000;
  } else {
    originalGravity = useAdjustedOG
        ? (targetMustSG ?? _estimatedOG ?? 1.000)
        : (measuredMustSG ?? _estimatedOG ?? 1.000);
  }

  // 7) Use the new ABV helper (guards are already in GravityService)
  final double fgValue = fg;
  abv = GravityService.abv(og: originalGravity, fg: fgValue);

  // 8) Back-fill desired ABV if the user didn’t override it
  if (!userOverrodeAbv) {
    desiredAbv = abv;
    desiredAbvController.text = abv.toStringAsFixed(2);
  }

  setState(() {});
}

  void addIngredient(Map<String, dynamic> ingredientMap) {
    final clean = Map<String, dynamic>.from(ingredientMap);
    clean.forEach((k, v) {
      if (v is DateTime) clean[k] = v.toIso8601String();
    });

    setState(() {
      ingredients.add(clean);
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
    final clean = Map<String, dynamic>.from(yeastMap);
    clean.forEach((k, v) {
      if (v is DateTime) clean[k] = v.toIso8601String();
    });
    setState(() {
      yeast = [clean];
    });
  }

  void editYeast() async {
    if (yeast.isEmpty) return;
    final scaffoldMessenger = snacks;
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
          final item = InventoryItem(
            id: generateId(),
            name: yeastData['name'] as String? ?? 'Unnamed',
            unit: yeastData['unit'] as String? ?? 'packets',
            unitType: inferUnitType(yeastData['unit'] as String? ?? 'packets'),
            category: 'Yeast',
            purchaseHistory: [purchase],
          );
          final box = Hive.box<InventoryItem>(Boxes.inventory);
          await box.put(item.id, item);
          if (!mounted) return;
          scaffoldMessenger.show(
            SnackBar(content: Text("Added '${item.name}' to Inventory")),
          );
          addYeast(yeastData);
        },
      ),
    );
  }

  void addAdditive(Map<String, dynamic> additiveMap) {
    final clean = Map<String, dynamic>.from(additiveMap);
    clean.forEach((k, v) {
      if (v is DateTime) clean[k] = v.toIso8601String();
    });
    setState(() {
      additives.add(clean);
    });
  }

  // ✅ Refactored: rely on RecipeModel.setTagsFromBox for canonicalization & refs
  void saveRecipe() {
    final recipeName = nameController.text.trim();
    if (recipeName.isEmpty) {
      snacks.show(const SnackBar(content: Text("Please enter a recipe name.")));
      return;
    }

    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (_) => AlertDialog(
        title: const Text("Confirm Save"),
        content: Text('Save recipe as "$recipeName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              // 1) Build recipe (don’t pass tags here; we’ll attach via setTagsFromBox)
              final rawCategory = categoryController.text.trim();
              final category = rawCategory.isEmpty ? 'Uncategorized' : rawCategory;
final newRecipe = RecipeModel(
  id: (widget.existingRecipe != null && !widget.isClone)
      ? widget.existingRecipe!.id
      : generateId(),
  name: recipeName,
  createdAt: widget.existingRecipe?.createdAt ?? DateTime.now(),
  fg: fg,
  abv: abv,
  additives: additives,
  og: originalGravity,
  ingredients: ingredients,
  yeast: yeast,
  category: category,
  fermentationStages: fermentationStages,
  notes: notesController.text.trim(),
);

// Save to Hive
final box = Hive.box<RecipeModel>(Boxes.recipes);
await box.put(newRecipe.id, newRecipe);

// ❌ Remove tag attachment completely:
// final tagBox = Hive.box<Tag>(Boxes.tags);
// await newRecipe.setTagsFromBox(tags, tagBox);


              if (!mounted) return;

              // Close dialog then go to details
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => RecipeDetailPage(
                    recipe: newRecipe,
                    recipeKey: newRecipe.id,
                  ),
                ),
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
      sugarNeededGrams = sgDelta / selectedSugarType.sgPerGramPerLiter * batchLiters;
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
    if (ounces >= 0.1 || parts.isEmpty) parts.add("${ounces.toStringAsFixed(1)} fl oz");
    return parts.join(' ');
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );

  Widget _buildIngredientsSummary() {
    if (ingredients.length <= 1) return const SizedBox();
    return ListTile(
      leading: const Icon(Icons.summarize_outlined),
      title: const Text("Ingredients Summary"),
      subtitle: Text(
        "Estimated OG: ${_estimatedOG?.toStringAsFixed(3) ?? 'N/A'}\n"
            "Total Volume: ${_totalVolGal.toStringAsFixed(2)} gal",
      ),
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
    final settings = context.watch<SettingsModel>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingRecipe == null ? "Recipe Builder" : "Edit Recipe"),
        actions: [
          IconButton(onPressed: saveRecipe, icon: const Icon(Icons.save)),
        ],
      ),
      body: ListView(
  children: [
    // ---- Category (replaces Tags) ----
// NEW: Recipe Name (you already capture nameController in saveRecipe)
Padding(
  padding: const EdgeInsets.symmetric(vertical: 8.0),
  child: TextFormField(
    controller: nameController,
    decoration: const InputDecoration(
      labelText: 'Recipe Name',
      hintText: 'e.g., Dry Traditional Mead',
      prefixIcon: Icon(Icons.edit),
      border: OutlineInputBorder(),
    ),
    textInputAction: TextInputAction.next,
  ),
),

// NEW: Category dropdown w/ icons + Custom option
Padding(
  padding: const EdgeInsets.symmetric(vertical: 8.0),
  child: DropdownButtonFormField<_CategoryChoice>(
    value: _selectedCategory,
    items: _categoryItems(),
    decoration: InputDecoration(
      labelText: 'Category',
      prefixIcon: Icon(
        _selectedCategory?.icon ?? Icons.category_outlined,
      ),
      border: const OutlineInputBorder(),
    ),
    hint: const Text('Select a category'),
    onChanged: (choice) async {
      if (choice == null) return;
      if (identical(choice, _customSentinel)) {
        await _openCustomCategoryDialog();
        return;
      }
      setState(() {
        _selectedCategory = choice;
        categoryController.text = choice.label; // keep saveRecipe unchanged
      });
    },
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

  final amount = f['amount'];
  final unit   = f['unit'];
  final ogRaw  = f['og'];
  final ogVal  = (ogRaw is num) ? ogRaw.toDouble() : double.tryParse('$ogRaw');

  return ListTile(
    title: Text(f['name'] ?? 'Unnamed'),
    subtitle: Text(
      "${amount ?? '—'} ${unit ?? ''}, OG: ${ogVal?.toStringAsFixed(3) ?? '—'}",
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: const Icon(Icons.edit), onPressed: () => editIngredient(i)),
        IconButton(icon: const Icon(Icons.delete), onPressed: () {
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
                            final scaffoldMessenger = snacks;
                            final purchase = PurchaseTransaction(
                              amount: (ingredientData['amount'] as num?)?.toDouble() ?? 0.0,
                              cost: (ingredientData['cost'] as num?)?.toDouble() ?? 0.0,
                              date: ingredientData['purchaseDate'] as DateTime? ?? DateTime.now(),
                              expirationDate: ingredientData['expirationDate'] as DateTime?,
                            );
                            final item = InventoryItem(
                              id: generateId(),
                              name: ingredientData['name'] as String? ?? 'Unnamed',
                              unit: ingredientData['unit'] as String? ?? 'packets',
                              unitType: inferUnitType(ingredientData['unit'] as String? ?? 'packets'),
                              category: 'Ingredient',
                              purchaseHistory: [purchase],
                            );
                            final box = Hive.box<InventoryItem>(Boxes.inventory);
                            await box.put(item.id, item);
                            if (!mounted) return;
                            scaffoldMessenger.show(
                              SnackBar(content: Text("Added '${item.name}' to Inventory")),
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
                        IconButton(icon: const Icon(Icons.edit), onPressed: () => editAdditive(i)),
                        IconButton(icon: const Icon(Icons.delete), onPressed: () => setState(() => additives.removeAt(i))),
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
                  final displayUnit = (unit == 'packets' && amount == 1.0) ? 'packet' : unit;
                  return ListTile(
                    title: Text(y['name']),
                    subtitle: Text("$amount $displayUnit"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit), onPressed: editYeast),
                        IconButton(icon: const Icon(Icons.delete), onPressed: () => setState(() => yeast.clear())),
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
                      final scaffoldMessenger = snacks;
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
                            final item = InventoryItem(
                              id: generateId(),
                              name: yeastData['name'] as String? ?? 'Unnamed',
                              unit: yeastData['unit'] as String? ?? 'packets',
                              unitType: inferUnitType(yeastData['unit'] as String? ?? 'packets'),
                              category: 'Yeast',
                              purchaseHistory: [purchase],
                            );
                            final box = Hive.box<InventoryItem>(Boxes.inventory);
                            await box.put(item.id, item);
                            if (!mounted) return;
                            scaffoldMessenger.show(
                              SnackBar(content: Text("Added '${item.name}' to Inventory")),
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
                    subtitle: Text("${stage.durationDays} days @ $tempString"),
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
                                onSave: (updated) => setState(() => fermentationStages[i] = updated),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => setState(() => fermentationStages.removeAt(i)),
                        ),
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
                          onSave: (stage) => setState(() => fermentationStages.add(stage)),
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
  controller: fgController,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  decoration: const InputDecoration(labelText: "Final Gravity"),
onChanged: (val) {
  if (val.trim().isEmpty) return;
  final parsed = double.tryParse(val);
  if (parsed != null && parsed >= 0.990 && parsed <= 1.200) {
    setFg(parsed);
  }
},

  onEditingComplete: () {
    final parsed = double.tryParse(fgController.text);
    if (parsed != null) {
      final clamped = parsed.clamp(0.990, 1.200);
      setFg(double.parse(clamped.toStringAsFixed(3)));
    }
    FocusScope.of(context).unfocus(); // optional: dismiss keyboard
  },
  // optional polish:
  textInputAction: TextInputAction.done,
  onFieldSubmitted: (_) => FocusScope.of(context).unfocus()

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
                Switch(value: showAdvanced, onChanged: (val) => setState(() => showAdvanced = val)),
              ],
            ),
          ),
          if (showAdvanced) // Expected an identifier.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Gravity Adjustment", style: Theme.of(context).textTheme.titleLarge),
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
                          items: VolumeUnit.values.map((unit) {
                            return DropdownMenuItem(value: unit, child: Text(unit.label));
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: targetMustSGController,
                      decoration: const InputDecoration(
                        labelText: "Target Initial SG",
                        border: OutlineInputBorder(),
                      ),
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
                      decoration: const InputDecoration(
                        labelText: "Desired ABV (%)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                        return DropdownMenuItem(value: type, child: Text(type.name));
                      }).toList(),
                    ),
                    if (sugarNeededGrams != null)
                      ListTile(
                        title: const Text("Sugar Needed"),
                        subtitle: Text("${sugarNeededGrams!.toStringAsFixed(1)} grams of ${selectedSugarType.name}"),
                      ),
                    if (waterToAddLiters != null && waterToAddLiters! > 0)
                      ListTile(
                        title: const Text("Dilution Needed"),
                        subtitle: Text("${_formatDilutionVolume(waterToAddLiters!)} of water"),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    desiredAbvController.dispose();
    measuredMustSGController.dispose();
    nameController.dispose();
    notesController.dispose();
    targetMustSGController.dispose();
    volumeController.dispose();
    categoryController.dispose(); // <- add this
    fgController.dispose();
    sgToAbvDebounce?.cancel();
    super.dispose();
  }
}