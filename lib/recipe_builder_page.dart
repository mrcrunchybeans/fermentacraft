import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/tag.dart';
import 'package:flutter_application_1/utils/temp_display.dart';
import 'package:logger/logger.dart';
import 'package:hive/hive.dart';
import 'models/fermentable.dart';
import 'utils/sugar_gravity_data.dart';
import 'widgets/add_additive_dialog.dart';
import 'widgets/add_fermentation_stage_dialog.dart';
import 'widgets/add_fermentable_dialog.dart';
import 'utils/utils.dart';
import 'models/recipe_model.dart';
import 'recipe_list_page.dart';
import 'package:provider/provider.dart';
import 'widgets/tag_picker_dialog.dart';
import 'package:flutter_application_1/models/tag_manager.dart';
import 'widgets/add_yeast_dialog.dart';
import 'dart:async';




final logger = Logger();


double calculateAbv(double og, double fg) {
  return (og - fg) * 131.25;
}

class RecipeBuilderPage extends StatefulWidget {
  final RecipeModel? existingRecipe;
  final int? recipeKey;
  final bool isClone;

  const RecipeBuilderPage({
    super.key,
    this.existingRecipe,
    this.recipeKey,
    this.isClone = false,
  });

  @override
  State<RecipeBuilderPage> createState() => _RecipeBuilderPageState();
}


class _RecipeBuilderPageState extends State<RecipeBuilderPage> {
  Timer? sgToAbvDebounce;
  bool userOverrodeAbv = false;
  bool userOverrodeTargetSG = false;
  final TextEditingController measuredMustSGController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController targetMustSGController = TextEditingController();
  bool get hasAnyOg => fermentables.any((f) => f.containsKey('og') && f['og'] != null);
  double abv = 0.0;
  List<Map<String, dynamic>> additives = [];
  List<Map<String, dynamic>> fermentables = [];
  List<Map<String, dynamic>> yeast = [];
  List<Map<String, dynamic>> fermentationStages = [];
  List<Tag> tags = [];
  double fg = 1.010;
  double? og;
  bool showAdvanced = false;
  bool userOverrodeMeasuredOG = false;
  double? measuredMustSG;
  double? targetMustSG;
  double? batchVolumeGallons;
  double originalGravity = 1.000;
  double? sugarNeededGrams;
  bool userOverrodeMeasuredSG = false;
  bool showAdvancedFields = true;
  SugarType selectedSugarType = sugarTypes.first;
  double? waterToDiluteLiters;
  VolumeUnit selectedVolumeUnit = VolumeUnit.gallons;
  TextEditingController volumeController = TextEditingController(text: "18.9");
  double? waterToAddLiters;
  VolumeUnit selectedWaterUnit = VolumeUnit.ounces;
  AbvSource selectedAbvSource = AbvSource.measured;
  bool useAdjustedOG = false;
  double? weightedAverageOG;
  final TextEditingController desiredAbvController = TextEditingController();
  double? desiredAbv;
  




Widget _buildCalculatedABVSection() {
  final ogDisplay = originalGravity.toStringAsFixed(3);
  final abvDisplay = abv.toStringAsFixed(2);
  final ogSource = useAdjustedOG ? "Target" : measuredMustSG != null ? "Measured" : weightedAverageOG != null ? "Weighted" : "Default";

  return Card(
    color: Colors.grey[100],
    margin: const EdgeInsets.symmetric(vertical: 12),
    child: ListTile(
      leading: const Icon(Icons.percent),
      title: const Text("Estimated ABV"),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Original Gravity Used ($ogSource): $ogDisplay"),
          Text("Estimated ABV: $abvDisplay%"),
        ],
      ),
    ),
  );
}

void _updateMeasuredMustSGIfNotOverridden() {
  if (!userOverrodeMeasuredSG && weightedAverageOG != null) {
    measuredMustSG = weightedAverageOG;
    measuredMustSGController.text = measuredMustSG!.toStringAsFixed(3);
  }
}


void updateMeasuredMustSGFromWeighted() {
  if (!userOverrodeMeasuredOG && weightedAverageOG != null) {
    measuredMustSG = weightedAverageOG;
    measuredMustSGController.text = weightedAverageOG!.toStringAsFixed(3);
  }
}



