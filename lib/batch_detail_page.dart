import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/measurement.dart';
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









class BatchDetailPage extends StatefulWidget {
  final BatchModel batch;

  const BatchDetailPage({super.key, required this.batch});

  @override
  State<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<BatchDetailPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    _tabController = TabController(length: 4, vsync: this);
    super.initState();
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

Widget _yeastSection(BatchModel batch) {
  final yeast = batch.yeast;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Yeast'),
      if (yeast == null)
        const Text('No yeast selected.'),
      if (yeast != null)
        ListTile(
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Are you sure you want to sync data from the original recipe? This will overwrite selected fields in the batch.'),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: syncYeast,
              onChanged: (val) => setState(() => syncYeast = val ?? true),
              title: const Text("Yeast"),
            ),
            CheckboxListTile(
              value: syncIngredients,
              onChanged: (val) => setState(() => syncIngredients = val ?? true),
              title: const Text("Ingredients"),
            ),
            CheckboxListTile(
              value: syncAdditives,
              onChanged: (val) => setState(() => syncAdditives = val ?? true),
              title: const Text("Additives"),
            ),
            CheckboxListTile(
              value: syncStages,
              onChanged: (val) => setState(() => syncStages = val ?? true),
              title: const Text("Fermentation Stages"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sync')),
        ],
      ),
    ),
  );

  if (confirmed != true) return;

  final recipeBox = Hive.isBoxOpen('recipes')
      ? Hive.box<RecipeModel>('recipes')
      : await Hive.openBox<RecipeModel>('recipes');

  if (!mounted) return;

  final recipe = recipeBox.get(batch.recipeId);

  if (recipe == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recipe not found.')),
    );
    return;
  }

if (syncYeast) {
  final yeastData = recipe.yeast;

  if (yeastData.isNotEmpty) {
    final firstItem = yeastData.first;
    batch.yeast = Map<String, dynamic>.from(firstItem);
    } else if (yeastData is Map) {
if (recipe.yeast.isNotEmpty) {
  final first = recipe.yeast.first;
  batch.yeast = Map<String, dynamic>.from(first);
}
  } else {
    batch.yeast = null;
  }
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


  await batch.save();

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Batch synced from recipe')),
  );
}





  Widget _additivesList(BatchModel batch) {
    if (batch.additives.isEmpty) {
      return const Text('No additives added.');
    }

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${batch.status}'),
            Text('Target Volume: ${batch.batchVolume?.toStringAsFixed(1) ?? '—'} gal'),
            Text('Target OG: ${batch.plannedOg?.toStringAsFixed(3) ?? '—'}'),
            Text('Target ABV: ${batch.plannedAbv?.toStringAsFixed(1) ?? '—'}%'),
          ],
        ),
      ),
    );
  }

  Widget _ingredientsList(BatchModel batch) {
    if (batch.ingredients.isEmpty) {
      return const Text('No ingredients added.');
    }

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
        const unit = 'days';

        return ListTile(
          leading: const Icon(Icons.thermostat),
          title: Text(name),
          subtitle: Text('Temp: $temp°C, Duration: $duration $unit'),
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

  Future<PlannedEvent?> _addPlannedEventDialog() async {
    final titleController = TextEditingController();
    final notesController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    return await showDialog<PlannedEvent>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Planned Event'),
        content: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Date: '),
                    TextButton(
                      child: Text('${selectedDate.toLocal()}'.split(' ')[0]),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = picked);
                        }
                      },
                    )
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newEvent = PlannedEvent(
                title: titleController.text,
                date: selectedDate,
                notes: notesController.text.isEmpty ? null : notesController.text,
              );
              Navigator.pop(context, newEvent);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
  builder: (_) => AddFermentableDialog(
    onAddToRecipe: (fermentable) {
      setState(() {
        widget.batch.ingredients = List.from(widget.batch.ingredients); // make it modifiable
        widget.batch.ingredients.add(fermentable);
        widget.batch.save();
      });
    },
    onAddToInventory: (_) {}, // Disable inventory from here
  ),
);

            },
          ),
          const SizedBox(height: 16),

_yeastSection(batch),
const SizedBox(height: 16),


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
const SizedBox(height: 12),



FermentationChartWidget(
  measurements: batch.measurements,
  stages: batch.safeFermentationStages,
  onEditMeasurement: (updatedMeasurement) async {
},

),
const SizedBox(height: 8),
ElevatedButton.icon(
  icon: const Icon(Icons.settings),
  label: const Text('Manage Stages'),
  onPressed: () async {
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
  },
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
                  widget.batch.plannedEvents ??= [];
                  widget.batch.plannedEvents!.add(newEvent);
                  widget.batch.save();
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
        const SizedBox(height: 16),
        Text(
          'Fermentation Stages',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
  icon: const Icon(Icons.add),
  label: const Text('Add Measurement'),
  onPressed: () async {
  final newMeasurement = await showDialog<Measurement>(
    context: context,
    builder: (_) => AddMeasurementDialog(
      onSave: (m) => Navigator.of(context).pop(m),
    ),
  );

  if (newMeasurement != null) {
    setState(() {
      final updated = [...batch.measurements]; // safe mutable copy
      updated.add(newMeasurement);
      batch.measurements = updated;
      batch.save();
    });
  }
},

),

FermentationChartWidget(
  measurements: batch.measurements,
  stages: batch.safeFermentationStages,
  onEditMeasurement: (updatedMeasurement) async {
},

),


        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () async {
            final updatedStages = await showDialog<List<FermentationStage>>(
              context: context,
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
          },
          icon: const Icon(Icons.edit_calendar),
          label: const Text('Manage Stages'),
        ),
      ],
    ),
  );
}


  Widget _buildCompletedTab(BatchModel batch) {
    return const Center(child: Text('Final batch notes and stats'));
  }
}



