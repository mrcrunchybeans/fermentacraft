import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/utils/recipe_to_batch.dart';


double estimateMustPH(BatchModel batch) {
  final withPH = batch.safeIngredients.where((f) => f['ph'] != null).toList();
  if (withPH.isEmpty) return 3.4;

  final phValues = withPH.map((f) => double.tryParse(f['ph'].toString()) ?? 3.4);
  final avgPH = phValues.reduce((a, b) => a + b) / phValues.length;
  return avgPH;
}

void syncBatchFromRecipe(BatchModel batch, RecipeModel recipe) {
  // ---- Yeast ----
  // If there’s an existing selection, try to preserve it by name; otherwise just take the first mapped yeast
  final mappedYeast = recipe.yeast
      .map<Map<String, dynamic>>((y) => recipeYeastToBatch(y as Map<String, dynamic>))
      .toList();

  if (batch.yeast.isNotEmpty) {
    final selectedName = (batch.yeast.first['name'] ?? '').toString();
    final preserved = mappedYeast.firstWhere(
      (y) => (y['name'] ?? '') == selectedName,
      orElse: () => mappedYeast.isNotEmpty ? mappedYeast.first : <String, dynamic>{},
    );
    batch.yeast = [preserved];
  } else {
    batch.yeast = mappedYeast.isNotEmpty ? [mappedYeast.first] : <Map<String, dynamic>>[];
  }

  // ---- Ingredients ----
  batch.ingredients = recipe.ingredients
      .map<Map<String, dynamic>>((ing) => recipeIngredientToBatch(ing as Map<String, dynamic>))
      .toList();

  // ---- Additives ----
  batch.additives = recipe.additives
      .map<Map<String, dynamic>>((a) => recipeAdditiveToBatch(a as Map<String, dynamic>))
      .toList();

  // ---- Stages ----
  batch.fermentationStages = recipe.fermentationStages.map((s) => s.copy()).toList();

  // ---- Targets ----
  batch.plannedOg = recipe.og;
  batch.plannedAbv = recipe.abv;
}

double calculateABV(double og, double fg) {
  return (og - fg) * 131.25;
}