Widget _buildFermentablesSummary() {
  final validFermentables = fermentables.where((f) =>
      f.containsKey('og') &&
      f['og'] != null &&
      f.containsKey('amount') &&
      f['amount'] != null &&
      f.containsKey('unit') &&
      f['unit'] != null);

  if (validFermentables.length <= 1) return const SizedBox();

  // Calculate weighted OG and converted volumes
  double totalVolumeGallons = 0;
  double weightedOGSum = 0;

  for (final f in validFermentables) {
    final amount = double.tryParse(f['amount'].toString()) ?? 0;
    final unit = f['unit']?.toString().toLowerCase();
    final og = f['og'] as double;

    // Convert to gallons
    double amountInGallons;
    switch (unit) {
      case 'oz':
      case 'ounces':
        amountInGallons = amount / 128.0;
        break;
      case 'liters':
      case 'l':
        amountInGallons = amount / 3.78541;
        break;
      case 'ml':
        amountInGallons = amount / 3785.41;
        break;
      case 'gallons':
      case 'gallon':
      default:
        amountInGallons = amount;
    }

    totalVolumeGallons += amountInGallons;
    weightedOGSum += og * amountInGallons;
  }

  final averageOG = totalVolumeGallons > 0 ? weightedOGSum / totalVolumeGallons : 0;


  return Card(
    color: Colors.grey[100],
    margin: const EdgeInsets.symmetric(vertical: 12),
    child: ListTile(
      leading: const Icon(Icons.summarize),
      title: const Text("Fermentables Summary"),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Weighted Avg OG: ${averageOG.toStringAsFixed(3)}"),
          Text("Total Volume: ${totalVolumeGallons.toStringAsFixed(2)} gal"),
        ],
      ),
    ),
  );
  
}

void _calculateSugarNeeded() {
  sugarNeededGrams = null;
  waterToAddLiters = null;

  if (measuredMustSG == null || targetMustSG == null) return;

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
    // Need to add sugar
    sugarNeededGrams = sgDelta / selectedSugarType.sgPerGramPerLiter * batchLiters;
  } else if (sgDelta < 0) {
    // Need to dilute
    final dilutionRatio = measuredMustSG! / targetMustSG!;
    final newTotalVolume = batchLiters * dilutionRatio;
    waterToAddLiters = newTotalVolume - batchLiters;
  }


  setState(() {});
  calculateStats();
  _updateMeasuredMustSGIfNotOverridden();

}

 @override
void initState() {
  super.initState();
     desiredAbvController.addListener(() {
  final input = desiredAbvController.text;
  final parsed = double.tryParse(input);

  if (parsed != null && parsed > 0 && parsed < 25) {
    setState(() {
      userOverrodeAbv = true;
      userOverrodeTargetSG = false;

      desiredAbv = parsed;
      final requiredOG = (desiredAbv! / 131.25) + fg;
      final formattedOG = double.parse(requiredOG.toStringAsFixed(3));

      targetMustSG = formattedOG;
      targetMustSGController.text = formattedOG.toStringAsFixed(3);
      _calculateSugarNeeded();
      if (useAdjustedOG) calculateStats();
    });
  }
});

  // Optional: keep targetMustSGController synced if targetMustSG changes elsewhere
  if (targetMustSG != null) {
    targetMustSGController.text = targetMustSG!.toStringAsFixed(3);
  }
  measuredMustSGController.addListener(() {
  final input = measuredMustSGController.text;
  final parsed = double.tryParse(input);
  if (parsed != null) {
    setState(() {
      measuredMustSG = parsed;
      calculateStats();
      _updateMeasuredMustSGIfNotOverridden();

    });
  }
});

  if (widget.existingRecipe != null) {
    final recipe = widget.existingRecipe!;
    nameController.text = recipe.name;
    notesController.text = recipe.notes;
    additives = List<Map<String, dynamic>>.from(recipe.additives);
    fermentables = List<Map<String, dynamic>>.from(recipe.fermentables);
    fermentationStages = List<Map<String, dynamic>>.from(recipe.fermentationStages);
    og = recipe.og;
    fg = recipe.fg;
    abv = recipe.abv;
    yeast = List<Map<String, dynamic>>.from(recipe.yeast);
    tags = List<Tag>.from(recipe.tags);
  }

  calculateStats();
    if (measuredMustSG == null && weightedAverageOG != null) {
    measuredMustSG = weightedAverageOG;
    measuredMustSGController.text = measuredMustSG!.toStringAsFixed(3);
  }
}

// ########## Start of CalculateStats ##########

