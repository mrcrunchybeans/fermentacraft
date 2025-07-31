import 'package:hive/hive.dart';

part 'measurement.g.dart';

@HiveType(typeId: 6)
class Measurement extends HiveObject {
  @HiveField(0)
  DateTime timestamp;

  @HiveField(1)
  double? gravity;

  @HiveField(2)
  double? temperature;

  @HiveField(3)
  String? notes;

  @HiveField(4)
  String? gravityUnit;

  @HiveField(5)
  List<String>? interventions;

  @HiveField(6)
  double? ta;

  @HiveField(7)
  double? brix;

  @HiveField(8)
  double? sgCorrected;

  @HiveField(9)
  double? fsuspeed;

  Measurement({
    required this.timestamp,
    this.gravity,
    this.temperature,
    this.notes,
    this.gravityUnit,
    this.interventions,
    this.ta,
    this.brix,
    this.sgCorrected,
    this.fsuspeed,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'gravity': gravity,
        'temperature': temperature,
        'notes': notes,
        'gravityUnit': gravityUnit,
        'interventions': interventions,
        'ta': ta,
        'brix': brix,
        'sgCorrected': sgCorrected,
        'fsuspeed': fsuspeed,
      };

  factory Measurement.fromJson(Map<String, dynamic> json) => Measurement(
        timestamp: DateTime.parse(json['timestamp']),
        gravity: json['gravity'],
        temperature: json['temperature'],
        notes: json['notes'],
        gravityUnit: json['gravityUnit'],
        interventions: json['interventions'] != null
            ? List<String>.from(json['interventions'])
            : null,
        ta: json['ta'],
        brix: json['brix'],
        sgCorrected: json['sgCorrected'],
        fsuspeed: json['fsuspeed'],
      );
}
