class So2Utils {
  /// Interpolates the recommended free SO₂ (ppm) based on pH
  static double getRecommendedFreeSO2(double pH) {
    if (pH <= 3.0) return 40;
    if (pH >= 3.9) return 200;
    return 40 + (pH - 3.0) * ((200 - 40) / (3.9 - 3.0));
  }

  /// Calculates grams of potassium metabisulfite needed for a target ppm
  static double calculateSulfiteGrams({
    required double volumeLiters,
    required double targetPPM,
  }) {
    return (volumeLiters * targetPPM) / 1000;
  }

  /// Converts grams to Campden tablets (1 tab ≈ 0.44g K2S2O5)
  static double gramsToCampdenTabs(double grams) {
    return grams / 0.44;
  }

  /// Converts Campden tablets to grams
  static double campdenTabsToGrams(int tablets) {
    return tablets * 0.44;
  }
}
