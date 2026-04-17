// lib/controllers/recipe_builder_controller.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/models/enums.dart';
import 'package:fermentacraft/services/usda_service.dart';
import 'package:fermentacraft/models/inventory_item.dart';
import 'package:fermentacraft/utils/gravity_utils.dart' as gu;

String _genId() => '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999999)}';

/// Normalize densities into g/mL (~ SG).
/// Heuristics to catch common data-entry/unit mistakes:
/// - 1420 (g/L) -> 1.420
/// - 14.2  (x10) -> 1.42
/// - 0.14  (/10) -> 1.4
double _normalizeDensity(double? d, {required double fallback}) {
  if (d == null) return fallback;
  if (d >= 100.0) return d / 1000.0;   // g/L → g/mL
  if (d > 5.0 && d < 25.0) return d / 10.0; // 14.2 → 1.42
  if (d < 0.2) return d * 10.0;        // 0.14 → 1.4
  return d;
}
// Treat two volumes as "the same" if they're within 5 mL (prevents fighting user edits).
bool _isClose(double a, double b, [double eps = 5.0]) => (a - b).abs() <= eps;

// Unit constants (lowerCamelCase to satisfy linter)
const double _lbsPerGram = 0.00220462262185;
const double _mlPerGal   = 3785.411784;

@immutable
class FermentableLine {
  final String id;
  final String name;
  final FermentableType type;
  final double? brix;       // %
  final double? density;    // g/mL (== SG)
  final double? weightG;    // grams
  final double? volumeMl;   // milliliters
  final bool syncWeightVolume;
  final bool usdaBacked;
  final int? usdaFdcId;
  final FruitCategory? fruitCategory;     // only used when type == FermentableType.fruit
  final double? fruitYieldGalPerLb;       // optional override per line
  final WeightUnit? userWeightUnit;
  final VolumeUiUnit? userVolumeUnit;

  const FermentableLine._internal({
    required this.id,
    this.name = '',
    this.type = FermentableType.fruit,
    this.brix,
    this.density,
    this.weightG,
    this.volumeMl,
    this.syncWeightVolume = true,
    this.usdaBacked = false,
    this.usdaFdcId,
    this.fruitCategory,
    this.fruitYieldGalPerLb,
    this.userWeightUnit,
    this.userVolumeUnit,
  });

  factory FermentableLine({
    String? id,
    String name = '',
    FermentableType type = FermentableType.fruit,
    double? brix,
    double? density,
    double? weightG,
    double? volumeMl,
    bool syncWeightVolume = true,
    bool usdaBacked = false,
    int? usdaFdcId,
    FruitCategory? fruitCategory,
    double? fruitYieldGalPerLb,
    WeightUnit? userWeightUnit,
    VolumeUiUnit? userVolumeUnit,
  }) {
    return FermentableLine._internal(
      id: id ?? _genId(),
      name: name,
      type: type,
      brix: brix,
      density: density,
      weightG: weightG,
      volumeMl: volumeMl,
      syncWeightVolume: syncWeightVolume,
      usdaBacked: usdaBacked,
      usdaFdcId: usdaFdcId,
      fruitCategory: fruitCategory,
      fruitYieldGalPerLb: fruitYieldGalPerLb,
      userWeightUnit: userWeightUnit,
      userVolumeUnit: userVolumeUnit,
    );
  }

  FermentableLine copyWith({
    String? id,
    String? name,
    FermentableType? type,
    double? brix,
    double? density,
    double? weightG,
    double? volumeMl,
    bool? syncWeightVolume,
    bool? usdaBacked,
    int? usdaFdcId,
    FruitCategory? fruitCategory,
    double? fruitYieldGalPerLb,
    WeightUnit? userWeightUnit,
    VolumeUiUnit? userVolumeUnit,
  }) {
    return FermentableLine._internal(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      brix: brix ?? this.brix,
      density: density ?? this.density,
      weightG: weightG ?? this.weightG,
      volumeMl: volumeMl ?? this.volumeMl,
      syncWeightVolume: syncWeightVolume ?? this.syncWeightVolume,
      usdaBacked: usdaBacked ?? this.usdaBacked,
      usdaFdcId: usdaFdcId ?? this.usdaFdcId,
      fruitCategory: fruitCategory ?? this.fruitCategory,
      fruitYieldGalPerLb: fruitYieldGalPerLb ?? this.fruitYieldGalPerLb,
      userWeightUnit: userWeightUnit ?? this.userWeightUnit,
      userVolumeUnit: userVolumeUnit ?? this.userVolumeUnit,
    );
  }

