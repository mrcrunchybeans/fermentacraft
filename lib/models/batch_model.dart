import 'package:hive_flutter/hive_flutter.dart';

import 'fermentation_stage.dart';
import 'measurement.dart';
import 'planned_event.dart';
import 'tag.dart'; // kept for legacy reads (tagsLegacy)

part 'batch_model.g.dart';

@HiveType(typeId: 34)
class BatchModel extends HiveObject {
  // ---------------- Core identifiers & timing ----------------
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  /// Link back to the source recipe (by recipe.id)
  @HiveField(2)
  String recipeId;

  @HiveField(3)
  DateTime startDate;

  @HiveField(18)
  DateTime createdAt;

  @HiveField(4)
  DateTime? bottleDate;

  // ---------------- Batch composition ----------------
  @HiveField(14)
  List<Map<String, dynamic>> ingredients;

  @HiveField(16)
  List<Map<String, dynamic>> additives;

  /// Yeast stored like other items for consistency (legacy used dynamic keys)
  @HiveField(17)
  List<Map<dynamic, dynamic>> yeast;

  /// Fermentation plan/profile
  @HiveField(6)
  List<FermentationStage> fermentationStages;

  // ---------------- Measurements & logs ----------------
  @HiveField(20)
  double? og;

  @HiveField(21)
  double? fg;

  @HiveField(22)
  double? abv;

  @HiveField(23)
  List<Measurement> measurements;

  /// Free-form logs (string-keyed maps preferred; normalized on save/load)
  @HiveField(7)
  List<Map<String, dynamic>> measurementLogs;

  // ---------------- Planning & status ----------------
  @HiveField(8)
  String status; // e.g., Planning, Primary, Aging, Bottled

  @HiveField(12)
  double? plannedOg;

  @HiveField(13)
  double? plannedAbv;

  @HiveField(15)
  List<PlannedEvent>? plannedEvents;

  // ---------------- Misc metadata ----------------
  @HiveField(5)
  double? batchVolume;

  @HiveField(9)
  String? notes;

  /// Inventory deduction record: ingredient id/name -> deducted?
  @HiveField(10)
  Map<String, bool> deductedIngredients;

  @HiveField(11)
  String? type; // optional free-form

  @HiveField(24)
  DateTime? fsuDate;

  @HiveField(25)
  String? prepNotes;

  @HiveField(26)
  int? tastingRating;

  @HiveField(27)
  Map<String, String>? tastingNotes;

  @HiveField(28)
  String? packagingMethod;

  @HiveField(29)
  double? finalYield;

  @HiveField(30)
  DateTime? packagingDate;

  @HiveField(31)
  String? finalNotes;

  @HiveField(32)
  String? finalYieldUnit;

  @HiveField(33, defaultValue: false)
  bool isArchived;


  // ---------------- Legacy tags (kept nullable for old data) ----------------
  /// Legacy tag storage. You can safely ignore it in new code.
  /// Kept only so older boxes deserialize without errors.
  @HiveField(19)
  List<Tag>? tagsLegacy;

  // ---------------- New category field ----------------
  /// Primary categorization for grouping/sorting (e.g., Mead, Cider, Wine).
  @HiveField(34)
  String? category;

// Back-compat API
List<Tag> get tags => tagsLegacy ?? const <Tag>[];
set tags(List<Tag> v) => tagsLegacy = v;

  /// Display-friendly category with fallbacks:
  /// 1) explicit category
  /// 2) first legacy tag name
  /// 3) "Uncategorized"
  String get categoryLabel {
    final c = category?.trim();
    if (c != null && c.isNotEmpty) return c;
    final legacy = tagsLegacy;
    if (legacy != null && legacy.isNotEmpty) return legacy.first.name;
    return 'Uncategorized';
  }

  // ---------------- Safe access helpers ----------------
  List<FermentationStage> get safeFermentationStages =>
      fermentationStages.whereType<FermentationStage>().toList(growable: true);

