import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/widgets/add_measurement_dialog.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/batch_model.dart';
import '../models/planned_event.dart';
import 'models/inventory_item.dart';
import 'models/purchase_transaction.dart';
import 'utils/unit_conversion.dart';
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
import 'package:intl/intl.dart';
import 'models/shopping_list_item.dart';
import 'widgets/planned_event_dialog.dart';

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

Future<void> _editIngredientDialog(BatchModel batch, int index) async {
  final existing = batch.ingredients[index];
  final correctedMap = Map<String, dynamic>.from(existing);

  if (correctedMap['purchaseDate'] is String) {
    correctedMap['purchaseDate'] = DateTime.tryParse(correctedMap['purchaseDate']);
  }
  if (correctedMap['expirationDate'] is String) {
    correctedMap['expirationDate'] = DateTime.tryParse(correctedMap['expirationDate']);
  }

  await showDialog(
    context: context,
    builder: (_) => AddIngredientDialog(
      unitType: inferUnitType(correctedMap['unit'] ?? 'g'),
      existing: correctedMap,
      onAddToRecipe: (updated) {
        batch.ingredients[index] = updated;
        batch.save();
      },
    ),
  );
}

  Future<void> _editAdditiveDialog(BatchModel batch, int index) async {
    final existing = batch.additives[index];
    await showDialog(
      context: context,
      builder: (_) => AddAdditiveDialog(
        mustPH: 3.4,
        volume: batch.batchVolume ?? 5.0,
        existing: Map<String, dynamic>.from(existing),
        onAdd: (updated) {
          batch.additives[index] = updated;
          batch.save();
        },
      ),
    );
  }

  Future<void> _editYeastDialog(BatchModel batch, int index) async {
    final existing = batch.yeast[index];
    await showDialog(
      context: context,
      builder: (_) => AddYeastDialog(
        existing: Map<String, dynamic>.from(existing),
        onAdd: (updated) {
          batch.yeast[index] = updated;
          batch.save();
        },
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<BatchModel>>(
      valueListenable: Hive.box<BatchModel>('batches').listenable(),
      builder: (context, batchBox, _) {
        final batch = batchBox.get(widget.batchKey);

        if (batch == null) {
          return Scaffold(
            appBar: AppBar(title: const Text("Batch Not Found")),
            body: const Center(
              child: Text("This batch may have been deleted."),
            ),
          );
        }

        return ValueListenableBuilder<Box<InventoryItem>>(
          valueListenable: Hive.box<InventoryItem>('inventory').listenable(),
          builder: (context, inventoryBox, _) {
            return Scaffold(
              appBar: AppBar(
                title: Text(batch.name),
                actions: [
                  IconButton(
                    icon: Icon(
                      _isBrewModeEnabled
                          ? Icons.lightbulb
                          : Icons.lightbulb_outline,
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
          // UPDATED YEAST SECTION
          _sectionTitle('Yeast'),
          _yeastList(batch),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Yeast'),
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (_) => AddYeastDialog(
                  onAdd: (newYeast) {
                    batch.yeast.add(newYeast);
                    batch.save();
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _sectionTitle('Additives'),
          _additivesList(batch),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Additive'),
            onPressed: () async {
              await showDialog<void>(
                context: context,
                builder: (_) => AddAdditiveDialog(
                  mustPH: estimateMustPH(batch),
                  volume: batch.batchVolume ?? 5.0,
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

  // --- PLANNING TAB LIST WIDGETS ---
  // All list widgets now support long-press to edit.

  Widget _ingredientsList(BatchModel batch) {
    if (batch.ingredients.isEmpty) return const Text('No ingredients added.');
    final inventoryBox = Hive.box<InventoryItem>('inventory');
    return Column(
      children: batch.ingredients.asMap().entries.map((entry) {
        final index = entry.key;
        final ingredientMap = entry.value;
        final ingredient = Map<String, dynamic>.from(ingredientMap);
        final name = ingredient['name'] as String? ?? 'Unnamed';
        final amount = (ingredient['amount'] as num?)?.toDouble() ?? 0;
        final unit = ingredient['unit'] as String? ?? '';
        final note = ingredient['note'] as String? ?? '';
        final inventoryItem = inventoryBox.values.firstWhere(
          (item) => item.name.toLowerCase() == name.toLowerCase(),
          orElse: () => InventoryItem(name: '', unit: '', unitType: UnitType.volume, category: '', purchaseHistory: []),
        );
        final inStock = inventoryItem.amountInStock;
        final sufficient = inStock >= amount;

        return InkWell(
          onLongPress: () => _editIngredientDialog(batch, index),
          child: ListTile(
            leading: const Icon(Icons.liquor_outlined),
            title: Text('$amount $unit $name'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.isNotEmpty) Text(note),
                if (inventoryItem.name.isNotEmpty)
                   Text(
                      'In stock: ${inStock.toStringAsFixed(2)} $unit',
                      style: TextStyle(
                        color: sufficient ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                else
                   const Text('Not in inventory', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _additivesList(BatchModel batch) {
    if (batch.additives.isEmpty) return const Text('No additives added.');
    final inventoryBox = Hive.box<InventoryItem>('inventory');
    return Column(
      children: batch.additives.asMap().entries.map((entry) {
        final index = entry.key;
        final additiveMap = entry.value;
        final additive = Map<String, dynamic>.from(additiveMap);
        final name = additive['name'] as String? ?? 'Unnamed';
        final amount = (additive['amount'] as num?)?.toDouble() ?? 0;
        final unit = additive['unit'] as String? ?? '';
        final note = additive['note'] as String? ?? '';
        final inventoryItem = inventoryBox.values.firstWhere(
          (item) => item.name.toLowerCase() == name.toLowerCase(),
          orElse: () => InventoryItem(name: '', unit: '', unitType: UnitType.volume, category: '', purchaseHistory: []),
        );
        final inStock = inventoryItem.amountInStock;
        final sufficient = inStock >= amount;

        return InkWell(
          onLongPress: () => _editAdditiveDialog(batch, index),
          child: ListTile(
            leading: const Icon(Icons.science),
            title: Text('$amount $unit $name'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.isNotEmpty) Text(note),
                if (inventoryItem.name.isNotEmpty)
                   Text(
                      'In stock: ${inStock.toStringAsFixed(2)} $unit',
                      style: TextStyle(
                        color: sufficient ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                else
                   const Text('Not in inventory', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _yeastList(BatchModel batch) {
    if (batch.yeast.isEmpty) return const Text('No yeast added.');
    final inventoryBox = Hive.box<InventoryItem>('inventory');
    return Column(
      children: batch.yeast.asMap().entries.map((entry) {
        final index = entry.key;
        final yeastMap = entry.value;
        final yeast = Map<String, dynamic>.from(yeastMap);
        final name = yeast['name'] as String? ?? 'Unnamed Yeast';
        final amount = (yeast['amount'] as num?)?.toDouble() ?? 0;
        final unit = yeast['unit'] as String? ?? '';
        final inventoryItem = inventoryBox.values.firstWhere(
          (item) => item.name.toLowerCase() == name.toLowerCase(),
          orElse: () => InventoryItem(name: '', unit: '', unitType: UnitType.mass, category: '', purchaseHistory: []),
        );
        final inStock = inventoryItem.amountInStock;
        final sufficient = inStock >= amount;

        return InkWell(
          onLongPress: () => _editYeastDialog(batch, index),
          child: ListTile(
            leading: const Icon(Icons.bubble_chart),
            title: Text('$amount $unit $name'),
            subtitle: inventoryItem.name.isNotEmpty
                ? Text(
                    'In stock: ${inStock.toStringAsFixed(2)} $unit',
                    style: TextStyle(
                      color: sufficient ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : const Text('Not in inventory', style: TextStyle(color: Colors.grey)),
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
    children: batch.safePlannedEvents.asMap().entries.map((entry) {
      final index = entry.key;
      final event = entry.value;

      return InkWell(
        onLongPress: () => _editPlannedEventDialog(batch, index),
        child: ListTile(
          leading: const Icon(Icons.event_note),
          title: Text(event.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(DateFormat.yMMMd().format(event.date)),
              if (event.notes != null && event.notes!.isNotEmpty)
                Text('Notes: ${event.notes}'),
            ],
          ),
trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      icon: const Icon(Icons.edit),
      tooltip: 'Edit',
      onPressed: () => _editPlannedEventDialog(batch, index),
    ),
    IconButton(
      icon: const Icon(Icons.delete, color: Colors.red),
      tooltip: 'Delete',
      onPressed: () => _deletePlannedEvent(batch, index),
    ),
  ],
),

        ),
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
                  fermentationStages: selectedRecipe!.fermentationStages.toList(),
                  yeast: batch.yeast,
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
      batch.yeast = List<Map<String, dynamic>>.from(recipe.yeast);
    }
    if (syncIngredients) {
      batch.ingredients =
          List<Map<String, dynamic>>.from(recipe.ingredients);
    }
    if (syncAdditives) {
      batch.additives = List<Map<String, dynamic>>.from(recipe.additives);
    }
    if (syncStages) {
      batch.fermentationStages = List<FermentationStage>.from(recipe.fermentationStages);
}



      if (batch.fermentationStages.isNotEmpty) {
        DateTime nextStageStartDate = batch.startDate;
        for (var stage in batch.fermentationStages) {
          stage.startDate = nextStageStartDate;
          nextStageStartDate =
              nextStageStartDate.add(Duration(days: stage.durationDays));
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
    context: context,
    builder: (context) => const PlannedEventDialog(),
  );

  if (newEvent != null) {
    batch.plannedEvents ??= [];
    batch.plannedEvents!.add(newEvent);
    await batch.save();
    setState(() {});
  }
}

Future<void> _editPlannedEventDialog(BatchModel batch, int index) async {
  final updatedEvent = await showDialog<PlannedEvent>(
    context: context,
    builder: (context) => PlannedEventDialog(
      existingEvent: batch.safePlannedEvents[index],
      onDelete: () {
        batch.plannedEvents?.removeAt(index);
        batch.save();
        setState(() {});
      },
    ),
  );

  if (updatedEvent != null) {
    batch.plannedEvents![index] = updatedEvent;
    await batch.save();
    setState(() {});
  }
}

void _deletePlannedEvent(BatchModel batch, int index) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Delete Planned Event"),
      content: const Text("Are you sure you want to delete this event?"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            batch.plannedEvents?.removeAt(index);
            batch.save();
            Navigator.pop(context);
            setState(() {});
          },
          child: const Text("Delete"),
        ),
      ],
    ),
  );
}

void _manageStages(BatchModel batch) async {
  final updatedStages = await showModalBottomSheet<List<FermentationStage>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ManageStagesDialog(
      initialStages: batch.safeFermentationStages,
      anchorStartDate: batch.startDate, // <-- anchor first stage here
    ),
  );

  if (updatedStages != null) {
    batch.fermentationStages = updatedStages;
    await batch.save();
    if (mounted) setState(() {});
  }
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
          // FIX: Updated this section to handle a list of yeasts, not just one.
          children: batch.yeast.isEmpty
              ? [const ListTile(title: Text('No yeast added.'))]
              : batch.yeast
                  .asMap()
                  .entries
                  .map((entry) => _buildChecklistItem(
                        batch: batch,
                        itemData: Map<String, dynamic>.from(entry.value),
                        inventoryBox: inventoryBox,
                        onChanged: (newValue) => _handleDeductionChange(
                          batch: batch,
                          itemType: 'yeast',
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
        cost: item.costPerUnit,
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
    required Map<dynamic, dynamic> item,
    int index = -1,
    required bool newValue,
    required Box<InventoryItem> inventoryBox,
  }) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final name = item['name'] as String? ?? 'Unnamed';
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final unit = item['unit'] as String? ?? '';
    final inventoryItem = inventoryBox.values
        .firstWhere((i) => i.name.toLowerCase() == name.toLowerCase());

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
        (batch.ingredients[index])['deductFromInventory'] = newValue;
        break;
    case 'yeast':
      (batch.yeast[index])['deductFromInventory'] = newValue;
      break;
      case 'additive':
        (batch.additives[index])['deductFromInventory'] = newValue;
        break;
    }
    
    // Call the new FEFO methods
    if (newValue) {
      inventoryItem.use(amount); // <-- Use the new method
      scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Used $amount $unit from $name')));
    } else {
      inventoryItem.restore(amount); // <-- Use the new method
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
  // sync local
  _tastingRating = batch.tastingRating ?? 0;
  _finalYieldUnit = batch.finalYieldUnit ?? 'gal';

  final actualAbv = (batch.og != null && batch.fg != null)
      ? calculateABV(batch.og!, batch.fg!)
      : null;

  // Tiny inline FG editor
  Future<void> editFg() async {
    final c = TextEditingController(text: batch.fg?.toStringAsFixed(3) ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Final Gravity'),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: 'e.g., 1.010'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      batch.fg = double.tryParse(c.text);
      await batch.save();
      setState(() {});
    }
  }

  // Packaging presets
  final presetChips = [
    {'label': '12 oz bottles', 'unit': '12oz bottle', 'method': 'Bottled'},
    {'label': '16 oz bottles', 'unit': '16oz bottle', 'method': 'Bottled'},
    {'label': '32 oz growlers', 'unit': '32oz growler', 'method': 'Bottled'},
    {'label': '5 gal keg', 'unit': '5gal keg', 'method': 'Kegged'},
    {'label': 'Bulk (gal)', 'unit': 'gal', 'method': 'Aged in Secondary'},
    {'label': 'Bulk (L)', 'unit': 'L', 'method': 'Aged in Secondary'},
  ];

  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // ===== Summary / Metrics
      _sectionCard(
        title: 'Final Summary',
        trailing: OutlinedButton.icon(
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Mark Completed'),
          onPressed: batch.status == 'Completed'
              ? null
              : () => _updateBatchStatus(batch, 'Completed'),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metricChip(
              icon: Icons.bubble_chart,
              label: 'OG',
              value: batch.og?.toStringAsFixed(3) ?? '—',
            ),
            _metricChip(
              icon: Icons.water_drop,
              label: 'FG',
              value: batch.fg?.toStringAsFixed(3) ?? '—',
              onTap: editFg,
            ),
            _metricChip(
              icon: Icons.percent,
              label: 'ABV',
              value: actualAbv != null ? '${actualAbv.toStringAsFixed(2)}%' : '—',
            ),
            _metricChip(
              icon: Icons.inventory_2_outlined,
              label: 'Yield',
              value: (batch.finalYield == null)
                  ? '—'
                  : '${batch.finalYield!.toStringAsFixed(2)} ${batch.finalYieldUnit ?? ''}',
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Rating:'),
                const SizedBox(width: 8),
                _starRow(
                  value: _tastingRating,
                  onChanged: (v) {
                    setState(() {
                      _tastingRating = v;
                      batch.tastingRating = v;
                      batch.save();
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),

      // ===== Packaging / Yield
      _sectionCard(
        title: 'Packaging & Yield',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // date
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Packaging Date'),
              subtitle: Text(
                batch.packagingDate == null
                    ? 'Not set'
                    : DateFormat.yMMMd().format(batch.packagingDate!),
              ),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: batch.packagingDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (date != null) {
                  batch.packagingDate = date;
                  await batch.save();
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: 8),

            // method
            DropdownButtonFormField<String>(
              value: batch.packagingMethod,
              decoration: const InputDecoration(labelText: 'Method'),
              items: const [
                DropdownMenuItem(value: 'Bottled', child: Text('Bottled')),
                DropdownMenuItem(value: 'Kegged', child: Text('Kegged')),
                DropdownMenuItem(value: 'Aged in Secondary', child: Text('Aged in Secondary')),
              ],
              onChanged: (v) {
                if (v != null) {
                  batch.packagingMethod = v;
                  batch.save();
                  setState(() {});
                }
              },
            ),

            const SizedBox(height: 12),
            // yield + unit
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _finalYieldController..text = batch.finalYield?.toString() ?? '',
                    decoration: const InputDecoration(labelText: 'Final Yield'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      batch.finalYield = double.tryParse(v);
                      batch.save();
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _finalYieldUnit,
                  onChanged: (u) {
                    if (u != null) {
                      setState(() {
                        _finalYieldUnit = u;
                        batch.finalYieldUnit = u;
                        batch.save();
                      });
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'gal', child: Text('gal')),
                    DropdownMenuItem(value: 'L', child: Text('L')),
                    DropdownMenuItem(value: '12oz bottle', child: Text('12oz bottle')),
                    DropdownMenuItem(value: '16oz bottle', child: Text('16oz bottle')),
                    DropdownMenuItem(value: '32oz growler', child: Text('32oz growler')),
                    DropdownMenuItem(value: '5gal keg', child: Text('5gal keg')),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),
            // Presets
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presetChips.map((p) {
                return ActionChip(
                  avatar: const Icon(Icons.local_drink),
                  label: Text(p['label'] as String),
                  onPressed: () {
                    batch.packagingMethod = p['method'] as String;
                    batch.finalYieldUnit = p['unit'] as String;
                    batch.save();
                    setState(() {});
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 12),
            // Computed counts
            Builder(builder: (_) {
              final fy = batch.finalYield;
              final u = batch.finalYieldUnit ?? 'gal';
              if (fy == null) return const SizedBox.shrink();

              final n12 = _bottlesFromYield(finalYield: fy, finalYieldUnit: u, bottleOz: 12);
              final n16 = _bottlesFromYield(finalYield: fy, finalYieldUnit: u, bottleOz: 16);
              final n25 = _bottlesFromYield(finalYield: fy, finalYieldUnit: u, bottleOz: 25.4); // 750mL
              final kegs = (_toGallons(fy, u) / 5.0).toStringAsFixed(2);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Estimated Packages', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(label: Text('$n12 × 12oz')),
                      Chip(label: Text('$n16 × 16oz')),
                      Chip(label: Text('$n25 × 750mL')),
                      Chip(label: Text('$kegs × 5gal kegs')),
                    ],
                  ),
                ],
              );
            }),
          ],
        ),
      ),

      // ===== Tasting Notes
      _sectionCard(
        title: 'Tasting Notes',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('Overall'),
              const SizedBox(width: 8),
              _starRow(
                value: _tastingRating,
                onChanged: (v) {
                  setState(() {
                    _tastingRating = v;
                    batch.tastingRating = v;
                    batch.save();
                  });
                },
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _tastingAromaController
                ..text = batch.tastingNotes?['aroma'] ?? '',
              decoration: const InputDecoration(labelText: 'Aroma'),
              onChanged: (v) {
                batch.tastingNotes ??= {};
                batch.tastingNotes!['aroma'] = v;
                batch.save();
              },
            ),
            TextField(
              controller: _tastingAppearanceController
                ..text = batch.tastingNotes?['appearance'] ?? '',
              decoration: const InputDecoration(labelText: 'Appearance'),
              onChanged: (v) {
                batch.tastingNotes ??= {};
                batch.tastingNotes!['appearance'] = v;
                batch.save();
              },
            ),
            TextField(
              controller: _tastingFlavorController
                ..text = batch.tastingNotes?['flavor'] ?? '',
              decoration: const InputDecoration(labelText: 'Flavor & Mouthfeel'),
              onChanged: (v) {
                batch.tastingNotes ??= {};
                batch.tastingNotes!['flavor'] = v;
                batch.save();
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                'Crisp', 'Dry', 'Tart', 'Fruity', 'Balanced', 'Funky', 'Sweet'
              ].map((t) {
                return InputChip(
                  label: Text(t),
                  onPressed: () {
                    final current = _tastingFlavorController.text;
                    final next = current.isEmpty ? t : '$current, $t';
                    _tastingFlavorController.text = next;
                    _tastingFlavorController.selection = TextSelection.fromPosition(
                      TextPosition(offset: next.length),
                    );
                    batch.tastingNotes ??= {};
                    batch.tastingNotes!['flavor'] = next;
                    batch.save();
                    setState(() {});
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),

      // ===== Lessons
      _sectionCard(
        title: 'Lessons Learned',
        child: TextField(
          controller: _finalNotesController..text = batch.finalNotes ?? '',
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'What would you do differently next time? What went well?',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            batch.finalNotes = v;
            batch.save();
          },
        ),
      ),

      // ===== Actions
      _sectionCard(
        title: 'Actions',
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text('Save as Recipe'),
              onPressed: () {
                // (leave your existing flow or wire here)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved as new recipe!')),
                );
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Clone to New Batch'),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Batch cloned!')),
                );
              },
            ),
          ],
        ),
      ),
    ],
  );
}


  // ===== Helpers: metric chip, section card, star rating =====
Widget _metricChip({
  required IconData icon,
  required String label,
  required String value,
  VoidCallback? onTap,
}) {
  final chip = Chip(
    avatar: Icon(icon, size: 18),
    label: Text('$label: $value'),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
  );
  return onTap == null
      ? chip
      : InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: chip);
}

Widget _sectionCard({
  required String title,
  Widget? trailing,
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
}) {
  return Card(
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

Widget _starRow({
  required int value,
  required ValueChanged<int> onChanged,
}) {
  return Row(
    children: List.generate(5, (i) {
      final filled = i < value;
      return IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(filled ? Icons.star : Icons.star_border, color: Colors.amber),
        onPressed: () => onChanged(i + 1),
      );
    }),
  );
}

// ===== Small utils for packaging math =====
double _toGallons(double qty, String unit) {
  switch (unit) {
    case 'gal':
      return qty;
    case 'L':
      return qty * 0.264172;
    case '12oz bottle':
      return (qty * 12.0) / 128.0;
    case '16oz bottle':
      return (qty * 16.0) / 128.0;
    case '32oz growler':
      return (qty * 32.0) / 128.0;
    case '5gal keg':
      return qty * 5.0;
    default:
      return qty; // fallback assumes gal
  }
}

int _bottlesFromYield({
  required double? finalYield,
  required String finalYieldUnit,
  required double bottleOz,
}) {
  if (finalYield == null) return 0;
  final totalOz = _toGallons(finalYield, finalYieldUnit) * 128.0;
  return (totalOz / bottleOz).floor();
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