  /// Recalculates one value (weight or volume) if the other is set and sync is enabled.
  FermentableLine recalculate() {
    if (!syncWeightVolume || !type.isLiquid || density == null || density! <= 0) {
      return this;
    }
    final hasWeight = (weightG ?? 0) > 0;
    final hasVolume = (volumeMl ?? 0) > 0;
    if (hasWeight && !hasVolume) {
      return copyWith(volumeMl: weightG! / density!);
    } else if (hasVolume && !hasWeight) {
      return copyWith(weightG: volumeMl! * density!);
    }
    return this;
  }

  double sugarGrams() {
    final b = (brix ?? type.defaultBrix) / 100.0;
    if (weightG != null) return b * weightG!;
    if (volumeMl != null) {
      final dens = _normalizeDensity(density ?? type.defaultDensity, fallback: type.defaultDensity);
      return b * (volumeMl! * dens);
    }
    return 0.0;
  }

   /// Only liquids contribute volume when only weight is present.
  /// For fruit solids, if user didn't enter a volume, we estimate from weight.
  double liquidMl() {
    // If user explicitly set a volume, always respect it
    if (volumeMl != null && volumeMl! > 0) return volumeMl!;

    // Liquids: compute from weight via density
    if (weightG != null && type.isLiquid) {
      final dens = _normalizeDensity(density ?? type.defaultDensity, fallback: type.defaultDensity);
      return weightG! / dens;
    }

    // Fruit solids: estimate contribution if no explicit volume
    if (type == FermentableType.fruit) {
      return _estimatedFruitMl();
    }

    return 0.0;
  }

    /// Estimated must volume contribution for solid fruit, in mL.
  /// Used only when type == fruit AND user did not explicitly set volume.
  double _estimatedFruitMl() {
    if (type != FermentableType.fruit) return 0.0;
    final g = weightG ?? 0.0;
    if (g <= 0) return 0.0;

    final pounds = g * _lbsPerGram;

    // Choose a category (default berries) and yield
    final cat = fruitCategory ?? FruitCategory.berries;
    final baseGalPerLb = fruitYieldGalPerLb ?? cat.defaultGalPerLb;

    // Clamp to a sane range so typos don't explode estimates
    final galPerLb = baseGalPerLb.clamp(0.05, 0.20);

    return pounds * galPerLb * _mlPerGal;
  }

}

class MustStats {
  final double totalSugarG;
  final double totalVolumeMl;
  final double brix;
  final double sg;
  double totalVolumeIn(VolumeUiUnit unit) => unit.fromMl(totalVolumeMl);


  const MustStats({
    required this.totalSugarG,
    required this.totalVolumeMl,
    required this.brix,
    required this.sg,
  });

  double get estimatedOg => sg;
  double get totalVolumeL => totalVolumeMl / 1000.0;
}

class RecipeBuilderController extends ChangeNotifier {
  RecipeBuilderController({required this.usda});
// Default stats volume unit (US gallons)
VolumeUiUnit _statsVolumeUnit = VolumeUiUnit.gallons;
VolumeUiUnit get statsVolumeUnit => _statsVolumeUnit;

void setStatsVolumeUnit(VolumeUiUnit unit) {
  if (_statsVolumeUnit == unit) return;
  _statsVolumeUnit = unit;
  _safeNotify();
}
  final UsdaService usda;

  // ---------------- Fermentables ----------------
  final List<FermentableLine> fermentables = <FermentableLine>[];
  final Map<String, List<UsdaChoice>> _suggestions = <String, List<UsdaChoice>>{};
  final Map<String, Timer?> _nameTimers = <String, Timer?>{};
  final Map<String, int> _queryTokens = <String, int>{};

