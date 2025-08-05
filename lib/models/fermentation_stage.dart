import 'package:hive/hive.dart';

part 'fermentation_stage.g.dart';

@HiveType(typeId: 1)
class FermentationStage extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  int durationDays;

  @HiveField(2)
  double? targetTempC;

  @HiveField(3)
  DateTime? startDate;

  FermentationStage({
    required this.name,
    required this.durationDays,
    this.targetTempC,
    this.startDate,
  });

  // For data export/import
  Map<String, dynamic> toJson() => {
        'name': name,
        'durationDays': durationDays,
        'targetTempC': targetTempC,
        'startDate': startDate?.toIso8601String(),
      };

  factory FermentationStage.fromJson(Map<String, dynamic> json) => FermentationStage(
    name: json['name'] ?? 'Unnamed Stage',
    durationDays: json['durationDays'] ?? 0,
    targetTempC: (json['targetTempC'] != null) ? (json['targetTempC'] as num).toDouble() : null,
    startDate: json['startDate'] != null ? DateTime.parse(json['startDate']) : null,
  );


  FermentationStage copy() {
    return FermentationStage(
      name: name,
      startDate: startDate,
      durationDays: durationDays,
      targetTempC: targetTempC,
    );
  }
}
