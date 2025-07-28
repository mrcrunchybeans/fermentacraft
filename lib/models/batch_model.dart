import 'package:hive/hive.dart';
import 'fermentation_stage.dart';
import 'measurement_log.dart';

part 'batch_model.g.dart';

@HiveType(typeId: 10)
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
  List<FermentationStage> stages;

  @HiveField(7)
  List<MeasurementLog> measurementLogs;

  @HiveField(8)
  String status; // Planning, Brewing, Fermenting, Completed

  @HiveField(9)
  String? notes;

  @HiveField(10)
  Map<String, bool> deductedIngredients; // name → deducted

  BatchModel({
    required this.id,
    required this.name,
    required this.recipeId,
    required this.startDate,
    this.bottleDate,
    this.batchVolume,
    this.stages = const [],
    this.measurementLogs = const [],
    this.status = 'Planning',
    this.notes,
    this.deductedIngredients = const {},
  });
}
