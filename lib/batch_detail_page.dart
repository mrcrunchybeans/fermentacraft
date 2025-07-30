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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  Widget _yeastSection(BatchModel batch) {
    final yeast = batch.yeast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Yeast'),
        if (yeast == null) const Text('No yeast selected.') else ListTile(
          leading: const Icon(Icons.bubble_chart),
          title: Text('${yeast['amount'] ?? ''} ${yeast['unit'] ?? ''} ${yeast['name'] ?? 'Unnamed'}'),
        ),
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
      ],
    );
  }

  Widget _additivesList(BatchModel batch) {
    if (batch.additives.isEmpty) return const Text('No additives added.');
    return Column(
      children: batch.additives.map((additive) {
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

  Widget _recipeSummaryCard(BatchModel batch) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Status: ${batch.status}'),
            const SizedBox(height: 4),
            Text('Target Volume: ${batch.batchVolume?.toStringAsFixed(1) ?? '—'} gal'),
            const SizedBox(height: 4),
            Text('Target OG: ${batch.plannedOg?.toStringAsFixed(3) ?? '—'}'),
            const SizedBox(height: 4),
            Text('Target ABV: ${batch.plannedAbv?.toStringAsFixed(1) ?? '—'}%'),
          ],
        ),
      ),
    );
  }

  Widget _ingredientsList(BatchModel batch) {
    if (batch.ingredients.isEmpty) return const Text('No ingredients added.');
    return Column(
      children: batch.ingredients.map((ingredient) {
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
          subtitle: Text('${event.date.toLocal().toString().split(' ')[0]}'
              '${event.notes != null ? '\nNotes: ${event.notes}' : ''}'),
          isThreeLine: event.notes != null,
        );
      }).toList(),
    );
  }

  // --- Dialog and Logic Methods ---
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
                Navigator.of(context).pop(); // Close the dialog
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Sync From Recipe'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('This will overwrite selected fields in the batch.'),
                const SizedBox(height: 12),
                CheckboxListTile(value: syncYeast, onChanged: (val) => setState(() => syncYeast = val ?? true), title: const Text("Yeast")),
                CheckboxListTile(value: syncIngredients, onChanged: (val) => setState(() => syncIngredients = val ?? true), title: const Text("Ingredients")),
                CheckboxListTile(value: syncAdditives, onChanged: (val) => setState(() => syncAdditives = val ?? true), title: const Text("Additives")),
                CheckboxListTile(value: syncStages, onChanged: (val) => setState(() => syncStages = val ?? true), title: const Text("Fermentation Stages")),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sync')),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final recipeBox = await Hive.openBox<RecipeModel>('recipes');
    final recipe = recipeBox.get(batch.recipeId);

    if (recipe == null) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recipe not found.')),
        );
      }
      return;
    }

    setState(() {
      if (syncYeast) {
        batch.yeast = recipe.yeast.isNotEmpty ? Map<String, dynamic>.from(recipe.yeast.first) : null;
      }
      if (syncIngredients) {
        batch.ingredients = List<Map<String, dynamic>>.from(recipe.fermentables);
      }
      if (syncAdditives) {
        batch.additives = List<Map<String, dynamic>>.from(recipe.additives);
      }
      if (syncStages) {
        batch.fermentationStages = List<FermentationStage>.from(recipe.fermentationStages);
      }
      batch.save();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Batch synced from recipe')));
  }

  // RESTORED: This method was missing.
  Future<PlannedEvent?> _addPlannedEventDialog() async {
    // You can implement your dialog logic here. For now, it does nothing.
    return null;
  }
  
  // RESTORED: This method was missing.
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
    return const Center(child: Text('Preparation content here'));
  }

  Widget _buildFermentingTab(BatchModel batch) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    // Wrap the Text widget in an Expanded widget
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
                          ));

                  if (newMeasurement != null) {
  setState(() {
    // Create a new, growable list from the old one
    final updatedMeasurements = List<Measurement>.from(batch.measurements);
    
    // Add the new item to the copy
    updatedMeasurements.add(newMeasurement);
    
    // Assign the new list back to the batch
    batch.measurements = updatedMeasurements;
    
    // Save the batch
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
              
              final index = sortedMeasurements.indexWhere((m) => m.timestamp == measurementToEdit.timestamp);

              final updatedMeasurement = await showDialog<Measurement>(
                context: context,
                builder: (_) => AddMeasurementDialog(
                  existingMeasurement: measurementToEdit,
                  previousMeasurement: (index > 0)
                      ? sortedMeasurements[index - 1]
                      : null,
                ),
              );

              if (updatedMeasurement != null) {
                setState(() {
                  final originalIndex = batch.measurements.indexWhere((m) => m.timestamp == measurementToEdit.timestamp);
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
      ),
    );
  }

  Widget _buildCompletedTab(BatchModel batch) {
    return const Center(child: Text('Final batch notes and stats'));
  }
}