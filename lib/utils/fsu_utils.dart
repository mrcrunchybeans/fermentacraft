/// Calculates FSU (Fermentation Speed Unit)
/// Based on temperature (°C) and specific gravity (SG)
/// Adapted from cider-specific guidance
double calculateFSU(double temperatureC, double sg) {
  // Prevent invalid values
  if (temperatureC <= 0 || sg < 0.990 || sg > 1.150) return 0;

  // This is a placeholder formula — update if you have a more precise one.
  final tempFactor = (temperatureC - 10) * 0.5;
  final gravityFactor = (sg - 1.000) * 1000;

  return double.parse((tempFactor * gravityFactor).toStringAsFixed(2));
}
