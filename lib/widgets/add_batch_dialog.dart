import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/batch_model.dart';
import 'package:flutter_application_1/models/recipe_model.dart';
import 'package:flutter_application_1/models/fermentation_stage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

class AddBatchDialog extends StatefulWidget {
  const AddBatchDialog({super.key});

  @override
  State<AddBatchDialog> createState() => _AddBatchDialogState();
}

class _AddBatchDialogState extends State<AddBatchDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _volumeController = TextEditingController();
  String? _selectedRecipeId;
  DateTime _startDate = DateTime.now();
  String _status = 'Planning';

  final List<String> _statusOptions = [
    'Planning',
    'Brewing',
    'Fermenting',
    'Completed'
  ];

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
      });
    }
  }

  void _saveBatch() {
    if (_formKey.currentState?.validate() ?? false) {
      final recipesBox = Hive.box<RecipeModel>('recipes');
      final selectedRecipe = _selectedRecipeId != null
          ? recipesBox.values.firstWhere(
              (r) => r.id == _selectedRecipeId,
              orElse: () => RecipeModel(
                name: 'Unknown',
                tags: [],
                createdAt: DateTime.now(),
              ),
            )
          : null;

      final newBatch = BatchModel(
        id: const Uuid().v4(),
        name: _nameController.text.trim(),
        recipeId: _selectedRecipeId ?? '',
        startDate: _startDate,
        status: _status,
        batchVolume: _volumeController.text.isNotEmpty
            ? double.tryParse(_volumeController.text)
            : null,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: DateTime.now(),
        tags: [],
        og: selectedRecipe?.og,
        fg: selectedRecipe?.fg,
        abv: selectedRecipe?.abv,
        ingredients: selectedRecipe?.ingredients != null
            ? List<Map<String, dynamic>>.from(selectedRecipe!.ingredients)
            : [],
        additives: selectedRecipe?.additives != null
            ? List<Map<String, dynamic>>.from(selectedRecipe!.additives)
            : [],
        yeast: (selectedRecipe?.yeast != null &&
                selectedRecipe!.yeast.isNotEmpty)
            ? Map<String, dynamic>.from(selectedRecipe.yeast.first)
            : null,
        fermentationStages: selectedRecipe?.fermentationStages != null
    ? selectedRecipe!.fermentationStages.map((e) {
        if (e is FermentationStage) return e;
        return FermentationStage.fromJson(e);
      }).toList()
      .cast<FermentationStage>() // ✅ cast to correct type
    : [],
        measurementLogs: [],
        plannedEvents: [],
        deductedIngredients: {},
      );

      final box = Hive.box<BatchModel>('batches');
      box.put(newBatch.id, newBatch);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipes = Hive.box<RecipeModel>('recipes');

    return AlertDialog(
      title: const Text('Add New Batch'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Batch Name'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text('Start Date: ${_startDate.toLocal().toString().split(' ')[0]}'),
                  ),
                  TextButton(
                    onPressed: _pickDate,
                    child: const Text('Select Date'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                onChanged: (value) => setState(() => _status = value!),
                items: _statusOptions
                    .map((status) => DropdownMenuItem(
                          value: status,
                          child: Text(status),
                        ))
                    .toList(),
                decoration: const InputDecoration(labelText: 'Status'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedRecipeId,
                onChanged: (value) => setState(() => _selectedRecipeId = value),
                decoration: const InputDecoration(labelText: 'Linked Recipe (optional)'),
                items: recipes.values.map((recipe) {
                  return DropdownMenuItem(
                    value: recipe.id,
                    child: Text(recipe.name),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveBatch,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
