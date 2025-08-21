import 'recipe_model.dart';

extension RecipeView on RecipeModel {
  List<Map<String, dynamic>> get fermentables => safeIngredients;

  static String _fmtNum(num? v, {int fractionDigits = 1}) =>
      (v == null) ? '-' : v.toStringAsFixed(fractionDigits);

  List<String> get fermentableLines => fermentables.map((f) {
    final name = (f['name'] ?? 'Unnamed').toString();
    final wG = (f['weightG'] as num?)?.toDouble();
    final vMl = (f['volumeMl'] as num?)?.toDouble();
    final weight = wG != null ? '${_fmtNum(wG, fractionDigits: 0)} g' : null;
    final vol    = vMl != null ? '${_fmtNum(vMl, fractionDigits: 0)} ml' : null;
    final parts = [weight, vol].where((s) => s != null && s.isNotEmpty).join(' • ');
    return parts.isEmpty ? name : '$name — $parts';
  }).toList(growable: false);
}
