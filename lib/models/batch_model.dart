import 'package:hive/hive.dart';
import 'fermentation_stage.dart';
import 'measurement.dart';
import 'planned_event.dart';
import 'tag.dart';

part 'batch_model.g.dart';

@HiveType(typeId: 34)
class BatchModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String recipeId;

  @HiveField(3)
  DateTime startDate;

  @HiveField(4)
  DateTime? bottleDate;

  @HiveField(5)
  double? batchVolume;

  @HiveField(6)
  List<FermentationStage> fermentationStages;
  List<FermentationStage> get safeFermentationStages => fermentationStages;

  @HiveField(7)
  List<Map<String, dynamic>> measurementLogs;

  @HiveField(8)
  String status;

  @HiveField(9)
  String? notes;

  @HiveField(10)
  Map<String, bool> deductedIngredients;

  @HiveField(11)
  String? type;

  @HiveField(12)
  double? plannedOg;

  @HiveField(13)
  double? plannedAbv;

  @HiveField(14)
  List<Map<String, dynamic>> ingredients;
  List<Map<String, dynamic>> get safeIngredients => ingredients;

  @HiveField(15)
  List<PlannedEvent>? plannedEvents;
  List<PlannedEvent> get safePlannedEvents => plannedEvents ?? [];

  @HiveField(16)
  List<Map<String, dynamic>> additives;
  List<Map<String, dynamic>> get safeAdditives => additives;

  @HiveField(17)
  Map<String, dynamic>? yeast;

  @HiveField(18)
  DateTime createdAt;

  @HiveField(19)
  List<Tag> tags;

  @HiveField(20)
  double? og;

  @HiveField(21)
  double? fg;

  @HiveField(22)
  double? abv;

  @HiveField(23)
  List<Measurement> measurements;

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

  BatchModel({
    required this.id,
    required this.name,
    required this.recipeId,
    required this.startDate,
    required this.createdAt,
    required this.tags,
    this.bottleDate,
    this.batchVolume,
    this.finalYieldUnit,
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
    this.yeast,
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
  })  : fermentationStages = fermentationStages ?? [],
        measurementLogs = measurementLogs ?? [],
        deductedIngredients = deductedIngredients ?? {},
        ingredients = ingredients ?? [],
        plannedEvents = plannedEvents ?? [],
        additives = additives ?? [],
        measurements = measurements ?? [];

  Map<String, dynamic> toJson() {
    Map<String, dynamic> safelyConvertMap(Map sourceMap) {
      final Map<String, dynamic> newMap = {};
      sourceMap.forEach((key, value) {
        newMap[key.toString()] = value is DateTime ? value.toIso8601String() : value;
      });
      return newMap;
    }

    return {
      'id': id,
      'name': name,
      'recipeId': recipeId,
      'startDate': startDate.toIso8601String(),
      'bottleDate': bottleDate?.toIso8601String(),
      'batchVolume': batchVolume,
      'fermentationStages': fermentationStages.map((fs) => fs.toJson()).toList(),
      'measurementLogs': measurementLogs.map((log) => safelyConvertMap(log)).toList(),
      'status': status,
      'notes': notes,
      'deductedIngredients': deductedIngredients,
      'type': type,
      'plannedOg': plannedOg,
      'plannedAbv': plannedAbv,
      'ingredients': ingredients.map((ing) => safelyConvertMap(ing)).toList(),
      'plannedEvents': plannedEvents?.map((e) => e.toJson()).toList(),
      'additives': additives.map((add) => safelyConvertMap(add)).toList(),
      'yeast': yeast != null ? safelyConvertMap(yeast!) : null,
      'createdAt': createdAt.toIso8601String(),
      'tags': tags.map((tag) => tag.toJson()).toList(),
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
    };
  }

  factory BatchModel.fromJson(Map<String, dynamic> json) => BatchModel(
        id: json['id'],
        name: json['name'],
        recipeId: json['recipeId'],
        startDate: DateTime.parse(json['startDate']),
        createdAt: DateTime.parse(json['createdAt']),
        tags: (json['tags'] as List).map((tagJson) => Tag.fromJson(tagJson)).toList(),
        bottleDate: json['bottleDate'] != null ? DateTime.parse(json['bottleDate']) : null,
        batchVolume: json['batchVolume'],
        fermentationStages: (json['fermentationStages'] as List)
            .map((fsJson) => FermentationStage.fromJson(Map<String, dynamic>.from(fsJson)))
            .toList(),
        measurementLogs: List<Map<String, dynamic>>.from(json['measurementLogs'] ?? []),
        status: json['status'] ?? 'Planning',
        notes: json['notes'],
        deductedIngredients: Map<String, bool>.from(json['deductedIngredients'] ?? {}),
        type: json['type'],
        plannedOg: json['plannedOg'],
        plannedAbv: json['plannedAbv'],
        ingredients: List<Map<String, dynamic>>.from(json['ingredients'] ?? []),
        plannedEvents: (json['plannedEvents'] as List?)
            ?.map((eJson) => PlannedEvent.fromJson(eJson))
            .toList(),
        additives: List<Map<String, dynamic>>.from(json['additives'] ?? []),
        yeast: json['yeast'] != null ? Map<String, dynamic>.from(json['yeast']) : null,
        og: json['og'],
        fg: json['fg'],
        abv: json['abv'],
        measurements: (json['measurements'] as List)
            .map((mJson) => Measurement.fromJson(mJson))
            .toList(),
        fsuDate: json['fsuDate'] != null ? DateTime.parse(json['fsuDate']) : null,
        prepNotes: json['prepNotes'],
        tastingRating: json['tastingRating'],
        tastingNotes:
            json['tastingNotes'] != null ? Map<String, String>.from(json['tastingNotes']) : null,
        packagingMethod: json['packagingMethod'],
        finalYield: json['finalYield'],
        packagingDate: json['packagingDate'] != null ? DateTime.parse(json['packagingDate']) : null,
        finalNotes: json['finalNotes'],
        finalYieldUnit: json['finalYieldUnit'],
      );
}