  List<PlannedEvent> get safePlannedEvents =>
      (plannedEvents ?? const <PlannedEvent>[]).whereType<PlannedEvent>().toList(growable: true);

  List<Measurement> get safeMeasurements =>
      measurements.whereType<Measurement>().toList(growable: true);

  List<Map<String, dynamic>> get safeIngredients =>
      ingredients.map(_toStringKeyedMap).toList(growable: true);

  List<Map<String, dynamic>> get safeAdditives =>
      additives.map(_toStringKeyedMap).toList(growable: true);

  List<Map<String, dynamic>> get safeYeast =>
      yeast.map(_toStringKeyedMap).toList(growable: true);

  // ---------------- Constructor ----------------
  BatchModel({
    required this.id,
    required this.name,
    required this.recipeId,
    required this.startDate,
    required this.createdAt,
    this.bottleDate,
    this.batchVolume,
    List<FermentationStage>? fermentationStages,
    List<Map<String, dynamic>>? measurementLogs,
    this.status = 'Planning',
    this.notes,
    Map<String, bool>? deductedIngredients,
    this.type,
    this.prepNotes,
    this.plannedOg,
    this.plannedAbv,
    List<Map<String, dynamic>>? ingredients,
    List<PlannedEvent>? plannedEvents,
    List<Map<String, dynamic>>? additives,
    List<Map<dynamic, dynamic>>? yeast,
    this.og,
    this.fg,
    this.abv,
    List<Measurement>? measurements,
    this.fsuDate,
    this.packagingDate,
    this.finalNotes,
    this.tastingRating,
    this.tastingNotes,
    this.packagingMethod,
    this.finalYield,
    this.finalYieldUnit,
    this.isArchived = false,
    this.category,

  List<Tag>? tags,            // <-- back-compat param
  List<Tag>? tagsLegacy,      // <-- keep for adapter/init


  })  : 
        tagsLegacy = tagsLegacy ?? tags ?? [],   // <-- bridge both to field
        fermentationStages = fermentationStages ?? <FermentationStage>[],
        measurementLogs = measurementLogs ?? <Map<String, dynamic>>[],
        deductedIngredients = deductedIngredients ?? <String, bool>{},
        ingredients = ingredients ?? <Map<String, dynamic>>[],
        plannedEvents = plannedEvents ?? <PlannedEvent>[],
        additives = additives ?? <Map<String, dynamic>>[],
        measurements = measurements ?? <Measurement>[],
        yeast = yeast ?? <Map<dynamic, dynamic>>[];
        

  // ---------------- Normalization (optional) ----------------
  /// Call once after construction/fromJson if you want to scrub dynamic data.
  void normalizeInPlace() {
    ingredients = safeIngredients;
    additives = safeAdditives;
    yeast = safeYeast;
    fermentationStages = safeFermentationStages;
    measurements = safeMeasurements;
    measurementLogs = measurementLogs.map(_toStringKeyedMap).toList();

    og = _toDouble(og);
    fg = _toDouble(fg);
    abv = _toDouble(abv);
    plannedOg = _toDouble(plannedOg);
    plannedAbv = _toDouble(plannedAbv);
    finalYield = _toDouble(finalYield);

    // keep legacy tags nullable; do not populate new ones
  }

