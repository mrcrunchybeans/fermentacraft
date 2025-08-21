// lib/models/enums.dart

enum FermentableType {
  fruit,
  sugar,
  honey,
  juice,
  water,
  syrup,
  other,
}

/// App-wide metadata for fermentables.
extension FermentableTypeX on FermentableType {
  /// Human-readable label for UI.
  String get label => switch (this) {
        FermentableType.fruit => 'Fruit',
        FermentableType.sugar => 'Sugar (dry)',
        FermentableType.honey => 'Honey',
        FermentableType.juice => 'Juice',
        FermentableType.water => 'Water',
        FermentableType.syrup => 'Syrup',
        FermentableType.other => 'Other',
      };

  /// Typical sugar concentration (%) if not provided by USDA or user.
  double get defaultBrix => switch (this) {
        FermentableType.fruit => 12.0,    // average fresh fruit
        FermentableType.sugar => 100.0,   // dry sugar is ~100% sugar
        FermentableType.honey => 80.0,    // typical honey
        FermentableType.juice => 12.0,    // typical juice
        FermentableType.water => 0.0,
        FermentableType.syrup => 65.0,    // table syrup range
        FermentableType.other => 0.0,
      };

  /// Typical density in g/mL for conversions when needed.
  /// Used as a *fallback*; we still normalize incoming densities.
  double get defaultDensity => switch (this) {
        FermentableType.fruit => 1.00,    // treat as solid: no auto W<->V
        FermentableType.sugar => 1.00,    // solid; density here is not used for auto-convert
        FermentableType.honey => 1.42,    // honey (room temp)
        FermentableType.juice => 1.045,   // depends on Bx; this is a common ballpark
        FermentableType.water => 1.00,
        FermentableType.syrup => 1.30,    // generic syrup
        FermentableType.other => 1.00,
      };

  /// Only liquids should auto-convert weight<->volume.
  bool get isLiquid => switch (this) {
        FermentableType.honey ||
        FermentableType.juice ||
        FermentableType.water ||
        FermentableType.syrup => true,
        _ => false,
      };
}

// ===================== ADDED CODE BELOW THIS LINE =====================

enum WeightUnit { grams, kilograms, pounds, ounces }

extension WeightUnitX on WeightUnit {
  String get label => switch (this) {
        WeightUnit.grams => 'g',
        WeightUnit.kilograms => 'kg',
        WeightUnit.pounds => 'lb',
        WeightUnit.ounces => 'oz',
      };

  double toGrams(double value) => switch (this) {
        WeightUnit.grams => value,
        WeightUnit.kilograms => value * 1000.0,
        WeightUnit.pounds => value * 453.59237,
        WeightUnit.ounces => value * 28.349523125,
      };

  double fromGrams(double grams) => switch (this) {
        WeightUnit.grams => grams,
        WeightUnit.kilograms => grams / 1000.0,
        WeightUnit.pounds => grams / 453.59237,
        WeightUnit.ounces => grams / 28.349523125,
      };
}

enum VolumeUiUnit { ml, liters, flOz, cups, gallons }

extension VolumeUiUnitX on VolumeUiUnit {
  String get label => switch (this) {
        VolumeUiUnit.ml => 'mL',
        VolumeUiUnit.liters => 'L',
        VolumeUiUnit.flOz => 'fl oz',
        VolumeUiUnit.cups => 'cup',
        VolumeUiUnit.gallons => 'gal',
      };

  double toMl(double value) => switch (this) {
        VolumeUiUnit.ml => value,
        VolumeUiUnit.liters => value * 1000.0,
        VolumeUiUnit.flOz => value * 29.5735295625,
        VolumeUiUnit.cups => value * 236.5882365,
        VolumeUiUnit.gallons => value * 3785.411784,
      };

  double fromMl(double ml) => switch (this) {
        VolumeUiUnit.ml => ml,
        VolumeUiUnit.liters => ml / 1000.0,
        VolumeUiUnit.flOz => ml / 29.5735295625,
        VolumeUiUnit.cups => ml / 236.5882365,
        VolumeUiUnit.gallons => ml / 3785.411784,
      };
}

// Fruit categories to estimate volume contribution for solid fruit
enum FruitCategory { berries, stone, pome, tropical, other }

extension FruitCategoryX on FruitCategory {
  String get label => switch (this) {
        FruitCategory.berries => 'Berries',
        FruitCategory.stone => 'Stone fruit',
        FruitCategory.pome => 'Apples & pears',
        FruitCategory.tropical => 'Tropical',
        FruitCategory.other => 'Other',
      };

  /// Typical free-juice + pulp contribution when thawed/crushed (US gal per lb)
  double get defaultGalPerLb => switch (this) {
        FruitCategory.berries => 0.11,   // 0.10–0.12
        FruitCategory.stone => 0.10,     // 0.09–0.11
        FruitCategory.pome => 0.095,     // 0.08–0.10
        FruitCategory.tropical => 0.12,  // often juicy
        FruitCategory.other => 0.10,
      };
}
