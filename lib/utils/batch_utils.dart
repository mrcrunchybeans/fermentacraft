import 'package:flutter_application_1/models/batch_model.dart';
import 'package:flutter_application_1/models/recipe_model.dart';

double estimateMustPH(BatchModel batch) {
  final withPH = batch.safeIngredients.where((f) => f['ph'] != null).toList();
  if (withPH.isEmpty) return 3.4;

  final phValues = withPH.map((f) => double.tryParse(f['ph'].toString()) ?? 3.4);
  final avgPH = phValues.reduce((a, b) => a + b) / phValues.length;
  return avgPH;
}

void syncBatchFromRecipe(BatchModel batch, RecipeModel recipe) {
  // Sync yeast (preserving selection if possible)
  batch.yeast = [
    List<Map<String, dynamic>>.from(recipe.yeast)
        .firstWhere(
          (y) => y['name'] == batch.yeast.first['name'],
          orElse: () => {},
        )
  ];

  // Sync ingredients and additives
  batch.ingredients = List<Map<String, dynamic>>.from(recipe.ingredients);
  batch.additives = List<Map<String, dynamic>>.from(recipe.additives);

  // Sync fermentation stages using copy constructor
  batch.fermentationStages = recipe.fermentationStages.map((s) => s.copy()).toList();

  // Sync target stats
  batch.plannedOg = recipe.og;
  batch.plannedAbv = recipe.abv;
}

double calculateABV(double og, double fg) {
  return (og - fg) * 131.25;
}
