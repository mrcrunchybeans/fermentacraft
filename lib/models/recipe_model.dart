import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:hive/hive.dart';
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

  // This setup with legacy and ref fields is for migration. New code primarily uses tagRefs.
  @HiveField(3)
  List<Tag>? tagsLegacy;

  @HiveField(17)
  HiveList<Tag>? tagRefs;

  // Central, safe way to access tags, regardless of their storage format.
  List<Tag> get tags => tagRefs?.toList() ?? tagsLegacy ?? const <Tag>[];

  @HiveField(4)
  double? og;

  @HiveField(5)
  double? fg;

  @HiveField(6)
  double? abv;

  @HiveField(7)
  List<Map> additives;

  @HiveField(8)
  List<Map> ingredients;

  @HiveField(9)
  List<FermentationStage> fermentationStages;

  @HiveField(10)
  List<Map> yeast;

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

  // ✅ NEW: category used for sorting/grouping
  @HiveField(18)
  String? category;

  String get categoryLabel {
    final c = category?.trim();
    if (c != null && c.isNotEmpty) return c;
    if (tags.isNotEmpty) return tags.first.name;
    return 'Uncategorized';
  }

  RecipeModel({
    String? id,
    required this.name,
    required this.createdAt,
    List<Tag>? tags,
    this.og,
    this.fg,
    this.abv,
    List<Map>? additives,
    List<Map>? ingredients,
    List<FermentationStage>? fermentationStages,
    List<Map>? yeast,
    this.notes = '',
    this.lastOpened,
    this.batchVolume,
    this.plannedOg,
    this.plannedAbv,
    this.isArchived = false,
    this.category,
  })  : id = id ?? const Uuid().v4(),
        tagsLegacy = tags,
        additives = additives ?? [],
        ingredients = ingredients ?? [],
        fermentationStages = fermentationStages ?? [],
        yeast = yeast ?? [];

  // --- Safe Accessors ---
  List<Map<String, dynamic>> get safeIngredients =>
      ingredients.map(_toStringKeyedMap).toList(growable: true);

  List<Map<String, dynamic>> get safeAdditives =>
      additives.map(_toStringKeyedMap).toList(growable: true);

  List<Map<String, dynamic>> get safeYeast =>
      yeast.map(_toStringKeyedMap).toList(growable: true);

  List<FermentationStage> get safeStages =>
      fermentationStages.whereType<FermentationStage>().toList(growable: true);

  // --- Tag Management ---
  Future<void> setTagsFromBox(List<Tag> pickedTags, Box<Tag> tagBox) async {
    final seen = <String>{};
    final canonicalTags = <Tag>[];

    for (final t in pickedTags) {
      final key = t.name.trim();
      if (key.isEmpty || !seen.add(key.toLowerCase())) continue;

      final storedTag = tagBox.get(key) ?? (() {
        final newTag = Tag(name: key, iconKey: t.iconKey);
        tagBox.put(key, newTag);
        return newTag;
      })();
      canonicalTags.add(storedTag);
    }

    tagRefs = HiveList<Tag>(tagBox, objects: canonicalTags);
    tagsLegacy = null; // Clear legacy field after migrating to refs.
    await save(); // Important for Hive watchers and sync service.
  }
  
  // ✅ RE-ADDED: This method is called during startup migrations.
  /// Normalize in place for legacy/dirty data.
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
    
    tagsLegacy ??= const <Tag>[];
  }

  // --- JSON Serialization ---
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'tags': tags.map((t) => t.toJson()).toList(),
      'category': category, 
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

  factory RecipeModel.fromJson(Map<String, dynamic> json) {
    // try category → else derive from first legacy tag → else null (will show as 'Uncategorized')
    String? derivedCategory() {
      final c = (json['category'] as String?)?.trim();
      if (c != null && c.isNotEmpty) return c;
      final legacy = _parseTagsFromJson(json['tags']);
      return legacy.isNotEmpty ? legacy.first.name : null;
    }
        return RecipeModel(
      id: json['id'] as String?,
      name: (json['name'] as String?) ?? 'Untitled',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      tags: _parseTagsFromJson(json['tags']),
      category: derivedCategory(),
      og: _toDouble(json['og']),
      fg: _toDouble(json['fg']),
      abv: _toDouble(json['abv']),
      additives: _listOfMaps(json['additives']),
      ingredients: _listOfMaps(json['ingredients']),
      fermentationStages: (json['fermentationStages'] as List<dynamic>? ?? [])
          .map((e) => FermentationStage.fromJson(_toStringKeyedMap(e)))
          .toList(),
      yeast: _listOfMaps(json['yeast']),
      notes: (json['notes'] as String?) ?? '',
      lastOpened: (json['lastOpened'] is String)
          ? DateTime.tryParse(json['lastOpened'] as String)
          : null,
      batchVolume: _toDouble(json['batchVolume']),
      plannedOg: _toDouble(json['plannedOg']),
      plannedAbv: _toDouble(json['plannedAbv']),
      isArchived: (json['isArchived'] as bool?) ?? false,
    );
  }

  // --- Private Static Helpers ---
  static Map<String, dynamic> _toStringKeyedMap(dynamic raw) {
    return (raw is Map) ? Map<String, dynamic>.from(raw) : {};
  }

  static List<Map<String, dynamic>> _listOfMaps(dynamic v) {
    return (v is List) ? v.map(_toStringKeyedMap).toList() : [];
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    return double.tryParse(v.toString());
  }

  static List<Tag> _parseTagsFromJson(dynamic raw) {
    final list = (raw is List) ? raw : [];
    final seen = <String>{};
    return list.map((t) {
      if (t is! Map) return null;
      final name = (t['name'] ?? t['id'] ?? '').toString().trim();
      if (name.isEmpty || !seen.add(name.toLowerCase())) return null;
      return Tag.fromJson(Map<String, dynamic>.from(t));
    }).whereType<Tag>().toList();
  }

  // --- Convenience Methods ---
  RecipeModel copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    List<Tag>? tags,
    double? og,
    double? fg,
    double? abv,
    List<Map>? additives,
    List<Map>? ingredients,
    List<FermentationStage>? fermentationStages,
    List<Map>? yeast,
    String? notes,
    DateTime? lastOpened,
    double? batchVolume,
    double? plannedOg,
    double? plannedAbv,
    bool? isArchived,
    String? category,
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
      category: category ?? this.category,
    );
    // Preserve HiveList reference if it exists to maintain relationships.
    r.tagRefs = tagRefs; 
    return r;
  }
}