  bool _disposed = false;
  void _safeNotify() {
    if (_disposed) return;
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _nameTimers.values) {
      t?.cancel();
    }
    _nameTimers.clear();
    super.dispose();
  }

  /// Call this before showing fields if editing an existing recipe.
  void seedFromRecipe(RecipeModel r) {
    // ---------- Fermentables ----------
    fermentables
      ..clear()
      ..addAll(r.safeIngredients.map((m) {
        final type = FermentableType.values.firstWhere(
          (t) => t.name == (m['type'] ?? '').toString(),
          orElse: () => FermentableType.sugar,
        );

        int? fdc;
        final rawId = m['usdaFdcId'];
        if (rawId is int) {
          fdc = rawId;
        } else if (rawId is String) {
          fdc = int.tryParse(rawId);
        }

        final rawDensity = (m['density'] as num?)?.toDouble();
        final dens = _normalizeDensity(rawDensity, fallback: type.defaultDensity);

        return FermentableLine(
          id: (m['id'] ?? _genId()).toString(),
          name: (m['name'] ?? '').toString(),
          type: type,
          brix: (m['brix'] as num?)?.toDouble(),
          density: dens,
          weightG: (m['weightG'] as num?)?.toDouble(),
          volumeMl: (m['volumeMl'] as num?)?.toDouble(),
          syncWeightVolume: (m['syncWeightVolume'] as bool?) ?? true,
          usdaBacked: m['usdaBacked'] == true,
          usdaFdcId: fdc,
          // Optional restore of fruit metadata if present in saved recipe
        fruitCategory: switch ((m['fruitCategory'] ?? '').toString()) {
          'berries'   => FruitCategory.berries,
          'stone'     => FruitCategory.stone,
          'pome'      => FruitCategory.pome,
          'tropical'  => FruitCategory.tropical,
          'other'     => FruitCategory.other,
          _           => null,
        },
        fruitYieldGalPerLb: (m['fruitYieldGalPerLb'] as num?)?.toDouble(),
        
        userWeightUnit: switch ((m['userWeightUnit'] ?? '').toString()) {
          'grams'     => WeightUnit.grams,
          'kilograms' => WeightUnit.kilograms,
          'pounds'    => WeightUnit.pounds,
          'ounces'    => WeightUnit.ounces,
          _           => null,
        },
        userVolumeUnit: switch ((m['userVolumeUnit'] ?? '').toString()) {
          'ml'        => VolumeUiUnit.ml,
          'liters'    => VolumeUiUnit.liters,
          'flOz'      => VolumeUiUnit.flOz,
          'cups'      => VolumeUiUnit.cups,
          'gallons'   => VolumeUiUnit.gallons,
          _           => null,
        },
        );

      }));

    // ---------- Yeasts ----------
    yeasts
      ..clear()
      ..addAll(r.safeYeast.map((m) {
        return YeastLine(
          id: (m['id'] ?? _genId()).toString(),
          name: (m['name'] ?? '').toString(),
          form: YeastForm.values.firstWhere(
            (f) => f.name == (m['form'] ?? '').toString(),
            orElse: () => YeastForm.dry,
          ),
          quantity: (m['quantity'] as num?)?.toDouble(),
          unit: QtyUnit.values.firstWhere(
            (u) => u.name == (m['unit'] ?? '').toString(),
            orElse: () => QtyUnit.packets,
          ),
          notes: (m['notes'] ?? '').toString(),
        );
      }));

    // ---------- Additives ----------
    additives
      ..clear()
      ..addAll(r.safeAdditives.map((m) {
        return AdditiveLine(
          id: (m['id'] ?? _genId()).toString(),
          name: (m['name'] ?? '').toString(),
          quantity: (m['quantity'] as num?)?.toDouble(),
          unit: QtyUnit.values.firstWhere(
            (u) => u.name == (m['unit'] ?? '').toString(),
            orElse: () => QtyUnit.g,
          ),
          when: (m['when'] ?? '').toString(),
          notes: (m['notes'] ?? '').toString(),
        );
      }));

    // Restore stats volume unit from recipe (per-recipe preference)
    if (r.statsVolumeUnit != null) {
      final vu = VolumeUiUnit.values.firstWhere(
        (v) => v.name == r.statsVolumeUnit,
        orElse: () => VolumeUiUnit.gallons,
      );
      setStatsVolumeUnit(vu);
    }

    recalc();
    notifyListeners();
  }

  MustStats get stats => _calcStats();
  void recalc() => _safeNotify();

  List<UsdaChoice> suggestionsFor(String lineId) =>
      List<UsdaChoice>.unmodifiable(_suggestions[lineId] ?? const []);

  Future<void> onNameChanged(String lineId, String text, {FermentableType? forceType}) async {
    _nameTimers[lineId]?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      _setSuggestions(lineId, const []);
      return;
    }
    final token = (_queryTokens[lineId] ?? 0) + 1;
    _queryTokens[lineId] = token;

    _nameTimers[lineId] = Timer(const Duration(seconds: 1), () async {
      try {
        final raw = await usda.searchFoods(q);
        if (_queryTokens[lineId] != token) return;
        final filtered =
            (forceType == null) ? raw : raw.where((c) => c.type == forceType).toList(growable: false);
        _setSuggestions(lineId, filtered);
      } catch (_) {
        if (_queryTokens[lineId] != token) return;
        _setSuggestions(lineId, const []);
      }
    });
  }

  Future<void> applyUsda(dynamic key, UsdaChoice choice) async {
    final detail = await usda.getFood(choice.fdcId);
    if (key is int) {
      _applyUsdaAt(key, choice, detail);
      return;
    }
    if (key is String) {
      final idx = fermentables.indexWhere((f) => f.id == key);
      if (idx >= 0) _applyUsdaAt(idx, choice, detail);
    }
  }

  Future<void> applyUsdaByIndex(int index, UsdaChoice choice) => applyUsda(index, choice);

  void seedFromInventoryItem(int index, InventoryItem item) {
    if (index < 0 || index >= fermentables.length) return;
    final prev = fermentables[index];

    FermentableType fType = FermentableType.sugar;
    final catLower = item.category.toLowerCase();
    if (catLower.contains('juice')) fType = FermentableType.juice;
    else if (catLower.contains('honey')) fType = FermentableType.honey;
    else if (catLower.contains('fruit')) fType = FermentableType.fruit;
    double dens = item.sg ?? prev.density ?? fType.defaultDensity;
    double brx = item.brix ?? prev.brix ?? fType.defaultBrix;

    if (item.brix != null && item.sg == null) {
      dens = gu.brixToSg(item.brix!);
    } else if (item.sg != null && item.brix == null) {
      brx = gu.sgToBrix(item.sg!);
    }

    _updateAtIndex(index, prev.copyWith(
      name: item.name,
      type: fType,
      density: dens,
      brix: brx,
    ));
  }

  void updateFermentableNameByIndex(int index, String name) {
    if (index < 0 || index >= fermentables.length) return;
    _updateAtIndex(index, fermentables[index].copyWith(name: name));
  }

  /// Generic updater used by the tile when typing directly into fields.
  void updateFermentableByIndex(
    int index, {
    double? brix,
    double? density,
    double? weightG,
    double? volumeMl,
    bool? syncWeightVolume,
  }) {
    if (index < 0 || index >= fermentables.length) return;
    var line = fermentables[index].copyWith(
      brix: brix,
      density: density,
      weightG: weightG,
      volumeMl: volumeMl,
      syncWeightVolume: syncWeightVolume,
    );

    // Normalize density
    final dens = _normalizeDensity(line.density ?? line.type.defaultDensity,
        fallback: line.type.defaultDensity);
    line = line.copyWith(density: dens);

    // For liquids, keep pairs in sync if one side is missing
    if (line.syncWeightVolume && line.type.isLiquid) {
      final hasW = (weightG ?? line.weightG ?? 0) > 0;
      final hasV = (volumeMl ?? line.volumeMl ?? 0) > 0;
      if (hasW && !hasV) {
        line = line.copyWith(volumeMl: (weightG ?? line.weightG)! / dens);
      } else if (hasV && !hasW) {
        line = line.copyWith(weightG: (volumeMl ?? line.volumeMl)! * dens);
      }
    }

    _updateAtIndex(index, line);
  }

  /// Explicit setters for gravity UI
