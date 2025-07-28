import 'package:hive/hive.dart';

part 'measurement_log.g.dart';

@HiveType(typeId: 12)
class MeasurementLog {
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
}
