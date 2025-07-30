import 'package:hive/hive.dart';

// This line is needed for Hive's code generator
part 'measurement.g.dart';

@HiveType(typeId: 16)
class Measurement {
  @HiveField(0)
  final DateTime timestamp;

  @HiveField(1)
  final double? temperature; // Stored in °C

  @HiveField(2)
  final double? sg; // Specific Gravity

  @HiveField(3)
  final double? brix;

  @HiveField(4)
  final String gravityUnit; // 'sg' or 'brix'

  @HiveField(5)
  final String? note;

  @HiveField(6)
  double? fsuspeed; // This will store the calculated speed

  @HiveField(7)
  double? ta; // Titratable Acidity

  @HiveField(8)
  List<String> interventions; // List of intervention names

  @HiveField(9)
  double? sgCorrected; // Temperature-corrected SG

  Measurement({
    required this.timestamp,
    required this.gravityUnit,
    this.temperature,
    this.sg,
    this.brix,
    this.note,
    this.fsuspeed,
    this.ta,
    this.interventions = const [], // Default to an empty list
    this.sgCorrected,
  });
}