void calculateStats() {
  double totalVolumeGallons = 0;
  double weightedOGSum = 0;

  for (final f in fermentables) {
    final og = f['og'];
    final amount = f['amount'];
    final unit = f['unit'];

    if (og == null || amount == null || unit == null) continue;

    final amountValue = double.tryParse(amount.toString()) ?? 0;
    double amountInGallons;

    abv = calculateAbv(originalGravity, fg);

    if (!userOverrodeAbv) {
      desiredAbv = abv;
      desiredAbvController.text = abv.toStringAsFixed(2);
    }


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

  weightedAverageOG = totalVolumeGallons > 0 ? weightedOGSum / totalVolumeGallons : null;

  _updateMeasuredMustSGIfNotOverridden();

  // 🔥 Set the batch volume for gravity adjustment
  batchVolumeGallons = totalVolumeGallons;

  // 🔁 Update the gravity adjustment volumeController
  if (batchVolumeGallons != null) {
    final double value = selectedVolumeUnit == VolumeUnit.ounces
        ? batchVolumeGallons! * 128.0
        : selectedVolumeUnit == VolumeUnit.liters
            ? batchVolumeGallons! * 3.78541
            : batchVolumeGallons!;
    volumeController.text = value.toStringAsFixed(2);
  }

  // Set originalGravity
  originalGravity = !showAdvanced
      ? (weightedAverageOG ?? 1.000)
      : (useAdjustedOG
          ? (targetMustSG ?? weightedAverageOG ?? 1.000)
          : (measuredMustSG ?? weightedAverageOG ?? 1.000));

  abv = calculateAbv(originalGravity, fg);

  logger.d("Stats calculated - OG: $originalGravity, FG: $fg, ABV: $abv, Weighted OG: $weightedAverageOG, Total Volume: $totalVolumeGallons gal");

abv = calculateAbv(originalGravity, fg);

// Update desired ABV unless overridden
if (!userOverrodeAbv) {
  desiredAbv = abv;
  desiredAbvController.text = abv.toStringAsFixed(2);
}


}


// ########### End of CalculateStats ###########




void addFermentable(Map<String, dynamic> f) {
  setState(() {
    _updateMeasuredMustSGIfNotOverridden();
 
    fermentables.add(f);
  });

  calculateStats();

  if (measuredMustSG == null && weightedAverageOG != null) {
    setState(() {
      measuredMustSG = weightedAverageOG;
      measuredMustSGController.text = measuredMustSG!.toStringAsFixed(3);
       _updateMeasuredMustSGIfNotOverridden();

      updateMeasuredMustSGFromWeighted();

    });
  }

  logger.d("Added fermentable: ${f['name']}");
  logger.i("OG fallback check → measuredMustSG: $measuredMustSG, weightedAverageOG: $weightedAverageOG");
}



  void editFermentable(int index) async {
  final existing = fermentables[index];

  await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => AddFermentableDialog(
      existing: existing,
      onAddToRecipe: (updated) {
        setState(() {
          fermentables[index] = updated;
          if (updated.containsKey('og') && updated['og'] != null) {
            og = updated['og'];
          }
        });
        calculateStats();
          _updateMeasuredMustSGIfNotOverridden();
          updateMeasuredMustSGFromWeighted();


      },
      onAddToInventory: (_) {},
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
        existing: existing,
        onAdd: (updated) {
          setState(() {
            additives[index] = updated;
          });
          calculateStats();
          _updateMeasuredMustSGIfNotOverridden();

        },
      ),
    );
  }

TextEditingController notesController = TextEditingController();


void addYeast(Map<String, dynamic> y) {
  setState(() {
    yeast = [y]; // Only one yeast allowed, replace any existing
  });
  logger.d("Added yeast: ${y['name']}");
}

void editYeast() async {
  final existing = yeast.isNotEmpty ? yeast.first : null;

  await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => AddYeastDialog(
      existing: existing,
      onAdd: (updated) {
        setState(() {
          yeast = [updated];
        });
      },
    ),
  );
}

    double getConvertedWaterAmount() {
      if (waterToAddLiters == null) return 0.0;
      switch (selectedWaterUnit) {
        case VolumeUnit.gallons:
          return waterToAddLiters! / 3.78541;
        case VolumeUnit.ounces:
          return waterToAddLiters! / 0.0295735;
        default:
          return waterToAddLiters!;
      }
    }



  void addAdditive(Map<String, dynamic> a) {
    setState(() {
      additives.add(a);
    });
    logger.d("Added additive: ${a['name']}");
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
              fermentables: fermentables,
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

            logger.i("${widget.isClone ? "Cloned" : widget.existingRecipe != null ? "Updated" : "Saved"} recipe: $recipeName");

            if (!mounted) return;
            Navigator.of(context).pop(); // Close dialog
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const RecipeListPage()),
            );
          },
          child: const Text("Save"),
        ),
      ],
    ),
  );
}

