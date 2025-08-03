import 'package:flutter/material.dart';
import 'package:flutter_application_1/utils/temp_display.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/recipe_model.dart';
import 'recipe_builder_page.dart';
import 'recipe_list_page.dart';

class RecipeDetailPage extends StatefulWidget {
  const RecipeDetailPage({
    super.key,
    required this.recipe,
    required this.index,
  });

  final int index;
  final RecipeModel recipe;

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final box = Hive.box<RecipeModel>('recipes');
        final updated = widget.recipe..lastOpened = DateTime.now();
        box.putAt(widget.index, updated);
      }
    });
  }

  void _editRecipe(BuildContext context, RecipeModel recipe) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeBuilderPage(
        existingRecipe: recipe,
        recipeKey: widget.index,
      ),
    ));
  }

  void _cloneRecipe(BuildContext context, RecipeModel recipe) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeBuilderPage(
        existingRecipe: recipe,
        isClone: true,
      ),
    ));
  }

  void _deleteRecipe(BuildContext context) async {
    // FIX: Capture the Navigator before the async gap.
    final navigator = Navigator.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Recipe"),
        content: const Text("Are you sure you want to delete this recipe? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    // The 'mounted' check is still important to prevent state updates on a disposed widget.
    if (confirm == true && mounted) {
      final box = Hive.box<RecipeModel>('recipes');
      await box.deleteAt(widget.index);
      
      // FIX: Use the captured navigator instance.
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RecipeListPage()),
        (route) => route.isFirst,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<RecipeModel>>(
      valueListenable: Hive.box<RecipeModel>('recipes').listenable(),
      builder: (context, box, _) {
        final recipe = box.getAt(widget.index);

        if (recipe == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Text("Recipe not found. It may have been deleted."),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(recipe.name),
            actions: [
              IconButton(onPressed: () => _editRecipe(context, recipe), icon: const Icon(Icons.edit)),
              IconButton(onPressed: () => _cloneRecipe(context, recipe), icon: const Icon(Icons.copy)),
              IconButton(onPressed: () => _deleteRecipe(context), icon: const Icon(Icons.delete)),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _buildInfoCard(recipe),
              const SizedBox(height: 12),
              _buildStatsCard(recipe),
              const SizedBox(height: 12),
              _buildIngredientsCard(recipe, "Ingredients", recipe.ingredients),
              const SizedBox(height: 12),
              _buildIngredientsCard(recipe, "Additives", recipe.additives),
              const SizedBox(height: 12),
              _buildYeastCard(recipe),
              const SizedBox(height: 12),
              _buildFermentationCard(recipe),
              if (recipe.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildNotesCard(recipe),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(RecipeModel recipe) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Created: ${DateFormat.yMMMd().format(recipe.createdAt)}"),
            const SizedBox(height: 8),
            if (recipe.tags.isNotEmpty)
              Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: recipe.tags.map((tag) => Chip(label: Text(tag.name))).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(RecipeModel recipe) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem("OG", recipe.og?.toStringAsFixed(3) ?? 'N/A'),
            _buildStatItem("FG", recipe.fg?.toStringAsFixed(3) ?? 'N/A'),
            _buildStatItem("ABV", "${recipe.abv?.toStringAsFixed(1) ?? 'N/A'}%"),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildIngredientsCard(RecipeModel recipe, String title, List<Map<dynamic, dynamic>> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
        initiallyExpanded: true,
        children: items.map((item) => ListTile(
          title: Text(item['name'] ?? 'Unnamed'),
          subtitle: Text("${item['amount']} ${item['unit']}"),
        )).toList(),
      ),
    );
  }

  Widget _buildYeastCard(RecipeModel recipe) {
    if (recipe.yeast.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        title: Text("Yeast", style: Theme.of(context).textTheme.titleLarge),
        initiallyExpanded: true,
        children: recipe.yeast.map((y) => ListTile(
          title: Text(y['name']),
          subtitle: Text("${y['amount']} ${y['amount'] == 1 ? 'packet' : y['unit']}"),
        )).toList(),
      ),
    );
  }

  Widget _buildFermentationCard(RecipeModel recipe) {
    if (recipe.fermentationStages.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        title: Text("Fermentation Profile", style: Theme.of(context).textTheme.titleLarge),
        initiallyExpanded: true,
        children: recipe.fermentationStages.map((stage) => ListTile(
          leading: const Icon(Icons.thermostat, color: Colors.grey),
          title: Text(stage['name']),
          subtitle: Text("${stage['days']} ${stage['days'] == 1 ? 'day' : 'days'} @ ${TempDisplay.format((stage['temp'] as num).toDouble())}"),
        )).toList(),
      ),
    );
  }

  Widget _buildNotesCard(RecipeModel recipe) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Notes", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(recipe.notes),
          ],
        ),
      ),
    );
  }
}
