// ignore_for_file: invalid_null_aware_operator

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

  @HiveField(3)
  List<Tag> tags;

  @HiveField(4)
  double? og;

  @HiveField(5)
  double? fg;

  @HiveField(6)
  double? abv;

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
    required this.tags,
    required this.createdAt,
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
    this.isArchived = false,

    this.plannedAbv,
  })  : id = id ?? const Uuid().v4(),
        additives = additives ?? [],
        ingredients = ingredients ?? [],
        fermentationStages = fermentationStages ?? [],
        yeast = yeast ?? [];

  Map<String, dynamic> _safelyConvertMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    } else if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    } else {
      return {};
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'tags': tags.map((tag) => tag.toJson()).toList(),
      'og': og,
      'fg': fg,
      'abv': abv,
      'additives': additives.map((e) => _safelyConvertMap(e)).toList(),
      'ingredients': ingredients.map((e) => _safelyConvertMap(e)).toList(),
      'fermentationStages': fermentationStages.map((e) => e.toJson()).toList(),
      'yeast': yeast.map((e) => _safelyConvertMap(e)).toList(),
      'notes': notes,
      'lastOpened': lastOpened?.toIso8601String(),
      'batchVolume': batchVolume,
      'plannedOg': plannedOg,
      'plannedAbv': plannedAbv,
      'isArchived': isArchived,
    };
  }

  factory RecipeModel.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> parseListOfMaps(dynamic jsonList) {
      if (jsonList == null || jsonList is! List) return [];
      return jsonList
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }

    return RecipeModel(
      id: json['id'],
      name: json['name'],
      createdAt: DateTime.parse(json['createdAt']),
      tags: (json['tags'] as List).map((tag) => Tag.fromJson(tag)).toList(),
      og: json['og'],
      fg: json['fg'],
      abv: json['abv'],
      additives: parseListOfMaps(json['additives']),
      ingredients: parseListOfMaps(json['ingredients']),
      fermentationStages: (json['fermentationStages'] as List<dynamic>?)
              ?.map((e) => FermentationStage.fromJson(
                  Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      yeast: parseListOfMaps(json['yeast']),
      notes: json['notes'] ?? '',
      lastOpened: json['lastOpened'] != null
          ? DateTime.parse(json['lastOpened'])
          : null,
      batchVolume: json['batchVolume'],
      plannedOg: json['plannedOg'],
      plannedAbv: json['plannedAbv'],
      isArchived: json['isArchived'] ?? false,

    );
  }
}