// ######## Start of _buildSectionTitle ########


  Widget _buildSectionTitle(String title, {VoidCallback? onAdd}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (onAdd != null)
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text("Add ${title.split(' ').first}"),
          ),
      ],
    );
  }

  @override
  
  Widget build(BuildContext context) {
    Provider.of<TagManager>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cider Recipe Builder"),
        actions: [
          IconButton(onPressed: saveRecipe, icon: const Icon(Icons.save)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              const Text("Show Advanced Fields"),
              Switch(
                value: showAdvanced,
                onChanged: (val) => setState(() => showAdvanced = val),
              ),
            ],
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: "Recipe Name",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Tags", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: tags.map((tag) => Chip(label: Text(tag.name))).toList(),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.label),
                label: const Text("Choose Tags"),
                onPressed: () async {
                  final result = await showTagPickerDialog(context, tags);
                  if (result != null) {
                    setState(() => tags = result);
                  }
                },
              ),
              const Divider(thickness: 1.2),
            ],
          ),

          _buildSectionTitle("Fermentables", onAdd: () async {
            final result = await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (_) => AddFermentableDialog(
                onAddToRecipe: addFermentable,
                onAddToInventory: (_) {},
              ),
            );
            if (result != null) addFermentable(result);
          }),
          ...fermentables.asMap().entries.map((entry) {
            final i = entry.key;
            final f = entry.value;
            return ListTile(
              title: Text(f['name'] ?? 'Unnamed'),
              subtitle: Text("${f['amount'] ?? '—'} ${f['unit'] ?? ''}, OG: ${f['og']?.toStringAsFixed(3) ?? '—'}"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => editFermentable(i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      setState(() {
                        fermentables.removeAt(i);
                      });
                      calculateStats();
                      updateMeasuredMustSGFromWeighted();

                    },
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 24),

          const Divider(thickness: 1.0),
          _buildFermentablesSummary(),
          const Divider(thickness: 1.0),




          _buildSectionTitle("Additives", onAdd: () async {
            final result = await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (_) => AddAdditiveDialog(
                mustPH: 3.4,
                volume: 5.0,
                onAdd: addAdditive,
              ),
            );
            if (result != null) addAdditive(result);
          }),
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
                    onPressed: () => editAdditive(i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      setState(() {
                        additives.removeAt(i);
                      });
                    },
                  ),
                ],
              ),
            );
          }),


          const SizedBox(height: 24),

          _buildSectionTitle("Yeast", onAdd: () async {
            final result = await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (_) => AddYeastDialog(
                onAdd: addYeast,
                existing: yeast.isNotEmpty ? yeast.first : null,

              ),
            );
            if (result != null) addYeast(result);
          }),
          ...yeast.map((y) {
  final amount = y['amount'];
  final unit = y['unit'];
  final displayUnit = (unit == 'packets' && amount == 1) ? 'packet' : unit;

  return ListTile(
    title: Text(y['name']),
    subtitle: Text("$amount $displayUnit"),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: editYeast,
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () {
            setState(() => yeast.clear());
          },
        ),
      ],
    ),
  );
}),


          const SizedBox(height: 24),

          _buildSectionTitle("Fermentation Profile", onAdd: () async {
            await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (_) => AddFermentationStageDialog(
                onSave: (stage) {
                  setState(() {
                    fermentationStages.add(stage);
                  });
                },
              ),
            );
          }),
          ...fermentationStages.asMap().entries.map((entry) {
            final i = entry.key;
            final stage = entry.value;
            return ListTile(
              title: Text(stage['name']),
              subtitle: Text("${stage['days']} ${stage['days'] == 1 ? 'day' : 'days'} @ ${TempDisplay.format(stage['temp'])}"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (_) => AddFermentationStageDialog(
                          existing: stage,
                          onSave: (updatedStage) {
                            setState(() {
                              fermentationStages[i] = updatedStage;
                            });
                          },
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      setState(() {
                        fermentationStages.removeAt(i);
                      });
                    },
                  ),
                ],
              ),
            );
          }),

          // --- NEW SECTION FOR TARGET SG & SUGAR CALC ---

          const SizedBox(height: 12),
          const Divider(thickness: 1.5),

                    TextFormField(
            controller: notesController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: "Notes",
              hintText: "Any extra information, comments, or observations",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          const Divider(thickness: 1.5),

 const Divider(thickness: 1.5),

ListTile(
  title: const Text("Original Gravity"),
  subtitle: Text(originalGravity.toStringAsFixed(3)),
),

const SizedBox(height: 12),

TextFormField(
  initialValue: fg.toStringAsFixed(3),
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  decoration: const InputDecoration(
    labelText: "Final Gravity",
    border: OutlineInputBorder(),
  ),
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

const SizedBox(height: 12),

_buildCalculatedABVSection(),

const SizedBox(height: 12),

Row(
  children: [
    Expanded(
      child: ListTile(
        title: const Text("ABV"),
        subtitle: Text("${abv.toStringAsFixed(2)}%"),
      ),
    ),
    if (showAdvanced)
      DropdownButton<bool>(
        value: useAdjustedOG,
        onChanged: (val) {
          if (val != null) {
            setState(() {
              useAdjustedOG = val;
              selectedAbvSource = val ? AbvSource.adjusted : AbvSource.measured;
              calculateStats();
              _updateMeasuredMustSGIfNotOverridden();

            });
          }
        },
        items: const [
          DropdownMenuItem(value: false, child: Text("Use Measured OG")),
          DropdownMenuItem(value: true, child: Text("Use Adjusted OG")),
        ],
      ),
  ],
),



  // 💡 Gravity Adjustment Section
  if (showAdvanced) ...[
    const Divider(thickness: 1.5),
    const Text("Gravity Adjustment", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 20),

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
        onChanged: (_) => setState(() => _calculateSugarNeeded()),
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
    hintText: "e.g. 1.045",
    border: OutlineInputBorder(),
  ),
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  onChanged: (val) {
      setState(() {
        measuredMustSG = double.tryParse(val);
      userOverrodeMeasuredSG = true;
      _calculateSugarNeeded();
      if (selectedAbvSource == AbvSource.measured) {
        calculateStats(); // Only recalculate if we're using measured OG
      }
        }
      );
    },

),

    const SizedBox(height: 12),

        TextFormField(
  controller: targetMustSGController,
  decoration: const InputDecoration(
    labelText: "Target Initial SG",
    hintText: "e.g. 1.065",
    border: OutlineInputBorder(),
  ),
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  onChanged: (val) {
  final parsed = double.tryParse(val);
  if (parsed != null) {
    setState(() {
      userOverrodeTargetSG = true;
      userOverrodeAbv = false;
      targetMustSG = parsed;
      _calculateSugarNeeded();
    });

    // debounce ABV update
    sgToAbvDebounce?.cancel();
    sgToAbvDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!userOverrodeAbv && mounted) {
        final calculatedAbv = (parsed - fg) * 131.25;
        setState(() {
          desiredAbv = calculatedAbv;
          desiredAbvController.text = calculatedAbv.toStringAsFixed(2);
        });
      }
    });

    if (useAdjustedOG) calculateStats();
  }
},

),



