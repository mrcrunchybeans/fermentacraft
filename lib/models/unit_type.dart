import 'package:hive_flutter/hive_flutter.dart';

part 'unit_type.g.dart';

@HiveType(typeId: 24)
enum UnitType {
  @HiveField(0)
  volume,

  @HiveField(1)
  mass,

  @HiveField(2)
  temperature,

  @HiveField(3)
  gravity,
}
