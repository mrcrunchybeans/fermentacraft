import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/models/recipe_model.dart';
import 'package:flutter_application_1/widgets/add_measurement_dialog.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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
import 'widgets/add_inventory_dialog.dart';
import '../models/unit_type.dart';
import 'models/shopping_list_item.dart';

class BatchDetailPage extends StatefulWidget {
  final dynamic batchKey;

  const BatchDetailPage({super.key, required this.batchKey});

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
  late TextEditingController _prepNotesController;

  String _finalYieldUnit = 'gal';
  int _tastingRating = 0;
  bool _isBrewModeEnabled = false;

  @override
  void initState() {
    super.initState();

    final box = Hive.box<BatchModel>('batches');
    final initialBatch = box.get(widget.batchKey);

    if (initialBatch == null) {
      _tabController = TabController(length: 4, vsync: this);
      _prepNotesController = TextEditingController();
      _fgController = TextEditingController();
      _tastingAromaController = TextEditingController();
      _tastingAppearanceController = TextEditingController();
      _tastingFlavorController = TextEditingController();
      _finalYieldController = TextEditingController();
      _finalNotesController = TextEditingController();
      return;
    }

    int initialTabIndex = 0;
    switch (initialBatch.status) {
      case 'Preparation':
        initialTabIndex = 1;
        break;
      case 'Fermenting':
        initialTabIndex = 2;
        break;
      case 'Completed':
        initialTabIndex = 3;
        break;
    }
    _tabController =
        TabController(length: 4, vsync: this, initialIndex: initialTabIndex);

    _prepNotesController =
        TextEditingController(text: initialBatch.prepNotes ?? '');
    _fgController =
        TextEditingController(text: initialBatch.fg?.toString() ?? '');
    _tastingRating = initialBatch.tastingRating ?? 0;
    _tastingAromaController =
        TextEditingController(text: initialBatch.tastingNotes?['aroma'] ?? '');
    _tastingAppearanceController = TextEditingController(
        text: initialBatch.tastingNotes?['appearance'] ?? '');
    _tastingFlavorController =
        TextEditingController(text: initialBatch.tastingNotes?['flavor'] ?? '');
    _finalYieldController =
        TextEditingController(text: initialBatch.finalYield?.toString() ?? '');
    _finalYieldUnit = initialBatch.finalYieldUnit ?? 'gal';
    _finalNotesController =
        TextEditingController(text: initialBatch.finalNotes ?? '');
  }

  @override
  void dispose() {
    if (_isBrewModeEnabled) {
      WakelockPlus.disable();
    }
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

  // FIX 1: All methods, including build(), now live inside the State class.
  
  void _toggleBrewMode() {
    setState(() {
      _isBrewModeEnabled = !_isBrewModeEnabled;
      if (_isBrewModeEnabled) {
        WakelockPlus.enable();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Brew Mode Enabled: Screen will stay on."),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        WakelockPlus.disable();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Brew Mode Disabled."),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _updateBatchStatus(BatchModel batch, String newStatus) {
    batch.status = newStatus;
    batch.save();

    int tabIndex = 0;
    switch (newStatus) {
      case 'Preparation':
        tabIndex = 1;
        break;
      case 'Fermenting':
        tabIndex = 2;
        break;
      case 'Completed':
        tabIndex = 3;
        break;
    }
    _tabController.animateTo(tabIndex);
  }

  Future<void> _showChangeStatusDialog(BatchModel batch) async {
    String currentStatus = batch.status;
    final newStatus = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Change Batch Status'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: ['Planning', 'Preparation', 'Fermenting', 'Completed']
                    .map((status) {
                  return RadioListTile<String>(
                    title: Text(status),
                    value: status,
                    groupValue: currentStatus,
                    onChanged: (String? value) {
                      if (value != null) {
                        setState(() {
                          currentStatus = value;
                        });
                      }
                    },
                  );
                }).toList(),
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Save'),
              onPressed: () => Navigator.of(context).pop(currentStatus),
            ),
          ],
        );
      },
    );

