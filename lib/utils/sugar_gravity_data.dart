class SugarType {
  final String name;
  final double sgPerGramPerLiter; // How much SG 1g/L raises

  const SugarType(this.name, this.sgPerGramPerLiter);
}

final List<SugarType> sugarTypes = [
  const SugarType("Table Sugar (sucrose)", 0.00046),
  const SugarType("Corn Sugar (dextrose)", 0.00042),
  const SugarType("Honey", 0.00035),
  const SugarType("Maple Syrup", 0.00030),
  const SugarType("Apple Juice Concentrate", 0.00036),
];

class SugarGravityData {
  static const Map<String, double> ppgMap = {
    'Table Sugar (sucrose)': 46,
    'Corn Sugar (dextrose)': 42,
    'Honey': 35,
    'Maple Syrup': 30,
    'Apple Juice Concentrate': 36,
  };

  // Converts SG to gravity points (e.g. 1.050 = 50)
  static double _sgToPoints(double sg) => (sg - 1.0) * 1000;

  /// Returns the grams of sugar needed to raise SG
  static double calculateSugarAddition({
    required double currentSG,
    required double targetSG,
    required double volumeGallons,
    required String sugarType,
  }) {
    final deltaPoints = _sgToPoints(targetSG) - _sgToPoints(currentSG);
    final yieldPerPoundPerGallon = ppgMap[sugarType];

    if (yieldPerPoundPerGallon == null) {
      throw ArgumentError("Unknown sugar type: $sugarType");
    }

    // Pounds of sugar = (Δ points * volume) / ppg
    final pounds = (deltaPoints * volumeGallons) / yieldPerPoundPerGallon;

    // Convert pounds to grams
    final grams = pounds * 453.592;
    return grams;
  }
}

String formatGallonsToGalCupOz(double gallons) {
  final int wholeGallons = gallons.floor();
  final double remainingGallons = gallons - wholeGallons;

  final int totalOz = (remainingGallons * 128).round();
  final int cups = totalOz ~/ 8;
  final int flOz = totalOz % 8;

  List<String> parts = [];

  if (wholeGallons > 0) parts.add("$wholeGallons gal");
  if (cups > 0) parts.add("$cups cup${cups > 1 ? 's' : ''}");
  if (flOz > 0) parts.add("$flOz fl oz");

  return parts.isNotEmpty ? parts.join(', ') : "0 fl oz";
}
