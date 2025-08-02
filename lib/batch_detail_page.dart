import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/recipe_model.dart';
import 'package:flutter_application_1/widgets/add_measurement_dialog.dart';
import 'package:hive/hive.dart';
import '../models/batch_model.dart';
import '../models/planned_event.dart';
import 'models/inventory_item.dart';
import 'models/purchase_transaction.dart';
import 'widgets/add_ingredient_dialog.dart';
import '../widgets/add_additive_dialog.dart';
import '../utils/batch_utils.dart';
import '../widgets/add_yeast_dialog.dart';
import '../widgets/fermentation_chart.dart';
import '../widgets/manage_stages_dialog.dart';
import '../models/fermentation_stage.dart';
import '../models/measurement.dart';

class BatchDetailPage extends StatefulWidget {
  final BatchModel batch;

  const BatchDetailPage({super.key, required this.batch});

  @override
  State<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<BatchDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _fgController;
  late TextEditingController _tastingAromaController;
  late TextEditingController _tastingAppearanceController;
  late TextEditingController _tastingFlavorController;
  late TextEditingController _finalYieldController;
  late TextEditingController _finalNotesController;
  String _finalYieldUnit = 'gal';
  int _tastingRating = 0;
  late TextEditingController _prepNotesController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _prepNotesController =
        TextEditingController(text: widget.batch.prepNotes ?? '');
    _fgController = TextEditingController(text: widget.batch.fg?.toString() ?? '');
    _tastingRating = widget.batch.tastingRating ?? 0;
    _tastingAromaController =
        TextEditingController(text: widget.batch.tastingNotes?['aroma'] ?? '');
    _tastingAppearanceController = TextEditingController(
        text: widget.batch.tastingNotes?['appearance'] ?? '');
    _tastingFlavorController =
        TextEditingController(text: widget.batch.tastingNotes?['flavor'] ?? '');
    _finalYieldController =
        TextEditingController(text: widget.batch.finalYield?.toString() ?? '');
    _finalYieldUnit = widget.batch.finalYieldUnit ?? 'gal';
    _finalNotesController =
        TextEditingController(text: widget.batch.finalNotes ?? '');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _prepNotesController.dispose();
    _fgController.dispose();
    _tastingAromaController.dispose();
    _tastingAppearanceController.dispose();
    _tastingFlavorController.dispose();
    _finalYieldController.dispose();
    _finalNotesController.dispose();
    super.dispose();
  }

  // --- UI Building Helper Methods ---

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }

  Widget _yeastSection(BatchModel batch, {bool showEditButton = true}) {
    final yeast =
        batch.yeast != null ? Map<String, dynamic>.from(batch.yeast!) : null;
    final yeastName = yeast?['name'] ?? 'Unnamed Yeast';
    final yeastAmount = (yeast?['amount'] as num?)?.toDouble() ?? 0.0;
    final yeastUnit = yeast?['unit'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Yeast'),
        if (yeast == null)
          const Text('No yeast selected.')
        else
          ListTile(
            leading: const Icon(Icons.bubble_chart),
            title: Text('$yeastAmount $yeastUnit $yeastName'),
          ),
        if (showEditButton) ...[
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.edit),
            label: Text(yeast == null ? 'Add Yeast' : 'Edit Yeast'),
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (_) => AddYeastDialog(
                  existing: batch.yeast,
                  onAdd: (newYeast) {
                    setState(() {
                      batch.yeast = newYeast;
                      batch.save();
                    });
                  },
                ),
              );
            },
          ),
        ]
      ],
    );
  }

  Widget _additivesList(BatchModel batch) {
    if (batch.additives.isEmpty) return const Text('No additives added.');
    return Column(
      children: batch.additives.map((rawAdditive) {
        final additive = Map<String, dynamic>.from(rawAdditive);
        final name = additive['name'] ?? 'Unnamed';
        final amount = additive['amount']?.toString() ?? '?';
        final unit = additive['unit'] ?? '';
        final note = additive['note'] ?? '';
        return ListTile(
          leading: const Icon(Icons.science),
          title: Text('$amount $unit $name'),
          subtitle: note.isNotEmpty ? Text(note) : null,
        );
      }).toList(),
    );
  }

  Widget _ingredientsList(BatchModel batch) {
    if (batch.ingredients.isEmpty) return const Text('No ingredients added.');
    final inventoryBox = Hive.box<InventoryItem>('inventory');
    return Column(
      children: batch.ingredients.map((ingredientMap) {
        final ingredient = Map<String, dynamic>.from(ingredientMap);
        final name = ingredient['name'] ?? 'Unnamed';
        final amount = (ingredient['amount'] as num?)?.toDouble() ?? 0;
        final unit = ingredient['unit'] ?? '';
        final note = ingredient['note'] ?? '';
        final inventoryItem = inventoryBox.values
            .cast<InventoryItem?>()
            .firstWhere(
                (item) => item?.name.toLowerCase() == name.toLowerCase(),
                orElse: () => null);
        final inStock = inventoryItem?.amountInStock;
        final sufficient = (inStock ?? 0) >= amount;
        return ListTile(
          title: Text('$amount $unit $name'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.isNotEmpty) Text(note),
              if (inventoryItem != null)
                Row(
                  children: [
                    Text(
                      'In stock: ${inStock?.toStringAsFixed(2) ?? 'N/A'} $unit',
                      style: TextStyle(
                        color: sufficient ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (!sufficient)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child:
                            Icon(Icons.warning, color: Colors.red, size: 18),
                      ),
                  ],
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _recipeSummaryCard(BatchModel batch) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Status & Targets',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editBatchSummary(batch),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Status: ${batch.status}'),
            Text(
                'Target Volume: ${batch.batchVolume?.toStringAsFixed(1) ?? '—'} gal'),
            Text('Target OG: ${batch.plannedOg?.toStringAsFixed(3) ?? '—'}'),
            Text(
                'Target ABV: ${batch.plannedAbv?.toStringAsFixed(1) ?? '—'}%'),
          ],
        ),
      ),
    );
  }

  Widget _fermentationStagesList(BatchModel batch) {
    if (batch.safeFermentationStages.isEmpty) {
      return const Text('No fermentation stages planned.');
    }
    return Column(
      children: batch.safeFermentationStages.map((stage) {
        final name = stage.name;
        final temp = stage.targetTempC?.toStringAsFixed(1) ?? '—';
        final duration = stage.durationDays.toString();
        return ListTile(
          leading: const Icon(Icons.thermostat),
          title: Text(name),
          subtitle: Text('Temp: $temp°C, Duration: $duration days'),
        );
      }).toList(),
    );
  }

  Widget _plannedEventsList(BatchModel batch) {
    if (batch.safePlannedEvents.isEmpty) {
      return const Text('No planned events.');
    }
    return Column(
      children: batch.safePlannedEvents.map((event) {
        return ListTile(
          leading: const Icon(Icons.event_note),
          title: Text(event.title),
          subtitle: Text(
              '${event.date.toLocal().toString().split(' ')[0]}'
              '${event.notes != null ? '\nNotes: ${event.notes}' : ''}'),
          isThreeLine: event.notes != null,
        );
      }).toList(),
    );
  }

  // --- Dialog and Logic Methods ---

  Future<bool> _confirmInventoryDeduction({
    required BuildContext context,
    required String name,
    required double inStock,
    required double requested,
    required String unit,
  }) async {
    if (inStock >= requested) return true;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Not Enough Inventory'),
            content: Text(
              'Only ${inStock.toStringAsFixed(2)} $unit of "$name" in stock, but trying to deduct $requested.\n\nProceed anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Proceed'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _editBatchSummary(BatchModel batch) {
    final volumeController =
        TextEditingController(text: batch.batchVolume?.toString() ?? '');
    final ogController =
        TextEditingController(text: batch.plannedOg?.toString() ?? '');
    final abvController =
        TextEditingController(text: batch.plannedAbv?.toString() ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Recipe Summary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: volumeController,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Target Volume (gal)'),
            ),
            TextField(
              controller: ogController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Target OG'),
            ),
            TextField(
              controller: abvController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Target ABV (%)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                batch.batchVolume = double.tryParse(volumeController.text);
                batch.plannedOg = double.tryParse(ogController.text);
                batch.plannedAbv = double.tryParse(abvController.text);
                batch.save();
              });
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _handleDeleteMeasurement(Measurement measurement) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text(
              'Are you sure you want to delete the measurement from ${measurement.timestamp.toLocal()}?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  widget.batch.measurements.remove(measurement);
                  widget.batch.save();
                });
              },
            ),
          ],
        );
      },
    );
  }

  void _showSyncFromRecipeDialog(BatchModel batch) async {
    bool syncYeast = true;
    bool syncIngredients = true;
    bool syncAdditives = true;
    bool syncStages = true;
    bool syncTargets = true;
    final recipeBox = Hive.box<RecipeModel>('recipes');
    List<RecipeModel> allRecipes = recipeBox.values.toList();
    if (!mounted) return;
    RecipeModel? selectedRecipe =
        (batch.recipeId.isNotEmpty) ? recipeBox.get(batch.recipeId) : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Sync From Recipe'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<RecipeModel>(
                  hint: const Text("Choose a recipe to sync from"),
                  isExpanded: true,
                  value: selectedRecipe,
                  items: allRecipes.map((recipe) {
                    return DropdownMenuItem<RecipeModel>(
                      value: recipe,
                      child: Text(recipe.name),
                    );
                  }).toList(),
                  onChanged: (RecipeModel? newValue) {
                    if (newValue != null) {
                      setState(() {
                        selectedRecipe = newValue;
                        batch.recipeId = newValue.id;
                      });
                    }
                  },
                ),
                if (selectedRecipe != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear'),
                      onPressed: () {
                        setState(() {
                          selectedRecipe = null;
                          batch.recipeId = '';
                        });
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('This will overwrite selected fields in the batch:'),
                const SizedBox(height: 12),
                CheckboxListTile(
                    value: syncYeast,
                    onChanged: (val) => setState(() => syncYeast = val ?? true),
                    title: const Text("Yeast")),
                CheckboxListTile(
                    value: syncIngredients,
                    onChanged: (val) =>
                        setState(() => syncIngredients = val ?? true),
                    title: const Text("Ingredients")),
                CheckboxListTile(
                    value: syncAdditives,
                    onChanged: (val) =>
                        setState(() => syncAdditives = val ?? true),
                    title: const Text("Additives")),
                CheckboxListTile(
                    value: syncStages,
                    onChanged: (val) =>
                        setState(() => syncStages = val ?? true),
                    title: const Text("Fermentation Stages")),
                CheckboxListTile(
                    value: syncTargets,
                    onChanged: (val) =>
                        setState(() => syncTargets = val ?? true),
                    title: const Text("Targets (Volume, OG, ABV)")),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(dialogContext);
                final newRecipe = RecipeModel(
                  name: batch.name,
                  createdAt: DateTime.now(),
                  tags: batch.tags,
                  og: batch.og,
                  fg: batch.fg,
                  abv: batch.abv,
                  additives: batch.additives,
                  ingredients: batch.ingredients,
                  fermentationStages: batch.safeFermentationStages
                      .map((e) => e.toJson())
                      .toList(),
                  yeast: batch.yeast != null ? [batch.yeast!] : [],
                  notes: batch.notes ?? '',
                  batchVolume: batch.batchVolume,
                  plannedOg: batch.plannedOg,
                  plannedAbv: batch.plannedAbv,
                );

                await recipeBox.put(newRecipe.id, newRecipe);

                if (!mounted) return;

                this.setState(() {
                  batch.recipeId = newRecipe.id;
                  batch.save();
                });

                navigator.pop();
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Recipe saved and linked')),
                );
              },
              child: const Text('Save as New Recipe'),
            ),
            ElevatedButton(
              onPressed: selectedRecipe == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Sync'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final recipe = selectedRecipe;
    if (recipe == null) return;
    widget.batch.save();

    setState(() {
      if (syncYeast) {
        batch.yeast = recipe.yeast.isNotEmpty
            ? Map<String, dynamic>.from(recipe.yeast.first)
            : null;
      }
      if (syncIngredients) {
        batch.ingredients =
            List<Map<String, dynamic>>.from(recipe.ingredients);
      }
      if (syncAdditives) {
        batch.additives = List<Map<String, dynamic>>.from(recipe.additives);
      }
      if (syncStages) {
        batch.fermentationStages = recipe.fermentationStages
            .map((stageMap) =>
                FermentationStage.fromJson(Map<String, dynamic>.from(stageMap)))
            .toList();
        if (batch.fermentationStages.isNotEmpty) {
          DateTime nextStageStartDate = batch.startDate;
          for (var stage in batch.fermentationStages) {
            stage.startDate = nextStageStartDate;
            nextStageStartDate =
                nextStageStartDate.add(Duration(days: stage.durationDays));
          }
        }
      }
      if (syncTargets) {
        batch.batchVolume = recipe.batchVolume;
        batch.plannedOg = recipe.plannedOg;
        batch.plannedAbv = recipe.plannedAbv;
      }
      batch.save();
    });

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Batch synced from recipe')));
    }
  }

  Future<PlannedEvent?> _addPlannedEventDialog() async {
    return null;
  }

  void _manageStages(BatchModel batch) async {
    final updatedStages = await showModalBottomSheet<List<FermentationStage>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ManageStagesDialog(
        initialStages: batch.safeFermentationStages,
      ),
    );
    if (updatedStages != null) {
      setState(() {
        batch.fermentationStages = updatedStages;
        batch.save();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    return Scaffold(
      appBar: AppBar(
        title: Text(batch.name),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Planning'),
            Tab(text: 'Preparation'),
            Tab(text: 'Fermenting'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPlanningTab(batch),
          _buildPreparationTab(batch),
          _buildFermentingTab(batch),
          _buildCompletedTab(batch),
        ],
      ),
    );
  }

  Widget _buildPlanningTab(BatchModel batch) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Recipe Summary'),
          _recipeSummaryCard(batch),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.sync),
            label: const Text('Sync From Recipe'),
            onPressed: () => _showSyncFromRecipeDialog(widget.batch),
          ),
          _sectionTitle('Ingredients'),
          _ingredientsList(batch),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Ingredient'),
            onPressed: () async {
              await showDialog<void>(
                context: context,
                builder: (_) => AddIngredientDialog(
                  onAddToRecipe: (ingredient) {
                    setState(() {
                      batch.ingredients.add(ingredient);
                      batch.save();
                    });
                  },
                  onAddToInventory: (_) {},
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _yeastSection(batch),
          const SizedBox(height: 16),
          _sectionTitle('Additives'),
          _additivesList(batch),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Additive'),
            onPressed: () async {
              final estimatedPH = estimateMustPH(batch);
              final volume = batch.batchVolume ?? 5;
              await showDialog<void>(
                context: context,
                builder: (_) => AddAdditiveDialog(
                  mustPH: estimatedPH,
                  volume: volume,
                  onAdd: (additive) {
                    setState(() {
                      batch.additives.add(additive);
                      batch.save();
                    });
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _sectionTitle('Fermentation Profile'),
          _fermentationStagesList(batch),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Manage Stages'),
            onPressed: () => _manageStages(batch),
          ),
          const SizedBox(height: 16),
          _sectionTitle('Planned Events'),
          _plannedEventsList(batch),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Planned Event'),
            onPressed: () async {
              final newEvent = await _addPlannedEventDialog();
              if (newEvent != null) {
                setState(() {
                  batch.plannedEvents ??= [];
                  batch.plannedEvents!.add(newEvent);
                  batch.save();
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPreparationTab(BatchModel batch) {
    final inventoryBox = Hive.box<InventoryItem>('inventory');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Inventory Checklist'),
          ..._buildInventoryChecklist(batch, inventoryBox),
          const SizedBox(height: 16),
          _sectionTitle('Preparation Notes'),
          _buildPreparationNotesEditor(batch),
        ],
      ),
    );
  }

  List<Widget> _buildInventoryChecklist(
      BatchModel batch, Box<InventoryItem> inventoryBox) {
    final widgets = <Widget>[];

    // --- HELPER WIDGET BUILDERS ---

    Widget buildItem(
        {required Map<String, dynamic> itemData,
        required int index,
        required Function(bool) onDeductChanged}) {
      final name = itemData['name'] ?? 'Unnamed';
      final amount = (itemData['amount'] as num?)?.toDouble() ?? 0;
      final unit = itemData['unit'] ?? '';
      final note = itemData['note'] ?? '';
      final shouldDeduct = itemData['deductFromInventory'] ?? false;
      final inventoryItem = inventoryBox.values
          .cast<InventoryItem?>()
          .firstWhere((item) => item?.name.toLowerCase() == name.toLowerCase(),
              orElse: () => null);
      final inStock = inventoryItem?.amountInStock ?? 0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text('$amount $unit $name'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.isNotEmpty) Text(note),
                Row(
                  children: [
                    Text(
                      'In stock: ${inStock.toStringAsFixed(2)} $unit',
                      style: TextStyle(
                          color: inStock >= amount ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w500),
                    ),
                    if (inStock < amount)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child:
                            Icon(Icons.warning, color: Colors.red, size: 18),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: CheckboxListTile(
              value: shouldDeduct,
              title: const Text('Deduct from Inventory'),
              onChanged: (val) => onDeductChanged(val ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const Divider(),
        ],
      );
    }

    // --- BUILD THE LIST ---

    widgets.add(const Text("Ingredients", style: TextStyle(fontWeight: FontWeight.bold)));
    if (batch.ingredients.isEmpty) {
      widgets.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text('No ingredients added.'),
      ));
    } else {
      widgets.addAll(
        batch.ingredients.asMap().entries.map(
          (entry) {
            final index = entry.key;
            final ingredient = entry.value;
            return buildItem(
              itemData: ingredient,
              index: index,
              onDeductChanged: (newValue) async {
                final name = ingredient['name'] ?? 'Unnamed';
                final amount = (ingredient['amount'] as num?)?.toDouble() ?? 0;
                final unit = ingredient['unit'] ?? '';
                final inventoryItem = inventoryBox.values.cast<InventoryItem?>().firstWhere(
                    (item) => item?.name.toLowerCase() == name.toLowerCase(),
                    orElse: () => null);

                if (inventoryItem == null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No inventory found for "$name"')));
                  return;
                }

                if (newValue) {
                  final confirmed = await _confirmInventoryDeduction(
                    context: context,
                    name: name,
                    inStock: inventoryItem.amountInStock,
                    requested: amount,
                    unit: unit,
                  );
                  if (!confirmed) return;
                }

                setState(() {
                  batch.ingredients[index]['deductFromInventory'] = newValue;
                  if (newValue) {
                    inventoryItem.deduct(amount);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deducted $amount $unit from $name')));
                  } else {
                    inventoryItem.addPurchase(PurchaseTransaction(
                        date: DateTime.now(),
                        amount: amount,
                        cost: inventoryItem.costPerUnit ?? 0));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restored $amount $unit to $name')));
                  }
                  batch.save();
                  inventoryItem.save();
                });
              },
            );
          },
        ),
      );
    }

    widgets.add(const SizedBox(height: 16));
    widgets.add(const Text("Yeast", style: TextStyle(fontWeight: FontWeight.bold)));
    if (batch.yeast == null) {
      widgets.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text('No yeast added.'),
      ));
    } else {
      widgets.add(
        buildItem(
          itemData: batch.yeast!,
          index: -1, // Index isn't needed for a single item
          onDeductChanged: (newValue) async {
            final yeast = batch.yeast!;
            final name = yeast['name'] ?? 'Unnamed Yeast';
            final amount = (yeast['amount'] as num?)?.toDouble() ?? 0;
            final unit = yeast['unit'] ?? '';
            final inventoryItem = inventoryBox.values.cast<InventoryItem?>().firstWhere(
                (item) => item?.name.toLowerCase() == name.toLowerCase(),
                orElse: () => null);
            
            if (inventoryItem == null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No inventory found for "$name"')));
                return;
            }

            if (newValue) {
                final confirmed = await _confirmInventoryDeduction(
                context: context,
                name: name,
                inStock: inventoryItem.amountInStock,
                requested: amount,
                unit: unit,
                );
                if (!confirmed) return;
            }
            
            setState(() {
                batch.yeast!['deductFromInventory'] = newValue;
                if (newValue) {
                inventoryItem.deduct(amount);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deducted $amount $unit from $name')));
                } else {
                inventoryItem.addPurchase(PurchaseTransaction(
                    date: DateTime.now(),
                    amount: amount,
                    cost: inventoryItem.costPerUnit ?? 0,
                ));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restored $amount $unit to $name')));
                }
                inventoryItem.save();
                batch.save();
            });
          },
        ),
      );
    }

    widgets.add(const SizedBox(height: 16));
    widgets.add(const Text("Additives", style: TextStyle(fontWeight: FontWeight.bold)));
    if (batch.additives.isEmpty) {
      widgets.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text('No additives added.'),
      ));
    } else {
      widgets.addAll(
        batch.additives.asMap().entries.map(
          (entry) {
            final index = entry.key;
            final additive = entry.value;
            return buildItem(
              itemData: additive,
              index: index,
              onDeductChanged: (newValue) async {
                final name = additive['name'] ?? 'Unnamed';
                final amount = (additive['amount'] as num?)?.toDouble() ?? 0;
                final unit = additive['unit'] ?? '';
                final inventoryItem = inventoryBox.values.cast<InventoryItem?>().firstWhere(
                    (item) => item?.name.toLowerCase() == name.toLowerCase(),
                    orElse: () => null);

                if (inventoryItem == null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No inventory found for "$name"')));
                  return;
                }

                if (newValue) {
                  final confirmed = await _confirmInventoryDeduction(
                    context: context,
                    name: name,
                    inStock: inventoryItem.amountInStock,
                    requested: amount,
                    unit: unit,
                  );
                  if (!confirmed) return;
                }

                setState(() {
                  batch.additives[index]['deductFromInventory'] = newValue;
                  if (newValue) {
                    inventoryItem.deduct(amount);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deducted $amount $unit from $name')));
                  } else {
                    inventoryItem.addPurchase(PurchaseTransaction(
                        date: DateTime.now(),
                        amount: amount,
                        cost: inventoryItem.costPerUnit ?? 0));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restored $amount $unit to $name')));
                  }
                  batch.save();
                  inventoryItem.save();
                });
              },
            );
          },
        ),
      );
    }

    return widgets;
  }

  Widget _buildFermentingTab(BatchModel batch) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Fermentation Progress',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Measurement'),
              onPressed: () async {
                final sortedMeasurements = batch.measurements.toList()
                  ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
                final newMeasurement = await showDialog<Measurement>(
                    context: context,
                    builder: (_) => AddMeasurementDialog(
                          previousMeasurement: sortedMeasurements.isNotEmpty
                              ? sortedMeasurements.last
                              : null,
                          firstMeasurementDate: sortedMeasurements.isNotEmpty
                              ? sortedMeasurements.first.timestamp
                              : null,
                        ));
                if (newMeasurement != null) {
                  setState(() {
                    batch.measurements.add(newMeasurement);
                    batch.save();
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        FermentationChartWidget(
          measurements: batch.measurements,
          stages: batch.safeFermentationStages,
          onEditMeasurement: (measurementToEdit) async {
            final sortedMeasurements = batch.measurements.toList()
              ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
            final index = sortedMeasurements
                .indexWhere((m) => m.timestamp == measurementToEdit.timestamp);
            final updatedMeasurement = await showDialog<Measurement>(
              context: context,
              builder: (_) => AddMeasurementDialog(
                existingMeasurement: measurementToEdit,
                previousMeasurement:
                    (index > 0) ? sortedMeasurements[index - 1] : null,
                firstMeasurementDate: sortedMeasurements.isNotEmpty
                    ? sortedMeasurements.first.timestamp
                    : null,
              ),
            );
            if (updatedMeasurement != null) {
              setState(() {
                final originalIndex = batch.measurements.indexWhere(
                    (m) => m.timestamp == measurementToEdit.timestamp);
                if (originalIndex != -1) {
                  batch.measurements[originalIndex] = updatedMeasurement;
                  batch.save();
                }
              });
            }
          },
          onDeleteMeasurement: _handleDeleteMeasurement,
          onManageStages: () => _manageStages(batch),
        ),
      ],
    );
  }

  Widget _buildCompletedTab(BatchModel batch) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFinalStatsCard(batch),
          _sectionTitle('Tasting Notes'),
          _buildTastingNotesSection(batch),
          _sectionTitle('Packaging & Yield'),
          _buildPackagingLogSection(batch),
          _sectionTitle('Lessons Learned'),
          _buildLessonsLearnedSection(batch),
          _sectionTitle('Actions'),
          _buildCompletedActions(batch),
        ],
      ),
    );
  }

  Widget _buildFinalStatsCard(BatchModel batch) {
    final actualAbv =
        (batch.og != null && batch.fg != null) ? calculateABV(batch.og!, batch.fg!) : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Final Stats',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Final Gravity (FG)')),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _fgController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(hintText: 'e.g., 1.010'),
                    onChanged: (value) {
                      setState(() {
                        batch.fg = double.tryParse(value);
                        batch.save();
                      });
                    },
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'OG: '),
              TextSpan(
                  text: batch.og?.toStringAsFixed(3) ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(
                  text:
                      ' (Target: ${batch.plannedOg?.toStringAsFixed(3) ?? '—'})',
                  style: const TextStyle(color: Colors.grey)),
            ])),
            const SizedBox(height: 4),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'ABV: '),
              TextSpan(
                  text: '${actualAbv?.toStringAsFixed(2) ?? '—'}%',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(
                  text:
                      ' (Target: ${batch.plannedAbv?.toStringAsFixed(1) ?? '—'}%)',
                  style: const TextStyle(color: Colors.grey)),
            ])),
          ],
        ),
      ),
    );
  }

  Widget _buildTastingNotesSection(BatchModel batch) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Overall Rating'),
            Row(
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    index < _tastingRating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                  ),
                  onPressed: () {
                    setState(() {
                      _tastingRating = index + 1;
                      batch.tastingRating = _tastingRating;
                      batch.save();
                    });
                  },
                );
              }),
            ),
          ],
        ),
        TextField(
            controller: _tastingAromaController,
            decoration: const InputDecoration(labelText: 'Aroma'),
            onChanged: (v) {
              batch.tastingNotes ??= {};
              batch.tastingNotes!['aroma'] = v;
              batch.save();
            }),
        TextField(
            controller: _tastingAppearanceController,
            decoration: const InputDecoration(labelText: 'Appearance'),
            onChanged: (v) {
              batch.tastingNotes ??= {};
              batch.tastingNotes!['appearance'] = v;
              batch.save();
            }),
        TextField(
            controller: _tastingFlavorController,
            decoration: const InputDecoration(labelText: 'Flavor & Mouthfeel'),
            onChanged: (v) {
              batch.tastingNotes ??= {};
              batch.tastingNotes!['flavor'] = v;
              batch.save();
            }),
      ],
    );
  }

  Widget _buildPackagingLogSection(BatchModel batch) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.calendar_today),
          title: const Text('Packaging Date'),
          subtitle: Text(
              batch.packagingDate?.toLocal().toString().split(' ')[0] ??
                  'Not set'),
          onTap: () async {
            final date = await showDatePicker(
                context: context,
                initialDate: batch.packagingDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100));
            if (date != null) {
              setState(() {
                batch.packagingDate = date;
                batch.save();
              });
            }
          },
        ),
        DropdownButtonFormField<String>(
          value: batch.packagingMethod,
          decoration: const InputDecoration(labelText: 'Packaging Method'),
          items: ['Bottled', 'Kegged', 'Aged in Secondary']
              .map((method) =>
                  DropdownMenuItem(value: method, child: Text(method)))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                batch.packagingMethod = value;
                batch.save();
              });
            }
          },
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _finalYieldController,
                decoration: const InputDecoration(labelText: 'Final Yield'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) {
                  batch.finalYield = double.tryParse(value);
                  batch.save();
                },
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _finalYieldUnit,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _finalYieldUnit = value;
                    batch.finalYieldUnit = value;
                    batch.save();
                  });
                }
              },
              items: [
                'gal',
                'L',
                '12oz bottle',
                '16oz bottle',
                '32oz growler'
              ].map((unit) {
                return DropdownMenuItem<String>(
                  value: unit,
                  child: Text(unit),
                );
              }).toList(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLessonsLearnedSection(BatchModel batch) {
    return TextField(
      controller: _finalNotesController,
      maxLines: 5,
      decoration: const InputDecoration(
        labelText: 'Final Thoughts & Improvements',
        hintText: 'What would you do differently next time? What went well?',
        border: OutlineInputBorder(),
      ),
      onChanged: (value) {
        batch.finalNotes = value;
        batch.save();
      },
    );
  }

  Widget _buildCompletedActions(BatchModel batch) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.save_alt),
            label: const Text('Save as Recipe'),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved as new recipe!')));
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Clone to New Batch'),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Batch cloned!')));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPreparationNotesEditor(BatchModel batch) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _prepNotesController,
          maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Add notes for your preparation steps...',
          ),
          onChanged: (value) {
            batch.prepNotes = value;
            widget.batch.save();
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Tip: Track things like sanitizing, yeast hydration, or juice prep here.',
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}