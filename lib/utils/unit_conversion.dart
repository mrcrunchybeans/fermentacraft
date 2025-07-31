import '../models/unit_type.dart';

class UnitConversion {
  // All keys are now lowercase for consistency.
  static final Map<String, double> volumeUnits = {
    'ml': 1.0,
    'l': 1000.0,
    'fl oz': 29.5735,
    'cup': 236.588,
    'pint': 473.176,
    'quart': 946.353,
    'gal': 3785.41,
    '12 oz bottle': 355.0,
    // -- ADDED NEW UNITS --
    'tsp': 4.92892,  // Teaspoon in mL
    'tbsp': 14.7868, // Tablespoon in mL
  };

  // All keys are now lowercase.
  static final Map<String, double> massUnits = {
    'mg': 0.001,
    'g': 1.0,
    'kg': 1000.0,
    'oz': 28.3495,
    'lb': 453.592,
    'packets': 5.0, // Defines 1 packet/package as 5 grams
  };

  static List<String> getUnitListFor(UnitType type) {
    return switch (type) {
      UnitType.mass => massUnits.keys.toList(),
      UnitType.volume => volumeUnits.keys.toList(),
      _ => [],
    };
  }

  static double? tryConvertCostPerUnit({
    required double amount,
    required String fromUnit,
    required String toUnit,
    required double? costPerUnit,
  }) {
    if (costPerUnit == null) return null;

    final fromMap = volumeUnits.containsKey(fromUnit) ? volumeUnits : massUnits;
    final toMap = volumeUnits.containsKey(toUnit) ? volumeUnits : massUnits;

    final from = fromMap[fromUnit];
    final to = toMap[toUnit];
    if (from == null || to == null) return null;

    final conversionFactor = to / from;
    return costPerUnit * conversionFactor;
  }

  static double? convertAmount({
    required double value,
    required String fromUnit,
    required String toUnit,
  }) {
    final fromMap = volumeUnits.containsKey(fromUnit) ? volumeUnits : massUnits;
    final toMap = volumeUnits.containsKey(toUnit) ? volumeUnits : massUnits;
    
    final from = fromMap[fromUnit];
    final to = toMap[toUnit];
    if (from == null || to == null) return null;

    return value * from / to;
  }
}

UnitType inferUnitType(String unit) {
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
    'packet': 'packets',
    // -- ADDED NEW ALIASES --
    'teaspoon': 'tsp',
    'teaspoons': 'tsp',
    'tablespoon': 'tbsp',
    'tablespoons': 'tbsp',
    'package': 'packets',
    'packages': 'packets',
  };

  final normalized = aliases[unit.toLowerCase()] ?? unit.toLowerCase();

  if (UnitConversion.massUnits.containsKey(normalized)) return UnitType.mass;
  if (UnitConversion.volumeUnits.containsKey(normalized)) return UnitType.volume;

  throw ArgumentError('Unknown unit type for unit: $unit');
}