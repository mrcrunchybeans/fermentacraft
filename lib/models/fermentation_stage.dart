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

  // --- ADDED for data export/import ---
  Map<String, dynamic> toJson() => {
        'name': name,
        'durationDays': durationDays,
        'targetTempC': targetTempC,
        'startDate': startDate?.toIso8601String(),
      };

  factory FermentationStage.fromJson(Map<String, dynamic> json) => FermentationStage(
        name: json['name'],
        durationDays: json['durationDays'],
        targetTempC: json['targetTempC'],
        startDate: json['startDate'] != null ? DateTime.parse(json['startDate']) : null,
      );
  // --- END of added code ---

  // Helper method from your previous code
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'durationDays': durationDays,
      'targetTempC': targetTempC,
      'startDate': startDate?.toIso8601String(),
    };
  }

  factory FermentationStage.fromMap(Map<String, dynamic> map) {
    return FermentationStage(
      name: map['name'],
      durationDays: map['durationDays'],
      targetTempC: map['targetTempC'],
      startDate: map['startDate'] != null ? DateTime.parse(map['startDate']) : null,
    );
  }
}
