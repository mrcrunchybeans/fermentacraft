import 'package:hive/hive.dart';

part 'fermentation_stage.g.dart';

@HiveType(typeId: 11)
class FermentationStage {
  @HiveField(0)
  String name;

  @HiveField(1)
  DateTime startDate;

  @HiveField(2)
  int durationDays;

  @HiveField(3)
  double? targetTempC;

  FermentationStage({
    required this.name,
    required this.startDate,
    required this.durationDays,
    this.targetTempC,
  });
}
