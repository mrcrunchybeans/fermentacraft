
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/ingredient.dart';
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

  /// More accurate ABV formula based on density changes
  /// [(76.08 × (OG - FG)) / (1.775 - OG)] × (FG / 0.794)
  static double calculateABVBetter(double og, double fg) {
    if (og <= fg || og < 0.9 || fg < 0.9) return 0.0;

    return ((76.08 * (og - fg)) / (1.775 - og)) * (fg / 0.794);
  }

  /// Correct SG based on temperature using polynomial formula (calibrated at 60°F)
static double correctedSG(double measuredSG, double tempF) {
  const double calibrationTempF = 60.0;

  final double correction = 1.313454
      - 0.132674 * tempF
      + 0.002057793 * (tempF * tempF)
      - 0.000002627634 * (tempF * tempF * tempF);

  const double baseCorrection = 1.313454
      - 0.132674 * calibrationTempF
      + 0.002057793 * (calibrationTempF * calibrationTempF)
      - 0.000002627634 * (calibrationTempF * calibrationTempF * calibrationTempF);

  final double correctionFactor = correction - baseCorrection;
  return measuredSG + (correctionFactor / 1000.0); // apply correction in SG units
}


  /// Calculate ABV from OG and FG
  static double calculateABV(double og, double fg) {
    return max(0.0, (og - fg) * 131.25);
  }


/// Calculates the weighted average OG from a list of ingredients.
/// Each ingredient must have a non-null SG and volume.
static double? calculateWeightedAverageOG(List<Ingredient> ingredients) {
  double totalLiters = 0.0;
  double weightedOGSum = 0.0;

  for (final f in ingredients) {
    if (f.sg == null || f.amount == null || f.unit == null) continue;

    final double volumeLiters = f.amount! * f.unit!.toLiters;
    totalLiters += volumeLiters;
    weightedOGSum += f.sg! * volumeLiters;
  }

  if (totalLiters == 0) return null;

  return weightedOGSum / totalLiters;
}


/// Returns the best OG value to use for ABV calculation based on user preferences.
///
/// Priority:
/// 1. If useAdjustedOG is true → use targetMustSG (if set)
/// 2. Else → use weightedAverageOG (if available)
/// 3. Else → use measuredMustSG (if set)
/// 4. Else → fallback to og (default single OG)
static double getOriginalGravityForABV({
  required bool useAdjustedOG,
  required double? targetMustSG,
  required double? weightedAverageOG,
  required double? measuredMustSG,
  required double? og,
}) {
  if (useAdjustedOG && targetMustSG != null) return targetMustSG;
  if (!useAdjustedOG && weightedAverageOG != null) return weightedAverageOG;
  if (!useAdjustedOG && measuredMustSG != null) return measuredMustSG;
  return og ?? 1.000;
}

/// Returns the OG used for calculation and optionally auto-fills Measured SG
static double autofillMeasuredSGIfEmpty({
  required bool useAdjustedOG,
  required double? targetMustSG,
  required double? weightedAverageOG,
  required double? measuredMustSG,
  required double? og,
  required TextEditingController measuredMustSGController,
}) {
  final ogUsed = getOriginalGravityForABV(
    useAdjustedOG: useAdjustedOG,
    targetMustSG: targetMustSG,
    weightedAverageOG: weightedAverageOG,
    measuredMustSG: measuredMustSG,
    og: og,
  );

  final shouldAutofill =
      (measuredMustSG == null || measuredMustSGController.text.trim().isEmpty) &&
      ogUsed != 1.000;

  if (shouldAutofill) {
    measuredMustSGController.text = ogUsed.toStringAsFixed(3);
  }

  return ogUsed;
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
  final points = {
    3.0: 40,
    3.1: 50,
    3.2: 60,
    3.3: 70,
    3.4: 80,
    3.5: 100,
    3.6: 125,
    3.7: 150,
    3.8: 190,
    3.9: 220,
  };

  // Clamp input pH to range
  if (ph <= 3.0) return 40;
  if (ph >= 3.9) return 220;

  // Find nearest two points for linear interpolation
  final keys = points.keys.toList()..sort();
  for (var i = 0; i < keys.length - 1; i++) {
    final x0 = keys[i];
    final x1 = keys[i + 1];
    if (ph >= x0 && ph <= x1) {
      final y0 = points[x0]!;
      final y1 = points[x1]!;
      final slope = (y1 - y0) / (x1 - x0);
      return y0 + slope * (ph - x0);
    }
  }

  return 0; // Should never hit this
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

  static double ppmToGrams(double gallons, int ppm) {
  return ppm * gallons * 3.78541 / 1000;
}

}

enum VolumeUnit {
  liters("L", 1.0),
  gallons("gal", 3.78541),
  ounces("oz", 0.0295735);

  final String label;
  final double toLiters;

  const VolumeUnit(this.label, this.toLiters);
}


