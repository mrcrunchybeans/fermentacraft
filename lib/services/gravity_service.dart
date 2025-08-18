// lib/services/gravity_service.dart
import 'dart:math';

/// One "gravity point" is 0.001 SG. 1.050 → 50 points.
double _pointsFromSg(double sg) => max(0, (sg - 1.0) * 1000.0);

/// Table-sugar yield (ppg). Honey is lower, ~35 ppg.
const double _ppgSucrose = 46.0;
const double _ppgHoneyDefault = 35.0;

/// Typical volume displacement (US gal) per lb of ingredient.
const double _volPerLbHoneyGal = 1.0 / 11.9; // ≈0.084 gal/lb
const double _volPerLbFruitGal = 0.11;       // empirical average for whole fruit/puree

/// A single fermentable or liquid in the must.
class FermentableItem {
  final bool isLiquid;

  /// If isLiquid:true and you measured volume directly (gal).
  final double? volumeGal;

  /// SG of the liquid (1.000 for water). Used only when volumeGal > 0.
  final double? sg;

  /// If you measured by weight (lb). Used with `ppg`, or fruitJuiceSg/fruitBrix.
  final double? weightLb;

  /// Points per pound per gallon. (Sugar≈46, Honey≈35). Used if provided.
  final double? ppg;

  /// Optional explicit volume from this item's weight (gal).
  /// If not provided, honey/fruit will get sensible defaults.
  final double? volumeFromWeightGal;

  /// If you’re entering fruit by weight, the SG of the juice (e.g. 1.031).
  final double? fruitJuiceSg;

  /// If you’re entering fruit by weight, the Brix (%) of that fruit.
  final double? fruitBrix;

  /// Optional hint to pick defaults: "honey", "fruit", "sugar", etc.
  final String? kind;

  const FermentableItem({
    required this.isLiquid,
    this.volumeGal,
    this.sg,
    this.weightLb,
    this.ppg,
    this.volumeFromWeightGal,
    this.fruitJuiceSg,
    this.fruitBrix,
    this.kind,
  });

  bool get _looksLikeHoney => (kind?.toLowerCase().contains('honey') ?? false);

  bool get _looksLikeFruit {
    final k = (kind ?? '').toLowerCase();
    return k.contains('fruit') || k.contains('berry') || k.contains('puree') || k.contains('juice');
  }

  /// Default volume contribution from weight if not explicitly provided.
  double get defaultVolumeFromWeightGal {
    if (volumeFromWeightGal != null) return volumeFromWeightGal!;
    final w = (weightLb ?? 0);
    if (w <= 0) return 0.0;

    if (_looksLikeHoney) return w * _volPerLbHoneyGal;
    if (_looksLikeFruit || fruitJuiceSg != null || fruitBrix != null) {
      return w * _volPerLbFruitGal;
    }
    // Most dry sugars/DME we treat as negligible volume in must.
    return 0.0;
  }

  /// Points contributed by this item *before* dividing by total volume.
  double get gravityPoints {
    // 1) Liquids by volume: points = (SG-1)*1000 * gallons
    if (isLiquid && (volumeGal ?? 0) > 0) {
      final s = (sg ?? 1.0);
      final v = volumeGal!;
      return _pointsFromSg(s) * v;
    }

    // 2) If we have weight + explicit PPG, use it.
    final w = (weightLb ?? 0);
    if (w > 0 && ppg != null) return w * ppg!;

    // 3) Fruit by weight with juice SG: treat as sugary liquid equal to fruit volume.
    if (w > 0 && fruitJuiceSg != null) {
      final v = defaultVolumeFromWeightGal;
      if (v <= 0) return 0.0;
      return _pointsFromSg(fruitJuiceSg!) * v;
    }

    // 4) Fruit by weight with Brix: convert sugar mass → table-sugar equivalent points.
    if (w > 0 && fruitBrix != null) {
      final sugarLb = w * (fruitBrix! / 100.0); // lb sugar inside that fruit
      return sugarLb * _ppgSucrose;
    }

    // 5) Honey by weight without explicit ppg: use default honey ppg.
    if (w > 0 && _looksLikeHoney) {
      return w * _ppgHoneyDefault;
    }

    return 0.0;
  }

  /// Volume this item contributes to the final must (gal).
  double get volumeContributionGal {
    if (isLiquid) return (volumeGal ?? 0);
    // dry/weight path
    return defaultVolumeFromWeightGal;
  }
}

class GravityResult {
  final double totalVolumeGal;
  final double og;

  const GravityResult({required this.totalVolumeGal, required this.og});
}

class GravityService {
  /// Core estimator. Give it all liquids (water & juices) and all fermentables.
  static GravityResult estimate(List<FermentableItem> items) {
    double totalVol = 0.0;
    double totalPoints = 0.0;

    for (final i in items) {
      totalVol += i.volumeContributionGal;
      totalPoints += i.gravityPoints;
    }

    if (totalVol <= 0) {
      return const GravityResult(totalVolumeGal: 0, og: 1.000);
    }

    final og = 1.0 + (totalPoints / totalVol) / 1000.0;
    return GravityResult(totalVolumeGal: totalVol, og: og);
  }

  /// ABV ≈ (OG - FG) * 131.25
  static double abv({required double og, required double fg}) {
    return max(0.0, (og - fg) * 131.25);
  }

  /// Helpers (typed as double so callers don’t fight with `num`)
  static double pointsFromSgAndVolume(double sg, double gallons) =>
      _pointsFromSg(sg) * max(0.0, gallons);

  static double ogFromPointsAndVolume(double points, double gallons) {
    if (gallons <= 0) return 1.000;
    return 1.0 + (points / gallons) / 1000.0;
  }
}
