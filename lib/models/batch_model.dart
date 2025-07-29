import 'package:flutter_application_1/models/planned_event.dart';
import 'package:hive/hive.dart';
import 'fermentation_stage.dart';
import 'measurement_log.dart';
import 'tag.dart';
import 'measurement.dart';


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
  List<MeasurementLog> measurementLogs;

  @HiveField(8)
  String status; // Planning, Brewing, Fermenting, Completed

  @HiveField(9)
  String? notes;

  @HiveField(10)
  Map<String, bool> deductedIngredients; // name → deducted

  // ✅ NEW FIELDS for Planning Tab
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

  @HiveField(24) // Use the next available index
  DateTime? fsuDate;




  // ✅ Constructor
BatchModel({
  required this.id,
  required this.name,
  required this.recipeId,
  required this.startDate,
  required this.createdAt,
  required this.tags,
  this.bottleDate,
  this.batchVolume,
  List<FermentationStage>? fermentationStages,
  
  List<MeasurementLog>? measurementLogs,
  this.status = 'Planning',
  this.notes,
  Map<String, bool>? deductedIngredients,
  this.type,
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
})  : fermentationStages = fermentationStages ?? [],
      measurementLogs = measurementLogs ?? [],
      deductedIngredients = deductedIngredients ?? {},
      ingredients = ingredients ?? [],
      plannedEvents = plannedEvents ?? [],
      additives = additives ?? [];
}