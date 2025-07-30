import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/recipe_model.dart';
import 'package:flutter_application_1/widgets/add_measurement_dialog.dart';
import 'package:hive/hive.dart';
import '../models/batch_model.dart';
import '../models/planned_event.dart';
import '../widgets/add_fermentable_dialog.dart';
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
  late TextEditingController _prepNotesController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _prepNotesController =
        TextEditingController(text: widget.batch.prepNotes ?? '');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _prepNotesController.dispose();
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
    final yeast = batch.yeast != null
        ? Map<String, dynamic>.from(batch.yeast!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Yeast'),
        if (yeast == null)
          const Text('No yeast selected.')
        else
          ListTile(
            leading: const Icon(Icons.bubble_chart),
            title: Text(
                '${yeast['amount'] ?? ''} ${yeast['unit'] ?? ''} ${yeast['name'] ?? 'Unnamed'}'),
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
    return Column(
      children: batch.ingredients.map((rawIngredient) {
        final ingredient = Map<String, dynamic>.from(rawIngredient);

        final name = ingredient['name'] ?? 'Unnamed';
        final amount = ingredient['amount']?.toString() ?? '?';
        final unit = ingredient['unit'] ?? '';
        final note = ingredient['note'] ?? '';
        return ListTile(
          title: Text('$amount $unit $name'),
          subtitle: note.isNotEmpty ? Text(note) : null,
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

  // --- Dialog and Logic Methods ---
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
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Target OG'),
            ),
            TextField(
              controller: abvController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
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

    final recipeBox = await Hive.openBox<RecipeModel>('recipes');
    List<RecipeModel> allRecipes = recipeBox.values.toList();

    if (!mounted) return;

    RecipeModel? selectedRecipe = (batch.recipeId.isNotEmpty)
        ? recipeBox.get(batch.recipeId)
        : null;

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
                    onChanged: (val) => setState(() => syncStages = val ?? true),
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
                final newRecipe = RecipeModel(
                  name: batch.name,
                  createdAt: DateTime.now(),
                  tags: batch.tags,
                  og: batch.og,
                  fg: batch.fg,
                  abv: batch.abv,
                  additives: batch.additives,
                  fermentables: batch.ingredients,
                  fermentationStages:
                      batch.safeFermentationStages.map((e) => e.toMap()).toList(),
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

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (mounted) {
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recipe saved and linked')),
                  );
                }
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
            List<Map<String, dynamic>>.from(recipe.fermentables);
      }
      if (syncAdditives) {
        batch.additives = List<Map<String, dynamic>>.from(recipe.additives);
      }
      if (syncStages) {
        batch.fermentationStages = recipe.fermentationStages
            .map((stageMap) =>
                FermentationStage.fromMap(Map<String, dynamic>.from(stageMap)))
            .toList();
      }
      if (syncTargets) {
        batch.batchVolume = recipe.batchVolume;
        batch.plannedOg = recipe.plannedOg;
        batch.plannedAbv = recipe.plannedAbv;
      }
      batch.save();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Batch synced from recipe')));
    }
  }

  Future<PlannedEvent?> _addPlannedEventDialog() async {
    // Placeholder implementation
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

  // --- Main Build Method ---

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

  // --- Tab Builder Methods ---

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
                builder: (_) => AddFermentableDialog(
                  onAddToRecipe: (fermentable) {
                    setState(() {
                      batch.ingredients.add(fermentable);
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Ingredients Ready'),
          _ingredientsList(batch),
          const SizedBox(height: 16),
          _yeastSection(batch, showEditButton: false),
          const SizedBox(height: 16),
          _sectionTitle('Additives'),
          _additivesList(batch),
          const SizedBox(height: 16),
          _sectionTitle('Preparation Notes'),
          _buildPreparationNotesEditor(batch),
        ],
      ),
    );
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
                          // MODIFIED: Pass the required firstMeasurementDate
                          previousMeasurement: sortedMeasurements.isNotEmpty
                              ? sortedMeasurements.last
                              : null,
                          firstMeasurementDate: sortedMeasurements.isNotEmpty
                              ? sortedMeasurements.first.timestamp
                              : null,
                        ));

                if (newMeasurement != null) {
                  setState(() {
                    final updatedMeasurements =
                        List<Measurement>.from(batch.measurements);
                    updatedMeasurements.add(newMeasurement);
                    batch.measurements = updatedMeasurements;
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
                // MODIFIED: Pass the required firstMeasurementDate here too
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
    return const Center(child: Text('Final batch notes and stats'));
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