// lib/utils/calc_utils.dart
import 'dart:math';

class CalcUtils {
  // From spec: SG from Brix
  static double sgFromBrix(double brix) {
    return 1.0 + (brix / (258.6 - ((brix / 258.2) * 227.1)));
  }

  static double brixFromSg(double sg) {
    final b = 182.4601 * pow(sg, 3) - 775.6821 * pow(sg, 2) + 1262.7794 * sg - 669.5622;
    return b.toDouble();
  }

  static double abvFromSG(double og, double fg) {
    return (og - fg) * 131.25;
  }

  /// Water to add to dilute from currentSg to targetSg at currentVolumeL
  static String formatWaterToDilute({
    required double currentSg,
    required double targetSg,
    required double currentVolumeL,
  }) {
    if (targetSg >= currentSg || targetSg <= 0) return 'No dilution possible/needed';
    final b1 = brixFromSg(currentSg);
    final b2 = brixFromSg(targetSg);
    final v2 = (b1 * currentVolumeL) / b2;
    final waterToAddL = max(0, v2 - currentVolumeL);
    return '${waterToAddL.toStringAsFixed(3)} L water';
  }
}