    if (newStatus != null && newStatus != batch.status) {
      _updateBatchStatus(batch, newStatus);
    }
  }

  Widget _buildStatusProgressionButton({
    required BatchModel batch,
    required String currentStatus,
    required String nextStatus,
    required String buttonText,
    IconData? icon,
  }) {
    if (batch.status != currentStatus) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Center(
        child: ElevatedButton.icon(
          icon: Icon(icon ?? Icons.arrow_forward_ios),
          label: Text(buttonText),
          onPressed: () => _updateBatchStatus(batch, nextStatus),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            textStyle: Theme.of(context).textTheme.titleMedium,
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }

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
                    batch.yeast = newYeast;
                    batch.save();
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
                Text('Recipe Summary',
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit Targets',
                  onPressed: () => _editBatchSummary(batch),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Text('Status: ', style: Theme.of(context).textTheme.titleMedium),
                Text(batch.status,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => _showChangeStatusDialog(batch),
                  child: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                'Target Volume: ${batch.batchVolume?.toStringAsFixed(1) ?? '—'} gal'),
            Text('Target OG: ${batch.plannedOg?.toStringAsFixed(3) ?? '—'}'),
            Text('Target ABV: ${batch.plannedAbv?.toStringAsFixed(1) ?? '—'}%'),
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
              batch.batchVolume = double.tryParse(volumeController.text);
              batch.plannedOg = double.tryParse(ogController.text);
              batch.plannedAbv = double.tryParse(abvController.text);
              batch.save();
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _handleDeleteMeasurement(BatchModel batch, Measurement measurement) {
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
                batch.measurements.remove(measurement);
                batch.save();
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

                batch.recipeId = newRecipe.id;
                batch.save();

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

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Batch synced from recipe')));
    }
  }

  Future<void> _addPlannedEventDialog(BatchModel batch) async {
    final newEvent = await showDialog<PlannedEvent>(
        context: context, builder: (_) => const AlertDialog(title: Text("Add Event (Not Implemented)")));
    if (newEvent != null) {
      batch.plannedEvents ??= [];
      batch.plannedEvents!.add(newEvent);
      batch.save();
    }
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
      batch.fermentationStages = updatedStages;
      batch.save();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<BatchModel>>(
      valueListenable: Hive.box<BatchModel>('batches').listenable(),
      builder: (context, box, _) {
        final batch = box.get(widget.batchKey);

        if (batch == null) {
          return Scaffold(
            appBar: AppBar(title: const Text("Batch Not Found")),
            body: const Center(
              child: Text("This batch may have been deleted."),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(batch.name),
            actions: [
              IconButton(
                icon: Icon(
                  _isBrewModeEnabled ? Icons.lightbulb : Icons.lightbulb_outline,
                  color: _isBrewModeEnabled ? Colors.amber : null,
                ),
                tooltip: 'Toggle Brew Mode',
                onPressed: _toggleBrewMode,
              ),
            ],
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
      },
    );
  }

  Widget _buildPlanningTab(BatchModel batch) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _recipeSummaryCard(batch),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.sync),
            label: const Text('Sync From Recipe'),
            onPressed: () => _showSyncFromRecipeDialog(batch),
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
                  // FIX 2: Added missing 'unitType' parameter.
                  unitType: UnitType.mass,
                  onAddToRecipe: (ingredient) {
                    batch.ingredients.add(ingredient);
                    batch.save();
                  },
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
                    batch.additives.add(additive);
                    batch.save();
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
            onPressed: () => _addPlannedEventDialog(batch),
          ),
          _buildStatusProgressionButton(
            batch: batch,
            currentStatus: 'Planning',
            nextStatus: 'Preparation',
            buttonText: 'Start Preparation',
          ),
        ],
      ),
    );
  }

  Widget _buildPreparationTab(BatchModel batch) {
    // Sync controller with the latest model state
    final currentPrepNotes = batch.prepNotes ?? '';
    if (_prepNotesController.text != currentPrepNotes) {
      _prepNotesController.text = currentPrepNotes;
      _prepNotesController.selection =
          TextSelection.fromPosition(TextPosition(offset: _prepNotesController.text.length));
    }

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
          _buildStatusProgressionButton(
            batch: batch,
            currentStatus: 'Preparation',
            nextStatus: 'Fermenting',
            buttonText: 'Start Fermenting',
          ),
        ],
      ),
    );
  }

  List<Widget> _buildInventoryChecklist(
      BatchModel batch, Box<InventoryItem> inventoryBox) {
    return [
      Card(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        child: ExpansionTile(
          title: const Text("Ingredients",
              style: TextStyle(fontWeight: FontWeight.bold)),
          initiallyExpanded: true,
          children: batch.ingredients.isEmpty
              ? [const ListTile(title: Text('No ingredients added.'))]
              : batch.ingredients
                  .asMap()
                  .entries
                  .map((entry) => _buildChecklistItem(
                        batch: batch,
                        itemData: entry.value,
                        inventoryBox: inventoryBox,
                        onChanged: (newValue) => _handleDeductionChange(
                          batch: batch,
                          itemType: 'ingredient',
                          item: entry.value,
                          index: entry.key,
                          newValue: newValue,
                          inventoryBox: inventoryBox,
                        ),
                      ))
                  .toList(),
        ),
      ),
      Card(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        child: ExpansionTile(
          title:
              const Text("Yeast", style: TextStyle(fontWeight: FontWeight.bold)),
          initiallyExpanded: true,
          children: batch.yeast == null
              ? [const ListTile(title: Text('No yeast added.'))]
              : [
                  _buildChecklistItem(
                    batch: batch,
                    itemData: batch.yeast!,
                    inventoryBox: inventoryBox,
                    onChanged: (newValue) => _handleDeductionChange(
                      batch: batch,
                      itemType: 'yeast',
                      item: batch.yeast!,
                      newValue: newValue,
                      inventoryBox: inventoryBox,
                    ),
                  )
                ],
        ),
      ),
      Card(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        child: ExpansionTile(
          title: const Text("Additives",
              style: TextStyle(fontWeight: FontWeight.bold)),
          initiallyExpanded: true,
          children: batch.additives.isEmpty
              ? [const ListTile(title: Text('No additives added.'))]
              : batch.additives
                  .asMap()
                  .entries
                  .map((entry) => _buildChecklistItem(
                        batch: batch,
                        itemData: entry.value,
                        inventoryBox: inventoryBox,
                        onChanged: (newValue) => _handleDeductionChange(
                          batch: batch,
                          itemType: 'additive',
                          item: entry.value,
                          index: entry.key,
                          newValue: newValue,
                          inventoryBox: inventoryBox,
                        ),
                      ))
                  .toList(),
        ),
      ),
    ];
  }

 Widget _buildChecklistItem({
    required BatchModel batch,
    required Map<String, dynamic> itemData,
    required Box<InventoryItem> inventoryBox,
    required Future<void> Function(bool) onChanged,
  }) {
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
    final sufficient = inStock >= amount;

    return Column(
      children: [
        ListTile(
          enabled: !shouldDeduct,
          title: Text(
            '$amount $unit $name',
            style: TextStyle(
              decoration:
                  shouldDeduct ? TextDecoration.lineThrough : TextDecoration.none,
              color: shouldDeduct ? Colors.grey : null,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.isNotEmpty) Text(note),
              if (inventoryItem != null)
                Row(
                  children: [
                    Text(
                      'In stock: ${inStock.toStringAsFixed(2)} $unit',
                      style: TextStyle(
                          color: sufficient ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      onPressed: () => _showQuickAddDialog(inventoryItem, unit),
                      tooltip: 'Quick-add to inventory',
                    ),
                    // This is the correct logic for the checklist warning icon
                    if (!sufficient && !shouldDeduct)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.warning, color: Colors.red, size: 18),
                      ),
                  ],
                )
              else
                Row(
                  children: [
                    Text(
                      'Not in Inventory',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.add_box_outlined, size: 20),
                      label: const Text('Create'),
                      onPressed: () =>
                          _showCreateInventoryItemDialog(name, unit),
                    )
                  ],
                ),
            ],
          ),
          trailing: (!sufficient && !shouldDeduct)
              ? ElevatedButton(
                  onPressed: () {
                    final shoppingBox =
                        Hive.box<ShoppingListItem>('shopping_list');
                    final amountNeeded = amount - inStock;

                    if (amountNeeded > 0) {
                      final newItem = ShoppingListItem(
                        name: name,
                        amount: amountNeeded,
                        unit: unit,
                        recipeName: batch.name,
                      );
                      shoppingBox.add(newItem);

                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'Added ${amountNeeded.toStringAsFixed(2)} $unit of "$name" to shopping list!'),
                        duration: const Duration(seconds: 2),
                      ));
                    }
                  },
                  child: const Icon(Icons.add_shopping_cart),
                )
              : null,
        ),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: CheckboxListTile(
            value: shouldDeduct,
            title: const Text('Deduct from Inventory'),
            onChanged: (val) => onChanged(val ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
  void _showQuickAddDialog(InventoryItem item, String unit) async {
    final TextEditingController controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Quick-add to ${item.name}'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Amount to add ($unit)',
            suffixText: unit,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value != null && value > 0) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (amount != null) {
      item.addPurchase(PurchaseTransaction(
        date: DateTime.now(),
        amount: amount,
        cost: item.costPerUnit ?? 0,
      ));
      item.save();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $amount $unit to ${item.name}')),
        );
      }
    }
  }

  void _showCreateInventoryItemDialog(String name, String unit) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AddInventoryDialog(initialData: {'name': name, 'unit': unit});
      },
    );
  }

  Future<void> _handleDeductionChange({
    required BatchModel batch,
    required String itemType,
    required Map<String, dynamic> item,
    int index = -1,
    required bool newValue,
    required Box<InventoryItem> inventoryBox,
  }) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final name = item['name'] ?? 'Unnamed';
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final unit = item['unit'] ?? '';
    final inventoryItem = inventoryBox.values
        .cast<InventoryItem?>()
        .firstWhere((i) => i?.name.toLowerCase() == name.toLowerCase(),
            orElse: () => null);

    if (inventoryItem == null) {
      if (!mounted) return;
      scaffoldMessenger
          .showSnackBar(SnackBar(content: Text('No inventory found for "$name"')));
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

    if (!mounted) return;

    switch (itemType) {
      case 'ingredient':
        batch.ingredients[index]['deductFromInventory'] = newValue;
        break;
      case 'yeast':
        batch.yeast!['deductFromInventory'] = newValue;
        break;
      case 'additive':
        batch.additives[index]['deductFromInventory'] = newValue;
        break;
    }

    if (newValue) {
      inventoryItem.deduct(amount);
      scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Deducted $amount $unit from $name')));
    } else {
      inventoryItem.addPurchase(PurchaseTransaction(
        date: DateTime.now(),
        amount: amount,
        cost: inventoryItem.costPerUnit ?? 0,
      ));
      scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Restored $amount $unit to $name')));
    }
    batch.save();
    inventoryItem.save();
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
                  batch.measurements.add(newMeasurement);
                  batch.save();
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
              final originalIndex = batch.measurements
                  .indexWhere((m) => m.timestamp == measurementToEdit.timestamp);
              if (originalIndex != -1) {
                batch.measurements[originalIndex] = updatedMeasurement;
                batch.save();
              }
            }
          },
          onDeleteMeasurement: (m) => _handleDeleteMeasurement(batch, m),
          onManageStages: () => _manageStages(batch),
        ),
        _buildStatusProgressionButton(
          batch: batch,
          currentStatus: 'Fermenting',
          nextStatus: 'Completed',
          buttonText: 'Mark as Completed',
          icon: Icons.check_circle_outline,
        ),
      ],
    );
  }

  Widget _buildCompletedTab(BatchModel batch) {
    // Sync local state with the model from the builder
    _tastingRating = batch.tastingRating ?? 0;
    _finalYieldUnit = batch.finalYieldUnit ?? 'gal';

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
    // Sync controller with the latest model state
    final currentFgText = batch.fg?.toString() ?? '';
    if (_fgController.text != currentFgText) {
      _fgController.text = currentFgText;
      _fgController.selection = TextSelection.fromPosition(
          TextPosition(offset: _fgController.text.length));
    }

    final actualAbv = (batch.og != null && batch.fg != null)
        ? calculateABV(batch.og!, batch.fg!)
        : null;
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
                      batch.fg = double.tryParse(value);
                      batch.save();
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
    // Sync controllers with the latest model state
    final currentAroma = batch.tastingNotes?['aroma'] ?? '';
    if (_tastingAromaController.text != currentAroma) {
      _tastingAromaController.text = currentAroma;
      _tastingAromaController.selection = TextSelection.fromPosition(
          TextPosition(offset: _tastingAromaController.text.length));
    }
    final currentAppearance = batch.tastingNotes?['appearance'] ?? '';
    if (_tastingAppearanceController.text != currentAppearance) {
      _tastingAppearanceController.text = currentAppearance;
      _tastingAppearanceController.selection = TextSelection.fromPosition(
          TextPosition(offset: _tastingAppearanceController.text.length));
    }
    final currentFlavor = batch.tastingNotes?['flavor'] ?? '';
    if (_tastingFlavorController.text != currentFlavor) {
      _tastingFlavorController.text = currentFlavor;
      _tastingFlavorController.selection = TextSelection.fromPosition(
          TextPosition(offset: _tastingFlavorController.text.length));
    }

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
    // Sync controller with the latest model state
    final currentYield = batch.finalYield?.toString() ?? '';
    if (_finalYieldController.text != currentYield) {
      _finalYieldController.text = currentYield;
      _finalYieldController.selection = TextSelection.fromPosition(
          TextPosition(offset: _finalYieldController.text.length));
    }

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
              batch.packagingDate = date;
              batch.save();
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
              batch.packagingMethod = value;
              batch.save();
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
              items: {
                'gal',
                'L',
                '12oz bottle',
                '16oz bottle',
                '32oz growler',
                '5gal keg'
              }.map((unit) {
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
    // Sync controller with the latest model state
    final currentNotes = batch.finalNotes ?? '';
    if (_finalNotesController.text != currentNotes) {
      _finalNotesController.text = currentNotes;
      _finalNotesController.selection = TextSelection.fromPosition(
          TextPosition(offset: _finalNotesController.text.length));
    }

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
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Batch cloned!')));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPreparationNotesEditor(BatchModel batch) {
    // Sync controller with the latest model state
    final currentPrepNotes = batch.prepNotes ?? '';
    if (_prepNotesController.text != currentPrepNotes) {
      _prepNotesController.text = currentPrepNotes;
      _prepNotesController.selection = TextSelection.fromPosition(
          TextPosition(offset: _prepNotesController.text.length));
    }

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
            batch.save();
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