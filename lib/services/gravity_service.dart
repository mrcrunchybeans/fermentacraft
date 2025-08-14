// lib/services/gravity_service.dart
class FermentableItem {
  final bool isLiquid;    // true for water/juice/must/concentrate-as-liquid
  final double volumeGal; // liquids only (0 for dry items)
  final double? sg;       // optional SG for liquids (>1.000 contributes points)
  final double weightLb;  // dry items only (0 for liquids)
  final double? ppg;      // e.g., 46 for sucrose/dextrose; 35 for honey

  const FermentableItem({
    required this.isLiquid,
    this.volumeGal = 0,
    this.sg,
    this.weightLb = 0,
    this.ppg,
  });
}

class GravityResult {
  final double totalVolumeGal; // sum of liquid volumes only
  final double estimatedOG;    // 1.000 if no points
  const GravityResult(this.totalVolumeGal, this.estimatedOG);
}

class GravityService {
  static GravityResult estimate(List<FermentableItem> items) {
    double volGal = 0.0;
    double totalPoints = 0.0;

    for (final i in items) {
      if (i.isLiquid && i.volumeGal > 0) {
        volGal += i.volumeGal;
        if (i.sg != null && i.sg! > 1.0) {
          final pts = (i.sg! - 1.0) * 1000.0;   // points per gallon
          totalPoints += pts * i.volumeGal;     // liquid contribution
        }
      } else if (!i.isLiquid && i.weightLb > 0 && (i.ppg ?? 0) > 0) {
        totalPoints += i.weightLb * i.ppg!;     // dry sugar contribution (no volume)
      }
    }

    if (volGal <= 0) return const GravityResult(0.0, 1.000);
    final og = 1.0 + (totalPoints / (1000.0 * volGal));
    return GravityResult(volGal, _round3(og));
  }

  static double abv({required double og, required double fg}) =>
      (og - fg) * 131.25;

  static double _round3(double v) => double.parse(v.toStringAsFixed(3));
}