  // ---------------- JSON ----------------
  Map<String, dynamic> toJson() {
    Map<String, dynamic> safeOut(Map m) => _toStringKeyedMap(m);

    return {
      'id': id,
      'name': name,
      'recipeId': recipeId,
      'startDate': startDate.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'bottleDate': bottleDate?.toIso8601String(),
      'batchVolume': batchVolume,
      'fermentationStages': fermentationStages.map((fs) => fs.toJson()).toList(),
      'measurementLogs': measurementLogs.map(safeOut).toList(),
      'status': status,
      'notes': notes,
      'deductedIngredients': deductedIngredients,
      'type': type,
      'plannedOg': plannedOg,
      'plannedAbv': plannedAbv,
      'ingredients': ingredients.map(safeOut).toList(),
      'plannedEvents': plannedEvents?.map((e) => e.toJson()).toList(),
      'additives': additives.map(safeOut).toList(),
      'yeast': yeast.map(safeOut).toList(),
      'og': og,
      'fg': fg,
      'abv': abv,
      'measurements': measurements.map((m) => m.toJson()).toList(),
      'fsuDate': fsuDate?.toIso8601String(),
      'prepNotes': prepNotes,
      'tastingRating': tastingRating,
      'tastingNotes': tastingNotes,
      'packagingMethod': packagingMethod,
      'finalYield': finalYield,
      'packagingDate': packagingDate?.toIso8601String(),
      'finalNotes': finalNotes,
      'finalYieldUnit': finalYieldUnit,
      'isArchived': isArchived,
      // new schema
      'category': category,
      // we intentionally do NOT output tagsLegacy; you can add it if you need export
    };
  }

  factory BatchModel.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(dynamic v) =>
        (v is List) ? v.map(_toStringKeyedMap).toList() : <Map<String, dynamic>>[];

    List<FermentationStage> stages(dynamic v) => (v is List)
        ? v
            .map((e) => FermentationStage.fromJson(_toStringKeyedMap(e)))
            .toList()
        : <FermentationStage>[];

    List<Measurement> meas(dynamic v) => (v is List)
        ? v.map((e) => Measurement.fromJson(_toStringKeyedMap(e))).toList()
        : <Measurement>[];

    List<PlannedEvent> events(dynamic v) => (v is List)
        ? v.map((e) => PlannedEvent.fromJson(_toStringKeyedMap(e))).toList()
        : <PlannedEvent>[];

    // Legacy tags parsing (best-effort)
    List<Tag>? parseTags(dynamic v) {
      if (v is! List) return null;
      final seen = <String>{};
      final out = <Tag>[];
      for (final e in v) {
        if (e is Map) {
          final m = _toStringKeyedMap(e);
          final name = (m['name'] ?? m['id'] ?? '').toString().trim();
          if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
          out.add(Tag.fromJson(m));
        }
      }
      return out.isEmpty ? null : out;
    }

