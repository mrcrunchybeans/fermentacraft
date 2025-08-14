import 'package:hive_flutter/hive_flutter.dart';
part 'user_yeast.g.dart';

@HiveType(typeId: 91) // pick a free id
class UserYeast extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String? notes;

  @HiveField(2)
  double? minTempC;

  @HiveField(3)
  double? maxTempC;

  UserYeast({required this.name, this.notes, this.minTempC, this.maxTempC});
}