void setBrixAt(int index, double newBrix) {
  if (index < 0 || index >= fermentables.length) return;
  final prev = fermentables[index];
  final newSg = gu.brixToSg(newBrix); // density in g/mL
  _updateAtIndex(index, prev.copyWith(brix: newBrix, density: newSg));
}

void setSgAt(int index, double newSg) {
  if (index < 0 || index >= fermentables.length) return;
  final prev = fermentables[index];
  final newBrix = gu.sgToBrix(newSg);
  _updateAtIndex(index, prev.copyWith(brix: newBrix, density: newSg));
}

void setWeightUnitAt(int index, WeightUnit unit) {
  if (index < 0 || index >= fermentables.length) return;
  _updateAtIndex(index, fermentables[index].copyWith(userWeightUnit: unit));
}

void setVolumeUnitAt(int index, VolumeUiUnit unit) {
  if (index < 0 || index >= fermentables.length) return;
  _updateAtIndex(index, fermentables[index].copyWith(userVolumeUnit: unit));
}
  /// Optional: direct density edit (advanced/hidden UI)
  void setDensityAt(int index, double newDensity) {
    if (index < 0 || index >= fermentables.length) return;
    final prev = fermentables[index];
    final dens = _normalizeDensity(newDensity, fallback: prev.type.defaultDensity);
    final updated = prev.copyWith(
      density: dens,
      brix: gu.sgToBrix(dens),
    );
    _updateAtIndex(index, updated);
  }

    void setFruitCategoryAt(int index, FruitCategory cat) {
    if (index < 0 || index >= fermentables.length) return;
    final prev = fermentables[index];
    _updateAtIndex(index, prev.copyWith(fruitCategory: cat));
  }

  void setFruitYieldGalPerLbAt(int index, double galPerLb) {
    if (index < 0 || index >= fermentables.length) return;
    final prev = fermentables[index];
    _updateAtIndex(index, prev.copyWith(fruitYieldGalPerLb: galPerLb));
  }


  void addFermentable() {
    fermentables.add(FermentableLine());
    _safeNotify();
  }

  void removeFermentable(int index) {
    if (index < 0 || index >= fermentables.length) return;
    final id = fermentables[index].id;
    fermentables.removeAt(index);
    _suggestions[id] = const [];
    _safeNotify();
  }

  void removeFermentableById(String id) {
    fermentables.removeWhere((f) => f.id == id);
    _suggestions[id] = const [];
    _safeNotify();
  }

  void updateFermentable(dynamic a, [FermentableLine? b]) {
    if (a is int && b != null) {
      _updateAtIndex(a, b);
      return;
    }
    if (a is FermentableLine) {
      final idx = fermentables.indexWhere((f) => f.id == a.id);
      if (idx >= 0) _updateAtIndex(idx, a);
    }
  }

  void _setSuggestions(String lineId, List<UsdaChoice> list) {
    _suggestions[lineId] = List<UsdaChoice>.from(list);
    _safeNotify();
  }

  void _applyUsdaAt(int index, UsdaChoice choice, UsdaFoodDetail detail) {
    final prev = fermentables[index];

    final brx = detail.brix ?? prev.brix ?? choice.type.defaultBrix;
    final dens = _normalizeDensity(
      detail.density ?? prev.density ?? choice.type.defaultDensity,
      fallback: choice.type.defaultDensity,
    );

    double? weightG = prev.weightG;
    double? volumeMl = prev.volumeMl;

    final hadWeight = (weightG ?? 0) > 0;
    final hadVolume = (volumeMl ?? 0) > 0;

    // If syncing + liquid, recompute intelligently
    if (prev.syncWeightVolume && choice.type.isLiquid && dens > 0) {
      if (hadWeight && !hadVolume) {
        volumeMl = weightG! / dens;
      } else if (hadVolume && !hadWeight) {
        weightG = volumeMl! * dens;
      } else if (!hadWeight && !hadVolume) {
        // Provide a sensible default for first-time imports
        weightG = WeightUnit.pounds.toGrams(1); // 1 lb
        volumeMl = weightG / dens;
      } else {
        // Both existed; USDA provided a (possibly better) density — bring the pair back in sync.
        if ((weightG ?? 0) > 0) {
          volumeMl = weightG! / dens;
        } else if ((volumeMl ?? 0) > 0) {
          weightG = volumeMl! * dens;
        }
      }
    }

    fermentables[index] = prev.copyWith(
      name: choice.name,
      type: choice.type,
      brix: brx,
      density: dens,
      weightG: weightG,
      volumeMl: volumeMl,
      usdaBacked: true,
      usdaFdcId: choice.fdcId,
    );

    _suggestions[prev.id] = const [];
    _safeNotify();
  }

  MustStats _calcStats() {
    final totalSugar = fermentables.fold<double>(0.0, (a, f) => a + f.sugarGrams());
    final totalMl = fermentables.fold<double>(0.0, (a, f) => a + f.liquidMl());
    final brix = totalMl > 0 ? (totalSugar / totalMl) * 100.0 : 0.0;
    final sg = gu.brixToSg(brix);
    return MustStats(
      totalSugarG: totalSugar,
      totalVolumeMl: totalMl,
      brix: brix,
      sg: sg,
    );
  }

  void _updateAtIndex(int index, FermentableLine input) {
  final prev = fermentables[index];

  // Work on a mutable local, not the (final) parameter
  var updated = input;

  // --- Water quality-of-life: name/type/gravity coherence ---
  final nameLower = updated.name.trim().toLowerCase();
  final isWaterName = nameLower == 'water';

  // If user typed "water", force type to Water
  if (isWaterName && updated.type != FermentableType.water) {
    updated = updated.copyWith(type: FermentableType.water);
  }

  // If type is Water, ensure canonical name + gravity
  if (updated.type == FermentableType.water) {
    if (updated.name.trim().isEmpty || isWaterName) {
      updated = updated.copyWith(name: 'Water');
    }
    // Force SG=1.000 and Brix=0.0
    updated = updated.copyWith(
      density: 1.000,
      brix: 0.0,
    );
  }

  // Normalize/repair density first
  final dens = _normalizeDensity(
    updated.density ?? updated.type.defaultDensity,
    fallback: updated.type.defaultDensity,
  );
  updated = updated.copyWith(density: dens);

  // Only auto-convert for liquids with syncing turned on and a valid density
  final canSync = updated.syncWeightVolume && updated.type.isLiquid && dens > 0;

  if (canSync) {
    // What actually changed?
    final weightChanged  = (updated.weightG  ?? double.nan) != (prev.weightG  ?? double.nan);
    final volumeChanged  = (updated.volumeMl ?? double.nan) != (prev.volumeMl ?? double.nan);
    final densityChanged = (updated.density  ?? double.nan) != (prev.density  ?? double.nan);
    final brixChanged    = (updated.brix     ?? double.nan) != (prev.brix     ?? double.nan);

    bool hasW(FermentableLine l) => (l.weightG  ?? 0) > 0;
    bool hasV(FermentableLine l) => (l.volumeMl ?? 0) > 0;

    // 1) If user edited WEIGHT (or density/brix changed and we have weight), recompute VOLUME
    if (weightChanged || ((densityChanged || brixChanged) && hasW(updated))) {
      if (hasW(updated)) {
        updated = updated.copyWith(volumeMl: updated.weightG! / dens);
      }
    }
    // 2) Else if user edited VOLUME (or density/brix changed and we have volume), recompute WEIGHT
    else if (volumeChanged || ((densityChanged || brixChanged) && hasV(updated))) {
      if (hasV(updated)) {
        updated = updated.copyWith(weightG: updated.volumeMl! * dens);
      }
    }
    // 3) Else (no explicit edit detected), fill the missing side if exactly one is present
    else {
      final hasWeight = hasW(updated);
      final hasVol    = hasV(updated);
      if (hasWeight && !hasVol) {
        updated = updated.copyWith(volumeMl: updated.weightG! / dens);
      } else if (hasVol && !hasWeight) {
        updated = updated.copyWith(weightG: updated.volumeMl! * dens);
      }
    }
  }

  // --- Auto-fill fruit volume from estimate ---
  if (updated.type == FermentableType.fruit) {
    final prevHadVol = (prev.volumeMl ?? 0) > 0;
    final hasVol     = (updated.volumeMl ?? 0) > 0;
    final hasW       = (updated.weightG ?? 0) > 0;

    // Library-private method; valid since this controller is in the same file
    final prevEst = prev._estimatedFruitMl();
    final newEst  = updated._estimatedFruitMl();

    if (!hasVol && hasW && newEst > 0) {
      // No volume set → auto-fill from estimate
      updated = updated.copyWith(volumeMl: newEst);
    } else if (hasVol && prevHadVol) {
      // If previous volume matched our estimate, keep it in sync with changes
      if (prevEst > 0 && _isClose(prev.volumeMl!, prevEst) && newEst > 0) {
        updated = updated.copyWith(volumeMl: newEst);
      }
    }
  }

  fermentables[index] = updated;
  _safeNotify();
}


  // ------------------------------------------------------------------
  //            YEAST & ADDITIVES
  // ------------------------------------------------------------------

  // ---------- Yeast ----------
  final List<YeastLine> yeasts = <YeastLine>[];

  void addYeast(YeastLine y) {
    yeasts.add(y.copyWith(id: _genId()));
    _safeNotify();
  }

  void updateYeast(String id, YeastLine y) {
    final i = yeasts.indexWhere((e) => e.id == id);
    if (i >= 0) {
      yeasts[i] = y.copyWith(id: id);
      _safeNotify();
    }
  }

  void removeYeast(String id) {
    yeasts.removeWhere((e) => e.id == id);
    _safeNotify();
  }

  // ---------- Additives ----------
  final List<AdditiveLine> additives = <AdditiveLine>[];

  void addAdditive(AdditiveLine a) {
    additives.add(a.copyWith(id: _genId()));
    _safeNotify();
  }

  void updateAdditive(String id, AdditiveLine a) {
    final i = additives.indexWhere((e) => e.id == id);
    if (i >= 0) {
      additives[i] = a.copyWith(id: id);
      _safeNotify();
    }
  }

  void removeAdditive(String id) {
    additives.removeWhere((e) => e.id == id);
    _safeNotify();
  }
}

