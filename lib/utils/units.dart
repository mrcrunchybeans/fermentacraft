// lib/utils/units.dart
library;

/// Canonical units used across the app.
/// Keep this list in the order you’d like to show in dropdowns.
const List<String> kCanonicalUnits = <String>[
  'g',
  'oz',
  'lb',
  'mL',
  'L',
  'tsp',
  'tbsp',
  'cup',
  'fl oz',
  'gal',
  'package',
];

/// Common aliases -> canonical
const Map<String, String> kUnitAliases = {
  // grams
  'gram': 'g',
  'grams': 'g',
  // ounces
  'ounce': 'oz',
  'ounces': 'oz',
  // pounds
  'pounds': 'lb',
  'pound': 'lb',
  'lbs': 'lb',
  // milliliter
  'ml': 'mL',
  'milliliter': 'mL',
  'milliliters': 'mL',
  // liter
  'l': 'L',
  'liter': 'L',
  'liters': 'L',
  'litre': 'L',
  'litres': 'L',
  // gallon
  'gallon': 'gal',
  'gallons': 'gal',
  // package/packet
  'packets': 'package',
  'packet': 'package',
  'pkg': 'package',
};

/// Normalize any raw unit string to one of [kCanonicalUnits].
String normalizeUnit(String? raw) {
  if (raw == null || raw.trim().isEmpty) return kCanonicalUnits.first;
  final v = raw.trim();

  // exact match first
  if (kCanonicalUnits.contains(v)) return v;

  // alias match (case-insensitive)
  final lower = v.toLowerCase();
  final aliased = kUnitAliases[lower];
  if (aliased != null && kCanonicalUnits.contains(aliased)) return aliased;

  // last-ditch: title-case variants like "Ml" -> "mL" won’t match; handle a few:
  switch (v) {
    case 'Ml':
      return 'mL';
    case 'Fl oz':
    case 'Fl Oz':
      return 'fl oz';
  }

  // fallback
  return kCanonicalUnits.first;
}