const SizedBox(height: 12),

TextFormField(
  controller: desiredAbvController,
  decoration: const InputDecoration(
    labelText: "Desired ABV (%)",
    hintText: "e.g. 6.5",
    border: OutlineInputBorder(),
  ),
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
),


    const SizedBox(height: 12),

   
    const SizedBox(height: 12),

const SizedBox(height: 12),
const Text("Select Sugar Type", style: TextStyle(fontWeight: FontWeight.bold)),
DropdownButton<SugarType>(
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
const SizedBox(height: 12),


   if (sugarNeededGrams != null)
  ListTile(
    title: const Text("Sugar Needed"),
    subtitle: Text("${sugarNeededGrams!.toStringAsFixed(1)} grams of ${selectedSugarType.name}"),
  ),
if (waterToAddLiters != null) ...[
  Row(
    children: [
      Expanded(
        child: ListTile(
          title: const Text("Dilution Needed"),
          subtitle: Text(
            "${getConvertedWaterAmount().toStringAsFixed(1)} ${selectedWaterUnit.label} of water",
          ),
        ),
      ),
      DropdownButton<VolumeUnit>(
        value: selectedWaterUnit,
        onChanged: (val) {
          if (val != null) {
            setState(() => selectedWaterUnit = val);
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
]


      
  ]
],
    
      

),
);
  }
}
