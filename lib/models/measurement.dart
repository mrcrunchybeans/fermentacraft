import 'package:hive/hive.dart';
import '../utils/fsu_utils.dart';
import '../utils/gravity_utils.dart';

part 'measurement.g.dart';

@HiveType(typeId: 16)
class Measurement {
  @HiveField(0)
  DateTime timestamp;

  @HiveField(1)
  double? temperature; // °C by default

  @HiveField(2)
  double? sg;

  @HiveField(3)
  double? brix;

  @HiveField(4)
  String gravityUnit; // 'sg' or 'brix'

  @HiveField(5)
  String? note;

  Measurement({
    required this.timestamp,
    this.temperature,
    double? specificGravity,
    double? brixValue,
    this.gravityUnit = 'sg',
    this.note,
  }) {
    if (gravityUnit == 'sg' && specificGravity != null) {
      sg = specificGravity;
      brix = sgToBrix(specificGravity);
    } else if (gravityUnit == 'brix' && brixValue != null) {
      brix = brixValue;
      sg = brixToSg(brixValue);
    }
  }

  double? get fsu {
    if (temperature != null && sg != null) {
      return calculateFSU(temperature!, sg!);
    }
    return null;
  }
}