// ======================= Yeast & Additives models =======================

enum YeastForm { dry, liquid, other }
extension YeastFormX on YeastForm {
  String get label => switch (this) {
        YeastForm.dry => 'Dry',
        YeastForm.liquid => 'Liquid',
        YeastForm.other => 'Other',
      };
}

enum QtyUnit { g, packets, ml, tsp }
extension QtyUnitX on QtyUnit {
  String get label => switch (this) {
        QtyUnit.g => 'g',
        QtyUnit.packets => 'pkt',
        QtyUnit.ml => 'mL',
        QtyUnit.tsp => 'tsp',
      };
}

@immutable
class YeastLine {
  final String id;
  final String name;
  final YeastForm form;
  final double? quantity;
  final QtyUnit unit;
  final String? notes;

  const YeastLine({
    required this.id,
    required this.name,
    required this.form,
    required this.quantity,
    required this.unit,
    this.notes,
  });

  factory YeastLine.blank() => YeastLine(
        id: _genId(),
        name: '',
        form: YeastForm.dry,
        quantity: null,
        unit: QtyUnit.packets,
      );

  YeastLine copyWith({
    String? id,
    String? name,
    YeastForm? form,
    double? quantity,
    QtyUnit? unit,
    String? notes,
  }) {
    return YeastLine(
      id: id ?? this.id,
      name: name ?? this.name,
      form: form ?? this.form,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      notes: notes ?? this.notes,
    );
  }
}

@immutable
class AdditiveLine {
  final String id;
  final String name;
  final double? quantity;
  final QtyUnit unit;
  final String? when; // e.g. "primary", "secondary"
  final String? notes;

  const AdditiveLine({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    this.when,
    this.notes,
  });

  factory AdditiveLine.blank() => AdditiveLine(
        id: _genId(),
        name: '',
        quantity: null,
        unit: QtyUnit.g,
      );

  AdditiveLine copyWith({
    String? id,
    String? name,
    double? quantity,
    QtyUnit? unit,
    String? when,
    String? notes,
  }) {
    return AdditiveLine(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      when: when ?? this.when,
      notes: notes ?? this.notes,
    );
  }
}
