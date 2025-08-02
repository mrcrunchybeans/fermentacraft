import 'package:hive/hive.dart';

part 'measurement_log.g.dart';

@HiveType(typeId: 12)
class MeasurementLog extends HiveObject { // Added extends HiveObject
  @HiveField(0)
  DateTime timestamp;

  @HiveField(1)
  double sg;

  @HiveField(2)
  double? tempC;

  @HiveField(3)
  double? pH;

  MeasurementLog({
    required this.timestamp,
    required this.sg,
    this.tempC,
    this.pH,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'sg': sg,
      'tempC': tempC,
      'pH': pH,
    };
  }

  // Add this factory for consistency
  factory MeasurementLog.fromJson(Map<String, dynamic> json) {
    return MeasurementLog(
      timestamp: DateTime.parse(json['timestamp']),
      sg: (json['sg'] as num).toDouble(),
      tempC: (json['tempC'] as num?)?.toDouble(),
      pH: (json['pH'] as num?)?.toDouble(),
    );
  }
}