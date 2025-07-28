import 'package:flutter/material.dart';
import '../models/batch_model.dart';
import '../models/planned_event.dart';
import '../widgets/add_fermentable_dialog.dart';
import '../widgets/add_additive_dialog.dart';
import '../utils/batch_utils.dart';


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
            icon: const Icon(Icons.add),
            label: const Text('Add Fermentation Stage'),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Add Fermentation Stage coming soon')),
              );
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
    return const Center(child: Text('Fermentation activity log coming soon'));
  }

  Widget _buildCompletedTab(BatchModel batch) {
    return const Center(child: Text('Final batch notes and stats'));
  }
}
