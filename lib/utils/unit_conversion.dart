import '../models/unit_type.dart';

class UnitConversion {
  static final Map<String, double> volumeUnits = {
    'mL': 1.0,
    'L': 1000.0,
    'fl oz': 29.5735,
    'cup': 236.588,
    'pint': 473.176,
    'quart': 946.353,
    'gal': 3785.41,
    '12 oz bottle': 355.0,
  };

  static final Map<String, double> massUnits = {
    'mg': 0.001,
    'g': 1.0,
    'kg': 1000.0,
    'oz': 28.3495,
    'lb': 453.592,
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
  required double? costPerUnit, // ← now nullable
}) {
  if (costPerUnit == null) return null;

  final fromMap = volumeUnits.containsKey(fromUnit) ? volumeUnits : massUnits;
  final from = fromMap[fromUnit];
  final to = fromMap[toUnit];
  if (from == null || to == null) return null;

  final conversionFactor = from / to;
  return costPerUnit * conversionFactor;
}

  static double? convertAmount({
    required double value,
    required String fromUnit,
    required String toUnit,
  }) {
    final fromMap = volumeUnits.containsKey(fromUnit) ? volumeUnits : massUnits;
    final from = fromMap[fromUnit];
    final to = fromMap[toUnit];
    if (from == null || to == null) return null;

    return value * from / to;
  }
}

// 👇 Place this **outside** the class
UnitType inferUnitType(String unit) {
  if (UnitConversion.massUnits.containsKey(unit)) return UnitType.mass;
  if (UnitConversion.volumeUnits.containsKey(unit)) return UnitType.volume;
  if (unit == 'package') return UnitType.mass; // Or create a separate UnitType.other if needed
  throw ArgumentError('Unknown unit type for unit: $unit');
}

