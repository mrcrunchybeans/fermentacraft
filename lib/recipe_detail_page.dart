import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';
import 'utils/temp_display.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/settings_model.dart';
import 'models/fermentation_stage.dart';
import 'models/recipe_model.dart';
import 'recipe_builder_page.dart';
import 'recipe_list_page.dart';
import 'package:provider/provider.dart';
import 'package:fermentacraft/services/feature_gate.dart';



// NOTE: In the page that navigates here (e.g., RecipeListPage),
// you must now pass the recipe's key instead of its index.
/*
// Example from RecipeListPage:
...
final recipe = box.getAt(index);
if (recipe != null) {
  Navigator.push(context, MaterialPageRoute(
    // Pass the recipe's key, not the index
    builder: (_) => RecipeDetailPage(recipeKey: recipe.key, recipe: recipe),
  ));
}
...
*/

class RecipeDetailPage extends StatefulWidget {
  const RecipeDetailPage({
    super.key,
    required this.recipe,
    required this.recipeKey, // CHANGED from 'index'
  });

  final dynamic recipeKey; // CHANGED from 'int index'
  final RecipeModel recipe;

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

void _upsell(BuildContext context, String reason) {
showPaywall(context);

}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final box = Hive.box<RecipeModel>('recipes');
        final updated = widget.recipe..lastOpened = DateTime.now();
        box.put(widget.recipeKey, updated); // CHANGED from 'putAt'
      }
    });
  }

  Map<String, dynamic> safeMap(dynamic input) {
    if (input is Map<String, dynamic>) return input;
    if (input is Map) {
      return input.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }

  void _editRecipe(BuildContext context, RecipeModel recipe) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeBuilderPage(
        existingRecipe: recipe,
        recipeKey: widget.recipeKey, // CHANGED from 'widget.index'
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
    final navigator = Navigator.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Recipe"),
        content: const Text(
            "Are you sure you want to delete this recipe? This action cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final box = Hive.box<RecipeModel>('recipes');
      await box.delete(widget.recipeKey); // CHANGED from 'deleteAt'
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
        final recipe = box.get(widget.recipeKey); // CHANGED from 'getAt'

        if (recipe == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Text("Recipe not found. It may have been deleted."),
            ),
          );
        }
final fg = FeatureGate.instance;
// If you have a dedicated recipe limit, use it. Otherwise pick a number:
final int freeLimit = fg.recipeLimitFree; // define in FeatureGate if not present
final int recipeCount = Hive.box<RecipeModel>('recipes').length;
final bool atRecipeLimit = !fg.isPro && recipeCount >= freeLimit;

        return Scaffold(
          appBar: AppBar(
            title: Text(recipe.name),
            actions: [
  IconButton(
    onPressed: () => _editRecipe(context, recipe),
    icon: const Icon(Icons.edit),
    tooltip: 'Edit',
  ),
  IconButton(
    onPressed: atRecipeLimit
        ? () => _upsell(context, 'Free limit reached ($freeLimit recipes). Upgrade to copy.')
        : () => _cloneRecipe(context, recipe),
    icon: const Icon(Icons.copy),
    tooltip: atRecipeLimit ? 'Upgrade to copy' : 'Copy recipe',
  ),
  IconButton(
    onPressed: () => _deleteRecipe(context),
    icon: const Icon(Icons.delete),
    tooltip: 'Delete',
  ),
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
                children:
                    recipe.tags.map((tag) => Chip(label: Text(tag.name))).toList(),
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
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildIngredientsCard(
      RecipeModel recipe, String title, List<Map<dynamic, dynamic>> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
        initiallyExpanded: true,
        children: items.map((item) {
          final i = safeMap(item);
          return ListTile(
            title: Text(i['name'] ?? 'Unnamed'),
            subtitle: Text("${i['amount']} ${i['unit']}"),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildYeastCard(RecipeModel recipe) {
    if (recipe.yeast.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        title: Text("Yeast", style: Theme.of(context).textTheme.titleLarge),
        initiallyExpanded: true,
        children: recipe.yeast.map((y) {
          final yeast = safeMap(y);
          final amount = yeast['amount'] ?? 0;
          final unit = yeast['unit'] ?? 'packets'; // Default to 'packets' if null

          // Determine the display unit based on amount and unit type
          final displayUnit =
              (amount == 1 && unit == 'packets') ? 'packet' : unit;

          return ListTile(
            title: Text(yeast['name']),
            subtitle: Text("$amount $displayUnit"),
          );
        }).toList(),
      ),
    );
  }

Widget _buildFermentationCard(RecipeModel recipe) {
  final settings = context.watch<SettingsModel>();

  if (recipe.fermentationStages.isEmpty) return const SizedBox.shrink();

  return Card(
    child: ExpansionTile(
      title: Text(
        "Fermentation Profile",
        style: Theme.of(context).textTheme.titleLarge,
      ),
      initiallyExpanded: true,
      children: recipe.fermentationStages.map<Widget>((dynamic stage) {
        final FermentationStage s = (stage is FermentationStage)
            ? stage
            : FermentationStage.fromJson(Map<String, dynamic>.from(stage as Map));

        return ListTile(
          leading: const Icon(Icons.thermostat, color: Colors.grey),
          title: Text(s.name),
          subtitle: Text(
          "${s.durationDays} ${s.durationDays == 1 ? 'day' : 'days'} @ ${s.targetTempC?.toDisplay(targetUnit: settings.unit) ?? 'N/A'}",
          ),
        );
      }).toList(),
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