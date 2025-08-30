// lib/models/measurement.dart
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

part 'measurement.g.dart';

@HiveType(typeId: 6)
class Measurement {
  /// 🔑 Stable string id used in your app logic (not a Hive key).
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime timestamp;

  @HiveField(2)
  double? gravity;

  @HiveField(3)
  double? temperature;

  @HiveField(4)
  String? notes;

  @HiveField(5)
  String? gravityUnit;

  @HiveField(6)
  List<String>? interventions;

  @HiveField(7)
  double? ta;

  @HiveField(8)
  double? brix;

  @HiveField(9)
  double? sgCorrected;

  @HiveField(10)
  double? fsuspeed;

  @HiveField(11, defaultValue: false)
  final bool fromDevice;

  Measurement({
    String? id,
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
    this.fromDevice = false,

  }) : id = id ?? const Uuid().v4();

Measurement copyWith({
  String? id,
  DateTime? timestamp,
  double? gravity,
  double? temperature,
  String? notes,
  String? gravityUnit,
  List<String>? interventions,
  double? ta,
  double? brix,
  double? sgCorrected,
  double? fsuspeed,
  bool? fromDevice, // <- add
}) {
  return Measurement(
    id: id ?? this.id,
    timestamp: timestamp ?? this.timestamp,
    gravity: gravity ?? this.gravity,
    temperature: temperature ?? this.temperature,
    notes: notes ?? this.notes,
    gravityUnit: gravityUnit ?? this.gravityUnit,
    interventions: interventions ?? this.interventions,
    ta: ta ?? this.ta,
    brix: brix ?? this.brix,
    sgCorrected: sgCorrected ?? this.sgCorrected,
    fsuspeed: fsuspeed ?? this.fsuspeed,
    fromDevice: fromDevice ?? this.fromDevice, // <- keep it
  );
}


  Map<String, dynamic> toJson() => {
        'id': id,
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
        'fromDevice': fromDevice,
      };

  factory Measurement.fromJson(Map<String, dynamic> json) => Measurement(
        id: (json['id'] as String?) ?? const Uuid().v4(),
        timestamp: DateTime.parse(json['timestamp'] as String),
        gravity: (json['gravity'] as num?)?.toDouble(),
        temperature: (json['temperature'] as num?)?.toDouble(),
        notes: json['notes'] as String?,
        gravityUnit: json['gravityUnit'] as String?,
        interventions: json['interventions'] != null
            ? List<String>.from(json['interventions'] as List)
            : null,
        ta: (json['ta'] as num?)?.toDouble(),
        brix: (json['brix'] as num?)?.toDouble(),
        sgCorrected: (json['sgCorrected'] as num?)?.toDouble(),
        fsuspeed: (json['fsuspeed'] as num?)?.toDouble(),
        fromDevice: (json['fromDevice'] as bool?) ?? (json['source'] == 'device'),

      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Measurement && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
