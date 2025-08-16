import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'tag.dart';

part 'recipe_model.g.dart';

@HiveType(typeId: 4)
class RecipeModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  DateTime createdAt;

  // ---- TAGS (migration-friendly) ------------------------------------------
  // Old, embedded tags. KEPT for older records.
  @HiveField(3)
  List<Tag>? tagsLegacy;

  // New, referenced tags via HiveList
  @HiveField(17)
  HiveList<Tag>? tagRefs;

  // Convenience: read tags from refs if present, else legacy (or []).
  List<Tag> get tags => (tagRefs != null) ? tagRefs!.toList() : (tagsLegacy ?? const <Tag>[]);

  /// Set tags using canonical objects from Tag box (de-duped), and persist so
  /// Hive watchers fire (important for Firestore sync).
  Future<void> setTagsFromBox(List<Tag> picked, Box<Tag> tagBox) async {
    final seen = <String>{};
    final canon = <Tag>[];

    for (final t in picked) {
      final key = t.name.trim();
      if (key.isEmpty) continue;
      if (seen.add(key.toLowerCase())) {
        final stored = tagBox.get(key) ?? (() {
          final fresh = Tag(name: key, iconKey: t.iconKey);
          tagBox.put(key, fresh);
          return fresh;
        })();
        canon.add(stored);
      }
    }

    tagRefs = HiveList<Tag>(tagBox, objects: canon);
    tagsLegacy = const []; // optional: clear legacy once migrated
    await save(); // 🔑 ensures watchers emit and Firestore gets updated tags
  }
  // -------------------------------------------------------------------------

  @HiveField(4)
  double? og;

  @HiveField(5)
  double? fg;

  @HiveField(6)
  double? abv;

  // NOTE: Keep these as dynamic for Hive backward-compat.
  @HiveField(7)
  List<Map<dynamic, dynamic>> additives;

  @HiveField(8)
  List<Map<dynamic, dynamic>> ingredients;

  @HiveField(9)
  List<FermentationStage> fermentationStages;

  @HiveField(10)
  List<Map<dynamic, dynamic>> yeast;

  @HiveField(11)
  String notes;

  @HiveField(12)
  DateTime? lastOpened;

  @HiveField(13)
  double? batchVolume;

  @HiveField(14)
  double? plannedOg;

  @HiveField(15)
  double? plannedAbv;

  @HiveField(16)
  bool isArchived;

  RecipeModel({
    String? id,
    required this.name,
    required this.createdAt,
    List<Tag>? tags, // optional so Hive adapter can construct the object
    this.og,
    this.fg,
    this.abv,
    List<Map<dynamic, dynamic>>? additives,
    List<Map<dynamic, dynamic>>? ingredients,
    List<FermentationStage>? fermentationStages,
    List<Map<dynamic, dynamic>>? yeast,
    this.notes = '',
    this.lastOpened,
    this.batchVolume,
    this.plannedOg,
    this.plannedAbv,
    this.isArchived = false,
  })  : id = id ?? const Uuid().v4(),
        tagsLegacy = tags, // seed legacy if provided
        additives = additives ?? <Map<dynamic, dynamic>>[],
        ingredients = ingredients ?? <Map<dynamic, dynamic>>[],
        fermentationStages = fermentationStages ?? <FermentationStage>[],
        yeast = yeast ?? <Map<dynamic, dynamic>>[];

  // ---------- Safe helpers ----------

  // Convert dynamic map (from Hive/legacy) to a proper Map<String, dynamic>.
  static Map<String, dynamic> _toStringKeyedMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// Use these in UI/business code instead of the raw lists.
  List<Map<String, dynamic>> get safeIngredients =>
      ingredients.map(_toStringKeyedMap).toList(growable: true);

  List<Map<String, dynamic>> get safeAdditives =>
      additives.map(_toStringKeyedMap).toList(growable: true);

  List<Map<String, dynamic>> get safeYeast =>
      yeast.map(_toStringKeyedMap).toList(growable: true);

  List<FermentationStage> get safeStages =>
      fermentationStages.whereType<FermentationStage>().toList(growable: true);

  /// Normalize in place for legacy/dirty data (call once after load if needed).
  void normalizeInPlace() {
    ingredients = safeIngredients;
    additives = safeAdditives;
    yeast = safeYeast;

    og = _toDouble(og);
    fg = _toDouble(fg);
    abv = _toDouble(abv);
    batchVolume = _toDouble(batchVolume);
    plannedOg = _toDouble(plannedOg);
    plannedAbv = _toDouble(plannedAbv);

    // Keep tags safe if legacy is null
    tagsLegacy ??= const <Tag>[];
  }

  // ---------- JSON ----------

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      // ✅ FIX: Serialize the full tag object, not just its name.
      'tags': tags.map((t) => t.toJson()).toList(),
      'og': og,
      'fg': fg,
      'abv': abv,
      'additives': safeAdditives,
      'ingredients': safeIngredients,
      'fermentationStages': safeStages.map((e) => e.toJson()).toList(),
      'yeast': safeYeast,
      'notes': notes,
      'lastOpened': lastOpened?.toIso8601String(),
      'batchVolume': batchVolume,
      'plannedOg': plannedOg,
      'plannedAbv': plannedAbv,
      'isArchived': isArchived,
    };
  }

  /// PURE parser: no Hive access, safe for cold-start / snapshot threads.
  factory RecipeModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> toStrMap(dynamic raw) {
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return <String, dynamic>{};
    }

    List<Map<String, dynamic>> listOfMaps(dynamic v) =>
        (v is List) ? v.map(toStrMap).toList() : <Map<String, dynamic>>[];

    List<FermentationStage> stages(dynamic v) =>
        (v is List) ? v.map((e) => FermentationStage.fromJson(toStrMap(e))).toList() : <FermentationStage>[];

    double? toD(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString());
    }

    // Parse embedded tags as {name}, preventing dupes; no Tag box access here.
    List<Tag> parseTags(dynamic raw) {
      final list = (raw is List) ? raw : const [];
      final seen = <String>{};
      final out = <Tag>[];
      for (final t in list) {
        // Handle both full tag objects and simple name maps
        final name = (t is Map ? (t['name'] ?? t['id'] ?? '') : t?.toString() ?? '').trim();
        if (name.isEmpty) continue;
        final key = name.toLowerCase();
        if (seen.add(key)) {
          // Use the full fromJson factory to preserve all data
          out.add(Tag.fromJson(t is Map ? Map<String, dynamic>.from(t) : {'name': name}));
        }
      }
      return out;
    }

    return RecipeModel(
      id: json['id'] as String?,
      name: (json['name'] as String?) ?? 'Untitled',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      tags: parseTags(json['tags']),
      og: toD(json['og']),
      fg: toD(json['fg']),
      abv: toD(json['abv']),
      additives: listOfMaps(json['additives']),
      ingredients: listOfMaps(json['ingredients']),
      fermentationStages: stages(json['fermentationStages']),
      yeast: listOfMaps(json['yeast']),
      notes: (json['notes'] as String?) ?? '',
      lastOpened: (json['lastOpened'] is String)
          ? DateTime.tryParse(json['lastOpened'] as String)
          : null,
      batchVolume: toD(json['batchVolume']),
      plannedOg: toD(json['plannedOg']),
      plannedAbv: toD(json['plannedAbv']),
      isArchived: (json['isArchived'] as bool?) ?? false,
    );
  }

  // ---------- Convenience ----------

  RecipeModel copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    List<Tag>? tags,
    double? og,
    double? fg,
    double? abv,
    List<Map<dynamic, dynamic>>? additives,
    List<Map<dynamic, dynamic>>? ingredients,
    List<FermentationStage>? fermentationStages,
    List<Map<dynamic, dynamic>>? yeast,
    String? notes,
    DateTime? lastOpened,
    double? batchVolume,
    double? plannedOg,
    double? plannedAbv,
    bool? isArchived,
  }) {
    final r = RecipeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      tags: tags ?? this.tags,
      og: og ?? this.og,
      fg: fg ?? this.fg,
      abv: abv ?? this.abv,
      additives: additives ?? this.additives,
      ingredients: ingredients ?? this.ingredients,
      fermentationStages: fermentationStages ?? this.fermentationStages,
      yeast: yeast ?? this.yeast,
      notes: notes ?? this.notes,
      lastOpened: lastOpened ?? this.lastOpened,
      batchVolume: batchVolume ?? this.batchVolume,
      plannedOg: plannedOg ?? this.plannedOg,
      plannedAbv: plannedAbv ?? this.plannedAbv,
      isArchived: isArchived ?? this.isArchived,
    );
    // preserve refs in copies
    r.tagRefs = tagRefs;
    return r;
  }
}