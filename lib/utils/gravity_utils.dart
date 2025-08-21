/// Converts Specific Gravity (SG) to Brix using polynomial approximation
double sgToBrix(double sg) {
  return (((182.4601 * sg - 775.6821) * sg + 1262.7794) * sg - 669.5622);


}

/// Converts Brix to Specific Gravity (SG)
double brixToSg(double brix) {
  return 1 + (brix / (258.6 - ((brix / 258.2) * 227.1)));
}

/// Convert between any supported gravity units (SG, °Brix, °Plato, SGP)
double convertGravity(double value, String fromUnit, String toUnit) {
  if (fromUnit == toUnit) return value;

  // Treat Plato as Brix
  if ((fromUnit == '°Plato' && toUnit == '°Brix') ||
      (fromUnit == '°Brix' && toUnit == '°Plato')) {
    return value;
  }

  // Convert to SG first
  double sg;
  switch (fromUnit) {
    case 'SG':
      sg = value;
      break;
    case 'SGP':
      sg = 1.000 + (value / 1000);
      break;
    case '°Brix':
    case '°Plato':
      sg = brixToSg(value);
      break;
    default:
      sg = value;
  }

  // Convert SG to target unit
  switch (toUnit) {
    case 'SG':
      return sg;
    case 'SGP':
      return (sg - 1.000) * 1000;
    case '°Brix':
    case '°Plato':
      return sgToBrix(sg);
    default:
      return value;
  }
}

/// Format SG as a 1.000-style string
String formatGravity(double sg) => sg.toStringAsFixed(3);

/// Format Brix as 7.5°Bx
String formatBrix(double brix) => '${brix.toStringAsFixed(1)}°Bx';

/// Accepts "1.045" or "1045" and normalizes to SG (e.g., 1.045).
double? parseUserSg(String raw) {
  final v = double.tryParse(raw.trim());
  if (v == null) return null;
  if (v >= 10 && v < 200) return v / 1000.0; // "1045" -> 1.045
  if (v > 0.9 && v < 2.0) return v;
  return null;
}