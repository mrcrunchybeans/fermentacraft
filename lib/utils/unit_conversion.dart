import '../models/unit_type.dart';

class UnitConversion {
  // All keys are lowercase for consistency.
  static final Map<String, double> volumeUnits = {
    'ml': 1.0,
    'l': 1000.0,
    'fl oz': 29.5735,
    'cup': 236.588,
    'pint': 473.176,
    'quart': 946.353,
    'gal': 3785.41,
    'tsp': 4.92892,
    'tbsp': 14.7868,
  };

  static final Map<String, double> massUnits = {
    'mg': 0.001,
    'g': 1.0,
    'kg': 1000.0,
    'oz': 28.3495,
    'lb': 453.592,
    'packet': 5.0,
  };

  /// Returns a list of valid unit keys for a unit type
  static List<String> getUnitListFor(UnitType type) {
    return switch (type) {
      UnitType.mass => massUnits.keys.toList(),
      UnitType.volume => volumeUnits.keys.toList(),
      _ => [],
    };
  }

  /// Normalize units to their singular base form
  static String normalizeUnit(String unit) {
    final aliases = {
      'gallon': 'gal',
      'gallons': 'gal',
      'milliliter': 'ml',
      'milliliters': 'ml',
      'liter': 'l',
      'liters': 'l',
      'gram': 'g',
      'grams': 'g',
      'pound': 'lb',
      'pounds': 'lb',
      'packet': 'packet',
      'packets': 'packet',
      'package': 'packet',
      'packages': 'packet',
      'teaspoon': 'tsp',
      'teaspoons': 'tsp',
      'tablespoon': 'tbsp',
      'tablespoons': 'tbsp',
      'fl ounce': 'fl oz',
      'ounces': 'oz',
      'ounce': 'oz',
      'carboys': 'carboy',
    };

    return aliases[unit.toLowerCase()] ?? unit.toLowerCase();
  }

  /// Display-safe pluralization for units
  static String getDisplayUnit(String unit, double amount) {
    final base = normalizeUnit(unit);

    const simplePlurals = {
      'packet': 'packets',
      'package': 'packages',
      'bottle': 'bottles',
      'can': 'cans',
      'tablet': 'tablets',
      'cap': 'caps',
      'carboy': 'carboys',
    };

    const invariantUnits = {
      'g', 'kg', 'mg', 'lb',
      'ml', 'l', 'tsp', 'tbsp', 'fl oz', 'cup', 'oz', 'gal'
    };

    if (amount == 1) return base;
    if (simplePlurals.containsKey(base)) return simplePlurals[base]!;
    if (invariantUnits.contains(base)) return base;

    return base.endsWith('s') ? base : '${base}s';
  }

  /// Attempts to convert cost from one unit to another
  static double? tryConvertCostPerUnit({
    required double amount,
    required String fromUnit,
    required String toUnit,
    required double? costPerUnit,
  }) {
    if (costPerUnit == null) return null;

    final fromNormalized = normalizeUnit(fromUnit);
    final toNormalized = normalizeUnit(toUnit);

    final fromMap = volumeUnits.containsKey(fromNormalized) ? volumeUnits : massUnits;
    final toMap = volumeUnits.containsKey(toNormalized) ? volumeUnits : massUnits;

    final from = fromMap[fromNormalized];
    final to = toMap[toNormalized];
    if (from == null || to == null) return null;

    final conversionFactor = to / from;
    return costPerUnit * conversionFactor;
  }

  /// Attempts to convert amount between units
  static double? convertAmount({
    required double value,
    required String fromUnit,
    required String toUnit,
  }) {
    final fromNormalized = normalizeUnit(fromUnit);
    final toNormalized = normalizeUnit(toUnit);

    final fromMap = volumeUnits.containsKey(fromNormalized) ? volumeUnits : massUnits;
    final toMap = volumeUnits.containsKey(toNormalized) ? volumeUnits : massUnits;

    final from = fromMap[fromNormalized];
    final to = toMap[toNormalized];
    if (from == null || to == null) return null;

    return value * from / to;
  }
}

/// Infers UnitType (mass or volume) from a given unit string.
/// Throws an error if unknown.
UnitType inferUnitType(String unit) {
  final normalized = UnitConversion.normalizeUnit(unit);

  if (UnitConversion.massUnits.containsKey(normalized)) return UnitType.mass;
  if (UnitConversion.volumeUnits.containsKey(normalized)) return UnitType.volume;

  throw ArgumentError('Unknown unit type for unit: $unit');
}