    return BatchModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Unnamed Batch').toString(),
      recipeId: (json['recipeId'] ?? '').toString(),
      startDate: DateTime.tryParse((json['startDate'] ?? '').toString()) ?? DateTime.now(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? DateTime.now(),
      bottleDate: (json['bottleDate'] != null)
          ? DateTime.tryParse(json['bottleDate'].toString())
          : null,
      batchVolume: _toDouble(json['batchVolume']),
      fermentationStages: stages(json['fermentationStages']),
      measurementLogs: maps(json['measurementLogs']),
      status: (json['status'] ?? 'Planning').toString(),
      notes: (json['notes'] as String?),
      deductedIngredients: (json['deductedIngredients'] is Map)
          ? Map<String, bool>.from(json['deductedIngredients'] as Map)
          : <String, bool>{},
      type: (json['type'] as String?),
      prepNotes: (json['prepNotes'] as String?),
      plannedOg: _toDouble(json['plannedOg']),
      plannedAbv: _toDouble(json['plannedAbv']),
      ingredients: maps(json['ingredients']),
      plannedEvents: events(json['plannedEvents']),
      additives: maps(json['additives']),
      yeast: (json['yeast'] is List) ? List<Map<dynamic, dynamic>>.from(json['yeast']) : <Map<dynamic, dynamic>>[],
      og: _toDouble(json['og']),
      fg: _toDouble(json['fg']),
      abv: _toDouble(json['abv']),
      measurements: meas(json['measurements']),
      fsuDate: (json['fsuDate'] != null)
          ? DateTime.tryParse(json['fsuDate'].toString())
          : null,
      packagingDate: (json['packagingDate'] != null)
          ? DateTime.tryParse(json['packagingDate'].toString())
          : null,
      finalNotes: (json['finalNotes'] as String?),
      tastingRating: (json['tastingRating'] is int) ? json['tastingRating'] as int : null,
      tastingNotes: (json['tastingNotes'] is Map)
          ? Map<String, String>.from(json['tastingNotes'] as Map)
          : null,
      packagingMethod: (json['packagingMethod'] as String?),
      finalYield: _toDouble(json['finalYield']),
      finalYieldUnit: (json['finalYieldUnit'] as String?),
      isArchived: (json['isArchived'] as bool?) ?? false,
      // new schema
      category: (json['category'] as String?)?.trim(),
      // legacy (best-effort)
      tagsLegacy: parseTags(json['tags']),
    );
  }

  // ---------------- copyWith ----------------
  BatchModel copyWith({
    String? id,
    String? name,
    String? recipeId,
    DateTime? startDate,
    DateTime? createdAt,
    DateTime? bottleDate,
    double? batchVolume,
    List<FermentationStage>? fermentationStages,
    List<Map<String, dynamic>>? measurementLogs,
    String? status,
    String? notes,
    Map<String, bool>? deductedIngredients,
    String? type,
    String? prepNotes,
    double? plannedOg,
    double? plannedAbv,
    List<Map<String, dynamic>>? ingredients,
    List<PlannedEvent>? plannedEvents,
    List<Map<String, dynamic>>? additives,
    List<Map<dynamic, dynamic>>? yeast,
    double? og,
    double? fg,
    double? abv,
    List<Measurement>? measurements,
    DateTime? fsuDate,
    DateTime? packagingDate,
    String? finalNotes,
    int? tastingRating,
    Map<String, String>? tastingNotes,
    String? packagingMethod,
    double? finalYield,
    String? finalYieldUnit,
    bool? isArchived,
    String? category,
    List<Tag>? tagsLegacy,
  }) {
    final b = BatchModel(
      id: id ?? this.id,
      name: name ?? this.name,
      recipeId: recipeId ?? this.recipeId,
      startDate: startDate ?? this.startDate,
      createdAt: createdAt ?? this.createdAt,
      bottleDate: bottleDate ?? this.bottleDate,
      batchVolume: batchVolume ?? this.batchVolume,
      fermentationStages: fermentationStages ?? this.fermentationStages,
      measurementLogs: measurementLogs ?? this.measurementLogs,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      deductedIngredients: deductedIngredients ?? this.deductedIngredients,
      type: type ?? this.type,
      prepNotes: prepNotes ?? this.prepNotes,
      plannedOg: plannedOg ?? this.plannedOg,
      plannedAbv: plannedAbv ?? this.plannedAbv,
      ingredients: ingredients ?? this.ingredients,
      plannedEvents: plannedEvents ?? this.plannedEvents,
      additives: additives ?? this.additives,
      yeast: yeast ?? this.yeast,
      og: og ?? this.og,
      fg: fg ?? this.fg,
      abv: abv ?? this.abv,
      measurements: measurements ?? this.measurements,
      fsuDate: fsuDate ?? this.fsuDate,
      packagingDate: packagingDate ?? this.packagingDate,
      finalNotes: finalNotes ?? this.finalNotes,
      tastingRating: tastingRating ?? this.tastingRating,
      tastingNotes: tastingNotes ?? this.tastingNotes,
      packagingMethod: packagingMethod ?? this.packagingMethod,
      finalYield: finalYield ?? this.finalYield,
      finalYieldUnit: finalYieldUnit ?? this.finalYieldUnit,
      isArchived: isArchived ?? this.isArchived,
      category: category ?? this.category,
      tagsLegacy: tagsLegacy ?? this.tagsLegacy,
    );
    return b;
  }

  // ---------------- Private helpers ----------------
  static Map<String, dynamic> _toStringKeyedMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}



