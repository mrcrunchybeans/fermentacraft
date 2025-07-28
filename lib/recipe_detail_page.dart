import 'package:flutter/material.dart';
import 'package:flutter_application_1/utils/temp_display.dart';
import 'package:intl/intl.dart';
import 'package:hive/hive.dart';

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
    final box = Hive.box<RecipeModel>('recipes');
    final updated = widget.recipe..lastOpened = DateTime.now();
    box.putAt(widget.index, updated);
  }

  void _editRecipe(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeBuilderPage(
        existingRecipe: widget.recipe,
        recipeKey: widget.index,
      ),
    ));
  }

  void _cloneRecipe(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeBuilderPage(
        existingRecipe: widget.recipe,
        isClone: true,
      ),
    ));
  }

  void _deleteRecipe(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Recipe"),
        content: const Text("Are you sure you want to delete this recipe?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
        ],
      ),
    );

    if (confirm == true) {
      final box = Hive.box<RecipeModel>('recipes');
      await box.deleteAt(widget.index);
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RecipeListPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;

    return Scaffold(
      appBar: AppBar(
        title: Text(recipe.name),
        actions: [
          IconButton(onPressed: () => _editRecipe(context), icon: const Icon(Icons.edit)),
          IconButton(onPressed: () => _cloneRecipe(context), icon: const Icon(Icons.copy)),
          IconButton(onPressed: () => _deleteRecipe(context), icon: const Icon(Icons.delete)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("Created: ${DateFormat.yMMMd().format(recipe.createdAt)}"),
          const SizedBox(height: 8),
          if (recipe.tags.isNotEmpty)
            Text("Tags: ${recipe.tags.join(', ')}"),
          const Divider(),

          Text('OG: ${recipe.og?.toStringAsFixed(3) ?? 'N/A'}'),
          Text('FG: ${recipe.fg?.toStringAsFixed(3) ?? 'N/A'}'),
          Text('ABV: ${recipe.abv?.toStringAsFixed(1) ?? 'N/A'}'),

          const Divider(),

          const Text("Fermentables", style: TextStyle(fontWeight: FontWeight.bold)),
          ...recipe.fermentables.map((f) => ListTile(
            title: Text(f['name'] ?? 'Unnamed'),
            subtitle: Text("${f['amount']} ${f['unit']}, OG: ${f['og']?.toStringAsFixed(3) ?? '—'}"),
          )),

          const Divider(),

          const Text("Additives", style: TextStyle(fontWeight: FontWeight.bold)),
          ...recipe.additives.map((a) => ListTile(
            title: Text(a['name']),
            subtitle: Text("${a['amount']} ${a['unit']}"),
          )),

          const Divider(),

          const Text("Yeast", style: TextStyle(fontWeight: FontWeight.bold)),
          ...recipe.yeast.map((y) => ListTile(
            title: Text(y['name']),
            subtitle: Text("${y['amount']} ${y['amount'] == 1 ? 'packet' : y['unit']}"),
          )),

          const Divider(),

          const Text("Fermentation Profile", style: TextStyle(fontWeight: FontWeight.bold)),
          ...recipe.fermentationStages.map((stage) => ListTile(
            title: Text(stage['name']),
            subtitle: Row(
              children: [
                const Icon(Icons.thermostat, size: 18, color: Colors.grey),
                const SizedBox(width: 4),
                Text("${stage['days']} ${stage['days'] == 1 ? 'day' : 'days'} @ ${TempDisplay.format((stage['temp'] as num).toDouble())}"),
              ],
            ),
          )),

          if (recipe.notes.trim().isNotEmpty) ...[
            const Divider(),
            const Text("Notes", style: TextStyle(fontWeight: FontWeight.bold)),
            Text(recipe.notes),
          ],
        ],
      ),
    );
  }
}
