// lib/utils/recipe_to_batch.dart
import 'package:fermentacraft/utils/gravity_utils.dart' as gu;

/// --- constants & helpers ----------------------------------------------------

const double _kMlPerGal   = 3785.411784;
const double _kMlPerL     = 1000.0;
const double _kMlPerFlOz  = 29.5735295625;

const double _kGPerKg     = 1000.0;
const double _kGPerLb     = 453.59237;
const double _kGPerOz     = 28.349523125;

/// Round a number to [places] decimal places.
double _round(double v, int places) {
  final p = places <= 0 ? 1.0 : List.filled(places, 10).fold<double>(1.0, (a, b) => a * b);
  return (v * p).round() / p;
}


double? _numToDouble(dynamic n) => (n is num) ? n.toDouble() : null;
String _asString(dynamic v, {String fallback = ''}) => (v ?? fallback).toString();

/// Normalize density to SG-ish range (handles g/L, 14.2 → 1.42 cases, etc.)
double _normDensity(num? d, {required double fallback}) {
  if (d == null) return fallback;
  final v = d.toDouble();
  if (v >= 100.0) return v / 1000.0; // g/L → g/mL ≈ SG
  if (v > 5.0 && v < 25.0) return v / 10.0; // 14.2 → 1.42
  if (v < 0.2) return v * 10.0; // 0.14 → 1.4
  return v;
}

/// Format an amount according to unit:
/// - gal/L/fl oz → 2 dp
/// - g/ml       → 0 dp
double _roundForUnit(double value, String unitLower) {
  switch (unitLower) {
    case 'gal':
    case 'l':
    case 'fl oz':
      return _round(value, 2);
    case 'g':
    case 'ml':
      return _round(value, 0);
    default:
      return _round(value, 2);
  }
}

/// --- Recipe -> Batch --------------------------------------------------------

/// Convert a recipe ingredient row (weightG/volumeMl/brix/density) → batch {amount, unit, og?, note?}
Map<String, dynamic> recipeIngredientToBatch(Map<String, dynamic> m) {
  final double? ml = _numToDouble(m['volumeMl']);
  final double? g  = _numToDouble(m['weightG']);

  // Prefer volume if present; convert to gallons and round nicely.
  late final String unit;
  late final double amount;

  if (ml != null && ml > 0) {
    unit = 'gal';
    amount = _roundForUnit(ml / _kMlPerGal, unit);
  } else if (g != null && g > 0) {
    unit = 'g';
    amount = _roundForUnit(g, unit);
  } else {
    unit = 'g';
    amount = 0;
  }

  // Optional OG for liquids (from brix or density)
  double? og;
  final double? brix    = _numToDouble(m['brix']);
  final double? density = _numToDouble(m['density']);
  if (brix != null && brix > 0) {
    og = gu.brixToSg(brix);
  } else if (density != null && density > 0) {
    og = _normDensity(density, fallback: 1.0);
  }

  final note = _asString(m['note'] ?? m['notes']).trim();

  return {
    'name': _asString(m['name'], fallback: 'Unnamed'),
    'amount': amount,
    'unit': unit,
    if (og != null && og > 1.0) 'og': double.parse(og.toStringAsFixed(3)),
    if (note.isNotEmpty) 'note': note,
    'deductFromInventory': false,
  };
}

Map<String, dynamic> recipeYeastToBatch(Map<String, dynamic> y) {
  final amt = _numToDouble(y['amount']) ?? _numToDouble(y['quantity']) ?? 0.0;
  final unit = _asString(y['unit']);
  final rounded = _roundForUnit(amt, unit.toLowerCase());

  return {
    'name': _asString(y['name'], fallback: 'Yeast'),
    'amount': rounded,
    'unit': unit,
    'form': _asString(y['form']),
    'deductFromInventory': false,
  };
}

Map<String, dynamic> recipeAdditiveToBatch(Map<String, dynamic> a) {
  final amt = _numToDouble(a['amount']) ?? _numToDouble(a['quantity']) ?? 0.0;
  final unit = _asString(a['unit']);
  final rounded = _roundForUnit(amt, unit.toLowerCase());

  return {
    'name': _asString(a['name'], fallback: 'Additive'),
    'amount': rounded,
    'unit': unit,
    'when': _asString(a['when']),
    'note': _asString(a['note'] ?? a['notes']),
    'deductFromInventory': false,
  };
}

/// --- Batch -> Recipe --------------------------------------------------------

Map<String, dynamic> batchIngredientToRecipe(Map<String, dynamic> m) {
  final name   = _asString(m['name'], fallback: 'Unnamed');
  final amount = _numToDouble(m['amount']) ?? 0.0;
  final unit   = _asString(m['unit']).toLowerCase();

  double? volumeMl;
  double? weightG;

  switch (unit) {
    case 'ml':
      volumeMl = amount;
      break;
    case 'l':
      volumeMl = amount * _kMlPerL;
      break;
    case 'gal':
      volumeMl = amount * _kMlPerGal;
      break;
    case 'fl oz':
      volumeMl = amount * _kMlPerFlOz;
      break;

    case 'g':
      weightG = amount;
      break;
    case 'kg':
      weightG = amount * _kGPerKg;
      break;
    case 'lb':
    case 'lbs':
      weightG = amount * _kGPerLb;
      break;
    case 'oz': // treated as mass-ounce
      weightG = amount * _kGPerOz;
      break;
  }

  // If batch item carried an OG (SG), preserve it as density for recipe math.
  final og = _numToDouble(m['og']);

  final notes = _asString(m['note']).trim();

  return {
    'name': name,
    if (volumeMl != null && volumeMl > 0) 'volumeMl': volumeMl,
    if (weightG != null && weightG > 0) 'weightG': weightG,
    if (og != null && og > 1.0) 'density': double.parse(og.toStringAsFixed(3)),
    if (notes.isNotEmpty) 'notes': notes,
    // 'type' optional; recipe code can default as needed.
  };
}

Map<String, dynamic> batchYeastToRecipe(Map<String, dynamic> y) {
  final qty = _numToDouble(y['amount']) ?? 0.0;
  final unit = _asString(y['unit']);
  final rounded = _roundForUnit(qty, unit.toLowerCase());

  return {
    'name': _asString(y['name'], fallback: 'Yeast'),
    'quantity': rounded,
    'unit': unit,
    'form': _asString(y['form']),
  };
}

Map<String, dynamic> batchAdditiveToRecipe(Map<String, dynamic> a) {
  final qty  = _numToDouble(a['amount']) ?? 0.0;
  final unit = _asString(a['unit']);
  final rounded = _roundForUnit(qty, unit.toLowerCase());

  return {
    'name': _asString(a['name'], fallback: 'Additive'),
    'quantity': rounded,
    'unit': unit,
    'when': _asString(a['when']),
    'notes': _asString(a['note']),
  };
}
