import 'package:hive/hive.dart';

part 'fermentation_stage.g.dart';

@HiveType(typeId: 11)
class FermentationStage {
  @HiveField(0)
  String name;

  @HiveField(1)
  DateTime? startDate;

  @HiveField(2)
  int durationDays;

  @HiveField(3)
  double? targetTempC;

  FermentationStage({
    required this.name,
    this.startDate,
    required this.durationDays,
    this.targetTempC,
  });

  // Factory to convert from legacy Map<String, dynamic>
  factory FermentationStage.fromMap(Map<String, dynamic> map) {
    return FermentationStage(
      name: map['name'] ?? '',
      startDate: map['startDate'] != null
          ? DateTime.tryParse(map['startDate'].toString())
          : null,
      durationDays: map['durationDays'] ?? map['days'] ?? 0,
      targetTempC: (map['targetTempC'] ?? map['temp'])?.toDouble(),
    );
  }

  // Convert back to map if needed
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'startDate': startDate?.toIso8601String(),
      'durationDays': durationDays,
      'targetTempC': targetTempC,
    };
  }
}
