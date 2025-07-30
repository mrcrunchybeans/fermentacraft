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
  DateTime? bottleDate; // Used for "Packaging Date"

  @HiveField(5)
  double? batchVolume;

  @HiveField(6)
  List<FermentationStage> fermentationStages;
  List<FermentationStage> get safeFermentationStages => fermentationStages;

  @HiveField(7)
  List<Map<String, dynamic>> measurementLogs; // Kept for legacy if needed

  @HiveField(8)
  String status; // Planning, Brewing, Fermenting, Completed

  @HiveField(9)
  String? notes; // Used for "Lessons Learned" / Final Notes

  @HiveField(10)
  Map<String, bool> deductedIngredients; // name → deducted

  @HiveField(11)
  String? type; // e.g., Cider, Wine, Mead

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
    this.fsuDate,
    this.measurements = const [],
    this.packagingDate,
    this.finalNotes,
    // ✅ NEW Constructor parameters
    this.tastingRating,
    this.tastingNotes,
    this.packagingMethod,
    this.finalYield,
  })  : fermentationStages = fermentationStages ?? [],
        measurementLogs = measurementLogs ?? [],
        deductedIngredients = deductedIngredients ?? {},
        ingredients = ingredients ?? [],
        plannedEvents = plannedEvents ?? [],
        additives = additives ?? [];
}