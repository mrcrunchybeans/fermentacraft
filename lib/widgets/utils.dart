class CiderUtils {
  /// Acidity classification based on pH
  ///
  /// | pH Range   | Description                         |
  /// |------------|-------------------------------------|
  /// | < 3.2      | Very High (Cooking apples, crabs)   |
  /// | 3.2–3.4    | High (Many table apples)            |
  /// | 3.4–3.6    | Medium (Balanced, ideal for cider)  |
  /// | > 3.6      | Low (Sweet apples)                  |
  static String classifyAcidity(double ph) {
    if (ph >= 0 && ph < 3.2) {
      return 'Very High (Cooking apples, crabs)';
    }
    if (ph >= 3.2 && ph < 3.4) {
      return 'High (Many table apples)';
    }
    if (ph >= 3.4 && ph < 3.6) {
      return 'Medium (Balanced, ideal for cider)';
    }
    if (ph >= 3.6) {
      return 'Low (Sweet apples)';
    }
    return 'Unknown';
  }

  /// Acidity classification based on TA (titratable acidity in g/L as malic acid)
  ///
  /// | TA (g/L)   | Description                         |
  /// |------------|-------------------------------------|
  /// | < 4.5      | Low (Sweet apples)                  |
  /// | 4.5–7.5    | Medium (Balanced, ideal for cider)  |
  /// | 7.5–11     | High (Many table apples)            |
  /// | > 11       | Very High (Cooking apples, crabs)   |
  static String classifyTA(double ta) {
    if (ta < 4.5) {
      return 'Low (Sweet apples)';
    }
    if (ta < 7.5) {
      return 'Medium (Balanced, ideal for cider)';
    }
    if (ta < 11) {
      return 'High (Many table apples)';
    }
    return 'Very High (Cooking apples, crabs)';
  }

  /// Sugar content classification based on SG (specific gravity)
  ///
  /// | SG         | Description                         |
  /// |------------|-------------------------------------|
  /// | ≤ 1.045    | Low (Summer/cooking apples)         |
  /// | ≤ 1.060    | Medium (Good)                       |
  /// | ≤ 1.070    | High (Ideal)                        |
  /// | > 1.070    | Very High (Crabapples, exceptional) |
  static String classifySugarSG(double sg) {
    if (sg <= 1.045) {
      return 'Low (Summer/cooking apples)';
    }
    if (sg <= 1.060) {
      return 'Medium (Good)';
    }
    if (sg <= 1.070) {
      return 'High (Ideal)';
    }
    return 'Very High (Crabapples, exceptional)';
  }

   static double correctedSgJolicoeur(double measuredSG, double tempF) {
    final Map<int, double> tempCorrections = {
      32: -0.002,
      40: -0.0015,
      50: -0.001,
      60: 0.0,
      70: 0.001,
      80: 0.002,
      90: 0.003,
      100: 0.004,
    };

    if (tempF <= 32) return measuredSG - tempCorrections[32]!;
    if (tempF >= 100) return measuredSG - tempCorrections[100]!;

    int lower = tempCorrections.keys.lastWhere((t) => t <= tempF);
    int upper = tempCorrections.keys.firstWhere((t) => t >= tempF);

    // At exactly 60°F (calibration temp), no correction needed
    if (lower == upper) return measuredSG;

    double lowerCorrection = tempCorrections[lower]!;
    double upperCorrection = tempCorrections[upper]!;

    double fraction = (tempF - lower) / (upper - lower);
    double interpolatedCorrection =
        lowerCorrection + fraction * (upperCorrection - lowerCorrection);

    return measuredSG - interpolatedCorrection;
  }


  /// Calculate ABV from OG and FG
  static double calculateABV(double og, double fg) {
    return (og - fg) * 131.25;
  }

  /// Estimate FG assuming full fermentation
  static double estimateFG() {
    return 1.000;
  }

  /// Recommended free SO₂ level (ppm) from pH
  ///
  /// Based on Claude Jolicoeur’s chart (pg. 213):
  ///
  /// | pH   | Free SO₂ (ppm) |
  /// |------|----------------|
  /// | ≤3.0 | 30             |
  /// | ≤3.1 | 40             |
  /// | ≤3.2 | 50             |
  /// | ≤3.3 | 60             |
  /// | ≤3.4 | 75             |
  /// | ≤3.5 | 90             |
  /// | ≤3.6 | 120            |
  /// | ≤3.7 | 150            |
  /// | ≤3.8 | 200            |
  /// | >3.8 | 250            |
  static double recommendedFreeSO2ppm(double ph) {
    if (ph <= 3.0) {
      return 30;
    }
    if (ph <= 3.1) {
      return 40;
    }
    if (ph <= 3.2) {
      return 50;
    }
    if (ph <= 3.3) {
      return 60;
    }
    if (ph <= 3.4) {
      return 75;
    }
    if (ph <= 3.5) {
      return 90;
    }
    if (ph <= 3.6) {
      return 120;
    }
    if (ph <= 3.7) {
      return 150;
    }
    if (ph <= 3.8) {
      return 200;
    }
    return 250;
  }

  /// Converts Campden tablets to grams of potassium metabisulphite
  /// (1 tablet ≈ 0.44g)
  static double campdenToGrams(int tablets) {
    return tablets * 0.44;
  }

  /// Calculate grams of sulfite (KMS) needed to hit target ppm in given volume
  static double sulfiteGramsForVolume(double volumeLiters, double targetPPM) {
    double totalMg = targetPPM * volumeLiters;
    return totalMg / 1000.0;
  }

  /// Convert gallons to liters
  static double gallonsToLiters(double gallons) {
    return gallons * 3.78541;
  }

  /// Convert milliliters to ounces
  static double mlToOz(double ml) {
    return ml * 0.033814;
  }

  /// Convert ounces to milliliters
  static double ozToMl(double oz) {
    return oz * 29.5735;
  }

  /// Round to two decimal places
  static double round2(double val) {
    return (val * 100).round() / 100.0;
  }

  /// Return a default FG of 1.000 (placeholder for future attenuation calc)
  static double calculateFG(double og) {
    return estimateFG();
  }
}

double correctedSGForTemp(double measuredSG, double tempF) {
  final correction = (1.313454 - 0.132674 * tempF + 0.002057793 * tempF * tempF - 0.000002627634 * tempF * tempF * tempF);
  return measuredSG + (correction * 0.001);
}
