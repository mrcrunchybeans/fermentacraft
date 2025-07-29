/// Converts Specific Gravity (SG) to Brix using polynomial approximation
double sgToBrix(double sg) {
  return (182.4601 * sg - 775.6821) * sg + 1262.7794;
}

/// Converts Brix to Specific Gravity (SG)
double brixToSg(double brix) {
  return 1 + (brix / (258.6 - ((brix / 258.2) * 227.1)));
}

/// Format SG as a 1.000-style string
String formatGravity(double sg) => sg.toStringAsFixed(3);

/// Format Brix as 7.5°Bx
String formatBrix(double brix) => '${brix.toStringAsFixed(1)}°Bx';
